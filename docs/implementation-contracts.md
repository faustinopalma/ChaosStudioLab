# Implementation contracts

This document pins the first implementation's API, persistence, measurement, and deployment contracts. It complements the [implementation specification](specification.md) and [accepted decisions](../DECISIONS-ACCEPTED.md).

## 1. Region and deployment boundary

- The project default remains `westeurope` as recorded in D05.
- Deployment defaults select `swedencentral` under D16. The inherited policy denies West Europe. North Europe's SKU catalog advertises the required HA mode, but its subscription-level `zoneRedundantHaSupported` is `Disabled` and actual creation was rejected. Require top-level `restricted: Disabled` and `zoneRedundantHaSupported: Enabled` before provisioning.
- Sweden Central passes those flags and lists the required SKU/zones and Chaos failover Action. Actual healthy cross-zone server creation remains a separate live gate. The North Europe adapter is retained for contexts where eligibility passes. D05's historical project default remains subject to current capability checks.
- The lab uses three new resource groups for networking, workload, and operations. Every deployment target, generated resource, role assignment, and deletion must be recorded in the per-run ownership manifest. No resource outside those new groups is in scope for mutation or deletion.
- Subscription and tenant-wide policy assignments, role assignments, provider registrations, and existing resources are outside the lab's mutation scope. Required providers were already registered during preflight.

Identity bootstrap exports only the five independent managed-identity resource declarations from the compiled workload/operations modules. The operator validates and creates this bounded prerequisite phase first. Before the full preview/deployment, resolve `id-csl-migrations` in the owned workload group and `id-csl-runner`/`id-csl-control` in the owned operations group. Require exact resource IDs, manifest membership, matching ownership tags and nonempty GUID principals. Supply them as `infra/main.bicep`'s `prerequisitePrincipalIds.migration`, `.runner` and `.control`, propagated through the validation wrapper and relevant administrator/role modules. ARM what-if can leave `reference()` values unresolved after identity creation; literal verified parameters preserve exact-ID preview safety.

## 2. Order API

All business endpoints require a bearer token held as a Key Vault secret and injected into the app through a managed-identity Key Vault reference. The token is generated per deployment, is not written to source control, and is readable only by the app and private test runner. Readiness and liveness probes remain available to the platform; no HTTP chaos-control endpoint is exposed.

### Create request

`POST /api/orders`

```json
{
  "operationId": "2f7e6793-46a9-4c62-a6b8-8935e9d45f5a",
  "payload": {
    "sku": "demo-001",
    "quantity": 2,
    "notes": "synthetic test order"
  }
}
```

- `operationId` is a non-empty client-generated GUID and is the durable idempotency key.
- `sku` is trimmed and must contain 1-64 characters.
- `quantity` must be between 1 and 10,000.
- `notes` is trimmed, may be null, and is limited to 1,000 characters.
- The normalized payload is serialized with the .NET web JSON defaults in property order `sku`, `quantity`, `notes`. The payload checksum is lower-case hexadecimal SHA-256 over those UTF-8 bytes.

### Responses

| Status | Meaning |
| --- | --- |
| `201 Created` | A new durable row was committed before success was returned. |
| `200 OK` | The same operation ID and checksum already exist; the existing row is returned. |
| `400 Bad Request` | The request violates the payload contract. |
| `401 Unauthorized` | The bearer token is absent or invalid. |
| `409 Conflict` | The operation ID is already committed with a different payload checksum. |
| `503 Service Unavailable` | Database recovery exceeded the bounded retry/request deadline or the database remains unavailable. |

Both successful responses include `operationId`, normalized payload, `payloadSha256`, `createdAtUtc`, `replayed`, replica ID, revision, optional `runId`, and trace ID. The API does not claim that a timed-out request failed to commit; the client reconciles its operation ID through `GET`.

### Read and health endpoints

- `GET /api/orders/{operationId}` returns the committed row, or `404` when it is absent. It requires the same bearer token as writes.
- `GET /health/live` checks only the process.
- `GET /health/ready` checks the database with a one-second bound and the local readiness-fault lease. Temporary database failure does not alter liveness.
- `GET /health/dependencies` returns dependency status only with the bearer token.
- The test-only readiness fault is a bounded local file written through authenticated Container Apps replica execution. Its maximum TTL is 300 seconds; the helper is not an HTTP endpoint.

## 3. Persistence and retry contract

`orders.operation_id` is the primary key. Each row stores the normalized JSON payload, its SHA-256 checksum, and a UTC creation timestamp. Creation uses an insert-on-conflict transaction followed by a read of the durable row. Equal checksums are idempotent replays; different checksums return `409 Conflict`.

The app obtains PostgreSQL Entra tokens through `DefaultAzureCredential` and Npgsql's periodic password provider for the `https://ossrdbms-aad.database.windows.net/.default` scope. TLS uses full certificate/hostname verification. The runtime identity receives only database connect and required table permissions; migration credentials are separate.

Each server operation has a five-second deadline and at most two retries for transient connection, I/O, and timeout failures, with bounded exponential delays and jitter. Every final transient failure becomes an explicit `503`; acknowledged writes are returned only after the database commit completes. Client-side retries reuse the same operation ID for up to 180 seconds and reconcile unknown outcomes through `GET`.

## 4. Measurement contract

- The load generator schedules 20 business operations per second with an open arrival-rate model; 80% are reads and 20% are writes.
- The journal records every business endpoint attempt, reconciliation request, canary tick, and dropped scheduled iteration. Raw-attempt success counts workload read/write requests and their retries; dropped workload iterations count as failed scheduled operations. Canary and write-reconciliation requests remain separately identifiable and do not inflate the 20-operation-per-second business denominator.
- A business operation succeeds when a read returns the requested checksum or a write is reconciled to a committed row. The business-operation success rate counts each scheduled read or logical write once, plus dropped workload iterations as failures. Attempt success and business-operation success are reported separately.
- Successful-operation p95 uses end-to-end logical business-operation duration. A write's duration includes client retries and checksum reconciliation; individual HTTP request durations remain in the raw journal.
- The independent one-second canary performs a read, a unique write, and a read-after-write verification. Canary results are reported separately and do not enter the workload denominator.
- A recovery window is 60 consecutive seconds with exactly one canary tick per second, at least 99% canary success, at least 99% business-operation success at the configured open arrival rate, and successful-operation p95 at most one second. Recovery duration starts at the first independently observed database disruption and ends at the beginning of that qualifying window.
- A zero recovery duration is valid only when independent evidence confirms that failover occurred without an observed application interruption. Missing or contradictory event evidence yields `INCONCLUSIVE`.
- Every issued write must reconcile as committed or confirmed absent. Unknown outcomes, duplicate logical writes, or checksum mismatches prevent a pass.
- Post-failover durability verification re-reads every unique issued write using its original operation ID and checksum. All acknowledged writes must remain present; unacknowledged writes must resolve to a matching row or confirmed absence. Resume repeats this verification against the original failover run. The private verifier reuses its HTTP session and writes separate phase verdicts.
- `HA-AZ-001` remains `BLOCKED` without both a supported real-zone injection and evidence tying the affected zone to the application path.

## 5. Run and ownership records

Each run records its UTC phase boundaries, run ID, source checksum, image digest, parameters, resource IDs, explicit Chaos target inventory, action timestamps, replica counts, PostgreSQL role and zone observations, per-attempt measurements, write reconciliation, private-connectivity checks, and cleanup result.

The ownership manifest is created before provisioning and records the generated deployment-instance ID, three exact resource-group IDs, every created resource ID, role assignment, DNS link, peering, public IP, private endpoint, secret name (never its value), and recoverable object requiring purge. Destruction refuses missing, mismatched, or foreign ownership data and never broadens the scope.

Public IPs follow [D13](../DECISIONS-ACCEPTED.md#d13-azure-allocated-public-ips-without-byoip): Azure-allocated Standard static IPv4, no prefix resource/reference, no supplied address on creation, and no public-IP `ipTags`. `Assert-LabPublicIpChanges` checks policy-adjusted what-if payloads before `Invoke-LabDeployment` issues a resource deployment. A registered BYOIP feature cannot authorize a conflicting payload. The earlier registration-state gate has been removed.

D14 removes Azure Firewall and the hub. Two directly peered VNets use Azure-provided DNS/private-zone links. Operations hosts NAT/Bastion, referencing two public IPs declared in the independently previewable network module. Private service access and ownership guards remain unchanged. `tests/Test-NetworkTopology.ps1` verifies the compiled topology and the operations-output Bastion tunnel. Standard NAT is a single-zone management egress dependency.

## 6. Implementation and verification state

- The initial .NET 10 API, PostgreSQL persistence, idempotency behavior, health probes, bearer-token requirement, and local readiness-fault helper are implemented. `/health/live` returned HTTP 200 in a local runtime smoke test without opening a database connection.
- `dotnet test .\src\Demo.Api.Tests\Demo.Api.Tests.csproj --configuration Release` passes 9 tests.
- `tests/load/scenario.js` implements the 20-operation-per-second, 80/20 workload, a separate one-second read/write/read-after-write canary, write retries, raw request events, and checksum reconciliation. `tests/load/run.ps1` writes per-run JSON, k6 metrics, and raw attempt events without writing the bearer token.
- `tests/load/evaluate-recovery.ps1` evaluates complete 60-second windows, business-operation success including dropped iterations, canary success, successful-operation p95, and independent failover evidence. Typed JSON timestamps preserve their UTC instant and fractional precision. Regressions cover `PASS`, `FAIL`, exact-99% including drops, zero-duration `INCONCLUSIVE`, positive/negative/half-hour offsets and fractional seconds.
- `tests/load/evaluate-durability.ps1` checks retained acknowledged writes and resolves unacknowledged outcomes through the private API. Its regressions cover deduplicated retries, exact checksums, absent unacknowledged writes, lost acknowledgements and explicit transport failures.
- `tests/load/Test-LoadRunner.ps1` uses a temporary mock k6 process to verify phase reports, dropped-iteration accounting, and token redaction without contacting Azure.
- Script syntax checks and real k6 1.5.0 format tests pass, including flat summaries, omitted zero-drop metrics, raw logging, and tagged `Point` records.
- Complete private provisioning, managed-identity migration, image publication, API integration, full warmup/baseline and genuine PostgreSQL failover have run in Sweden Central. Measured recovery passed at 38.624 seconds. The [execution report](first-cycle-results.md) records separate full-phase availability, durability, observed lifecycle and exact-cleanup evidence.
- Lifecycle manual requests and schedule associations use one deterministic, schema-versioned `ContextBase64` parameter. The worker validates the decoded target/identity/intent before Azure access. This avoids observed Linux Hybrid Worker multi-parameter misbinding. Registration verifies actual server-assigned association IDs and full details before reuse.

## 7. Remaining feasibility gates

The bounded-cycle evidence is recorded in the execution report. Broader qualification retains these gates:

1. Inspect inherited Deploy/Modify policy effects in each Bicep `what-if`, including policy-created resources and required tags. The PostgreSQL Advanced Threat Protection `DeployIfNotExists` effect is already known and must be included in cost and cleanup reporting.
   The observed public-IP append rule adds `FirstPartyUsage=/Unprivileged`; the authorized finite, one-reference Public-IP waiver resolved the declared-resource conflict. Future starts must revalidate that private waiver contract and effective payload. Do not register the BYOIP feature. Record ARM `NestedDeploymentShortCircuited` diagnostics as incomplete coverage and verify expanded payloads before claiming full validation.
2. Revalidate managed-identity permissions, directory bootstrap and private telemetry for each new environment; the first successful region provides bounded evidence.
3. Prototype non-interactive execution against an explicit Container Apps replica and prove the local readiness lease expires and clears.
4. Preserve private image/migration/test proof when changing region, runtime, network or identity adapters.
5. Qualify the real disconnected 24-hour schedule, delayed dispatch, repeated reconciliation and PostgreSQL's later automatic restart; schedule registration and short smoke tests cover narrower behavior.
6. Complete preview cancellation/interruption recovery, combined faults and real-zone evidence using the pinned API contracts.

Any failed gate stops provisioning before workload resources are created, or produces the specified `BLOCKED`/`INCONCLUSIVE` result when the failure is discovered during an approved isolated prototype. No HA, privacy, test, or cleanup criterion is relaxed to bypass a gate.
