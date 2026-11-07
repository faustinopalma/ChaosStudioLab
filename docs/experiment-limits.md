# Experiment limits and interpretation

[Lab guide](lab-guide.md) · [App Service results](app-service-results.md) · [AKS plan](aks-lab.md) · [AKS results](aks-results.md)

Evidence date for the App Service measurements: 6 November 2026. AKS design date: 7 November 2026; measured AKS verdicts remain pending.

## Separate the verdicts

Each test must publish fault eligibility, accepted targeting, actual effect, sustained duration where required, automatic recovery, full-phase availability and acknowledged-write retention separately.

- **PASS** requires the evidence and thresholds for the named gate.
- **FAIL** records an executed or observed condition that misses its required gate.
- **BLOCKED** records missing eligibility or a safety/evidence prerequisite that prevents qualifying execution.
- **PENDING** records work without a completed qualifying result.

Do not derive a complete-suite PASS from a subset of passed cases. Preserve failed and blocked attempts when a later runtime, topology or package qualifies.

## App Service process-crash scope

The measured Windows Actions killed application dotnet worker processes on one exact App Service instance and on both instances associated with the selected physical zone. App Service restarted those processes in place. The workers' instance identities and zone placement persisted through the measured effects.

Those experiments establish routing and recovery during discrete process loss under the recorded load. They leave the App Service worker hosts, zone infrastructure, ingress and shared networking outside the demonstrated fault effect. The 11–13 s or 12.7 s process-start intervals describe process replacement timing; zero business failures describe the independent client outcome.

Windows native validation rejected an explicit `processName`. The scenarios omitted it, and out-of-process hosting allowed the measured default target to be the dotnet application worker. Eligibility of that runtime/hosting combination needs requalification before reuse.

### Linux support evidence

Where process listing succeeded on .NET 8, .NET 9 and Node.js 22, actual deletion returned HTTP 400 `This runtime stack is not yet supported on Linux`. Other tested stacks encountered listing blockers: .NET 10/11 returned 409 through dotnet-monitor, Python 3.13/Java 21/container listing returned 400, and Node.js 24 listed no processes.

Listing success, selector validation and a documented template each cover distinct prerequisites. Actual unsupported deletion left Linux application and combined coverage BLOCKED. Windows outcomes apply to the Windows variant.

### Windows connection-open finding

Npgsql's `GSS Encryption Mode=Prefer` caused Kerberos/SSPI probing during cold physical opens on Windows App Service. Measured physical-open time fell from 4.7–5.1 s to 0.22–0.60 s after disabling GSS encryption probing. TLS certificate/hostname verification and Entra token authentication remained unchanged.

This finding addresses the observed Windows cold-open stall. It supplies no general database-failover guarantee and should retain its platform attribution when comparing with the .NET 10 AKS container.

## PostgreSQL forced failover

The App Service database case exercised a native forced failover, role/zone transition and application reconnection. Recovery and durability passed at 36.359 s. Full-phase availability failed at 97.347%. The combined case recorded 34.989 s recovery and 97.324% full-phase availability.

Those outcomes show that all acknowledged writes survived and service recovered under the measured load, while some scheduled operations failed or were dropped during disruption. Latency percentiles for successful operations exclude failed requests; publish failures, dropped operations and canary gaps alongside p95.

A managed forced failover leaves the underlying host-failure and physical-zone-loss mechanisms outside directly demonstrated coverage. For the AKS comparison, record the actual failover mode, primary/standby transition, accepted native operation, observed dependency failure and recovery separately.

## Combined overlap

The Windows combined case observed database disruption first, then submitted the process kill. Independently observed database failures bracketed process replacement, with no healthy sample between the bracketing failures. This supports the reported overlap within the observation resolution.

The new AKS combined case likewise requires database-first triggering and independently observed dependency failure during actual selected-zone node shutdown. Simultaneous submissions or overlapping native Action timelines alone leave the business-effect overlap unverified. Report sample cadence, timestamps and any observation gap.

## AKS compute shutdown and physical-zone scope

The new native fault path targets node VM scale sets. The selected live Action accepts `GracefulShutdown` and `Zones`; it has no instance-ID parameter.

| Intended experiment | Required target/effect evidence | Coverage boundary |
| --- | --- | --- |
| Exact application node | One owned single-node user-pool VMSS mapped to one Kubernetes node; actual power-off and NotReady | One application compute node and its workloads |
| Selected-zone compute | All owned system/user VMSS selected with zone 1; expected two user nodes and one system node physically off | Lab-owned AKS compute in the selected zone |
| Database forced failover | Native operation, observed dependency errors, role/zone transition | Managed database failover and application reconnection |
| Combined | Database failure independently overlaps actual selected-zone node shutdown | Correlated tested dependency/compute effects |
| HA-AZ-001 | Supported broader physical full-zone injection and independent effect proof | Remains BLOCKED; no physical full-zone injection is planned |

The private internal load balancer, shared networking and AKS control plane are outside the planned physical fault targets. A concurrent PostgreSQL forced failover adds a tested dependency effect, while ingress, network, control-plane and managed-host disaster behavior remain unverified.

### Sustained window and service remediation

Require a continuous five-minute physically-off interval, supported by ARM VM power-state snapshots and Kubernetes NotReady observations. Correlate each VMSS node with its Kubernetes identity, physical zone and workload placement. Readiness alone cannot establish power-off: a node can become NotReady because of connectivity or reporting delays.

Record the actual shutdown state, including whether the service stops or deallocates instances, the configured `GracefulShutdown` value, and the verified restore-on-stop behavior. Verify restoration after Action completion or abort. Action duration by itself supplies no continuous-effect proof.

Static pools, disabled autoscaling and disabled NAP make the intended capacity explicit. AKS reconciliation or remediation may still restart or replace nodes. Record every replacement, power-state transition and pod reschedule. A restart or replacement that shortens the required five-minute fault window fails the sustained-fault gate, even when business availability remains good.

Surviving pods may reschedule onto healthy capacity. Report scheduling constraints and any relaxation needed for recovery; baseline six-node spread and post-fault capacity are distinct observations.

## Load, durability and comparison boundaries

The planned AKS load is 20 scheduled business operations/s plus one independent canary/s, with bounded maximums of 200 business VUs and 10 canary VUs. Dropped work remains part of the availability record. Preserve the offered rate, request mix, payload size, deadlines, build identity and observation cadence for comparison.

Reconcile every acknowledged write and checksum across the complete attributable history. The App Service total of 92,616 writes belongs to its 31 historical runs. AKS totals must be measured and reported separately; no new retention success is inferred from the older total.

The comparison changes hosting platform, runtime, ingress and compute fault mechanism. Report these changes rather than attributing every difference in availability to one platform choice. Baseline checks, elapsed provisioning/troubleshooting/measurement time, and full-phase denominators must accompany final conclusions.

The historical App Service lab queried telemetry through AMPLS. The initial AKS lab deploys no AMPLS or Log Analytics: application logs use the private Kubernetes API, and the remote runner's independent observer and node-topology monitor capture the client and topology evidence. Keep all raw evidence under ignored `.local\`. Publish sampling cadence and missing observation intervals; lost API/log access cannot by itself prove node power-off.

## Lifecycle and retention

The App Service dedicated groups were deleted by the operator on 6 November at 09:43 UTC; seven unrelated groups and 24 resources were verified unchanged. Historical execution reports describe resource state at their original evidence time.

The new AKS lab remains active until the operator orders stop or deletion. No independent expiry enforcement is claimed. Resource-group absence alone does not establish deletion of retained backups, audit records or recoverable vault objects.

## Official fault-scope references

- [Chaos Studio AKS guidance](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-guidance)
- [Chaos Studio Scenarios](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-scenarios)
- [Workspace supported resources](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources)

Supported catalog entries, exact live Action parameters and observed effects must be recorded together; documentation alone supplies no execution verdict.
