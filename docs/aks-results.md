# Private AKS comparison results register

[Lab guide](lab-guide.md) · [AKS design and tests](aks-lab.md) · [Experiment limits](experiment-limits.md) · [Historical App Service results](app-service-results.md)

Status date: 7 November 2026. **Measured AKS outcomes are pending.** Scope and identities are deployed; private AKS/PostgreSQL infrastructure is provisioning. ARM validation passed with 42 Creates and five owned-identity Ignores. These validation counts describe the planned changes, rather than completed resource creates. No baseline, shutdown, failover or durability test is reported as executed.

## Qualified prerequisites and intended deployment

| Item | Available fact | Remaining evidence |
| --- | --- | --- |
| Authorization/scope | Autonomous implementation, deployment, repairs and tests authorized; scope and identities deployed; retain groups until operator stop/delete order | Completed infrastructure inventory and lifecycle state |
| ARM validation | Passed; 42 Creates and five owned-identity Ignores | Completed private AKS/PostgreSQL provisioning and actual resource inventory |
| Region/VM eligibility | Sweden Central `Standard_D4ds_v5` unrestricted in zones 1, 2 and 3; initial Italy North VM candidate restricted | Successful allocation and actual zone/node mapping |
| PostgreSQL catalog | Zone-redundant HA capability enabled | Live PostgreSQL 16, Healthy primary/standby roles and zones, private TLS/Entra connectivity |
| Kubernetes catalog | 1.35.9 checked as supported | Actual deployed version and healthy cluster |
| AKS shape | Standard, no NAP/autoscaling; three tainted system nodes and six single-node user pools planned | Nine-node inventory, baseline six-pod participation and actual spread |
| Native node contract | Live Action has `GracefulShutdown` and `Zones`, without instance IDs; shutdown definitions PT7M | Accepted targets and at least 300 s observed continuous power-off, shutdown state and restoration semantics |
| Selected-zone target configuration | Exactly system/z1a/z1b VMSS with zone 1 selected; other four user pools omitted to avoid empty-zone matches | Actual VMSS/node mapping and exactly three affected nodes |
| Node-group authorization | Runner Reader; Chaos Virtual Machine Contributor and Reader | Effective scoped grants, independent reads and actual fault-caller evidence |
| Private paths | Private API/public FQDN disabled; private application HTTPS, Premium registry, vault and database planned | Actual caller-specific DNS, routes, authentication and publication/pull proof |
| Runtime/logs | .NET 10 container reusing source; private Kubernetes API application logs; no initial AMPLS/Log Analytics | Published build, successful startup and actual private log collection |
| Workload probe | Process-live readiness retains endpoints during dependency outage; `/health/ready` remains qualification gate | Actual probe configuration, baseline/restored-health checks and independent business results |
| Independent observations | Remote runner observer and node-topology monitor planned; all raw evidence retained under ignored `.local\` | Complete attributable client/topology samples, power states and observation cadence |

Catalog qualification and ARM validation supply prerequisite evidence. Scope and identity deployment is recorded separately; completion of private AKS/PostgreSQL provisioning and baseline acceptance remain pending.

## Test verdicts

| Test | Execution/effect | Service recovery | Full-phase availability | Complete-history retention |
| --- | --- | --- | --- | --- |
| BASE-001 | **PENDING** | **PENDING** | **PENDING** | **PENDING** |
| HA-NODE-001 | **PENDING**: PT7M exact single-node shutdown; at least 300 s sustained effect | **PENDING** | **PENDING** | **PENDING** |
| HA-ZONE-COMPUTE-001 | **PENDING**: PT7M system/z1a/z1b targets; expected 3 nodes, at least 300 s sustained effect | **PENDING** | **PENDING** | **PENDING** |
| HA-DB-001 | **PENDING**: forced failover and role/zone transition | **PENDING** | **PENDING** | **PENDING** |
| HA-COMBINED-001 | **PENDING**: database-first disruption and independent node-effect overlap | **PENDING** | **PENDING** | **PENDING** |
| HA-AZ-001 | **BLOCKED**: no supported physical full-zone injection in the current plan | Unmeasured | Unmeasured | Unmeasured |

HA-AZ-001 has no injected physical full-zone result. The remaining tests have no published final metrics yet.

## Metrics awaiting evidence

| Measurement | AKS value |
| --- | --- |
| Baseline business success and successful-operation p95 | Pending |
| Per-phase scheduled successes, failures and drops | Pending |
| Independent canary successes, failures, drops and maximum complete outage gap | Pending |
| Exact-node actual effect, continuous off duration and restoration | Pending |
| Selected-zone expected/observed target counts and continuous off duration | Pending |
| Surviving pods, rescheduling and AKS restart/replacement events | Pending |
| PostgreSQL actual disruption, recovery-window start and stable-window qualification | Pending |
| Combined independently observed overlap and recovery | Pending |
| Per-phase and complete-history acknowledged-write/checksum totals | Pending |
| Provisioning, troubleshooting, measurement and reconciliation elapsed time | Pending |

## Publication requirements for final results

Replace pending values only from final attributable evidence. Preserve failed and blocked attempts, distinguish accepted Actions from independently verified effects, and publish sustained-window failure when AKS remediation weakens the intended fault.

Each final case needs actual target counts/zone placement, accepted fault parameters, power-state/NotReady evidence where applicable, surviving service, errors/drops, successful-operation p95, recovery/stable timing, complete-history checksum reconciliation and separate availability/durability verdicts. The combined case additionally needs independent dependency failures overlapping actual compute loss.

The approved database/combined gates remain 180 seconds to the beginning of a complete 60-second qualifying window with at least 99% business/canary success and successful-operation p95 at most one second, followed by 300 continuous stable seconds at 99.9% business success and baseline latency. Record explicit `/health/ready` qualification separately from Kubernetes process-live readiness and business recovery.

Record whether the node fault stopped or deallocated instances and how service restored them. Verify private Kubernetes API log collection and the independent runner observer/node-topology monitor, including sampling cadence and missing intervals. The initial lab omits AMPLS and Log Analytics; record any later justified observability change. Keep raw resource identifiers, authentication details and all raw evidence under ignored `.local\`.

## Comparison anchor: historical App Service

The measured Windows App Service comparison supplies the following historical reference:

- BASE-001: 100% business success, successful-operation p95 123 ms.
- Exact-instance process replacement: 12.7 s after acceptance; zero failed business operations.
- Selected-zone process replacements: 11–13 s; zero failed business operations.
- PostgreSQL recovery/durability: PASS, 36.359 s recovery; full-phase availability FAIL, 97.347%.
- Combined recovery/durability/overlap: PASS, 34.989 s recovery; full-phase availability FAIL, 97.324%.
- Retention: 92,616 acknowledged measurement writes across 31 Linux/Windows runs, all retained with matching checksums.
- Physical full-zone case: BLOCKED, never injected.

These measurements remain attributed to App Service. The .NET 10 container, private internal load balancer and sustained VMSS node shutdown introduce comparison differences that must accompany any AKS conclusion. Observation also changes from the historical App Service AMPLS path to private Kubernetes API logs and independent runner samples, with no initial AMPLS/Log Analytics deployment.

## Lifecycle

The earlier App Service dedicated groups were deleted by the operator on 6 November 2026 at 09:43 UTC. Seven unrelated groups and their 24 resources were verified unchanged.

The new scope and identities are deployed; private AKS/PostgreSQL infrastructure is provisioning after successful ARM validation. The lab is authorized to remain active until an operator stop/delete order. Completed infrastructure readiness, running/stopped state, fault restoration and later cleanup verification remain pending.
