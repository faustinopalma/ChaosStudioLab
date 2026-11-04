# Project status

This document contains dated notes and project progress. It can be deleted without changing the README, specification, or research documentation. Those documents do not link to this file.

Last updated: 4 November 2026  
Research last verified: 3 November 2026

## Current phase

The Sweden Central stack provisioned successfully with private access and cross-zone PostgreSQL HA. Managed-identity migration, immutable image publication, authenticated API integration and private telemetry passed.

- Full warmup: 6,001 successful operations, zero failures/drops, p95 29 ms.
- Full baseline: 12,001 successful operations, zero failures/drops, p95 27 ms; 601 successful canaries.
- Genuine Chaos PostgreSQL forced failover: exact single target, native Succeeded and observed primary/standby swap.
- Recovery: **38.624 seconds**, with a complete qualifying sixty-second window and p95 20 ms.
- Full injected phase: 97.118% business success; its stricter full-phase availability gate failed during the outage and remains separately recorded.
- Post-fault durability: all **3,558** unique acknowledged writes retained with matching checksums, including **340** acknowledged before action start; zero acknowledged loss.
- Native Suspend/Resume: observed stopped/deallocated/zero-active/minimum-zero state and restored Ready/Healthy/six-replica/minimum-three state, with privacy and HA configuration preserved.
- Post-resume checks: the same **3,558** writes retained, two controller registrations without duplicate associations, and sixty-second private baselines passing at p95 56/57 ms.

The [execution report](docs/first-cycle-results.md) records observed lifecycle/cleanup outcomes and the complete failed-attempt chronology. The [repeatable method](docs/lab-cycle-method.md) identifies concrete commands, prerequisites and timing causes.

Real context, raw evidence, validation state and generated keys stay in ignored local paths. Build/cycle/Resume block missing, expired or drifted exemptions and give manual create-or-extend guidance. No PIM, pricing/budget queries, excluded-feature registration, broad exemption or unrelated-resource deletion was used.

Three [editable Inkscape diagrams](docs/diagrams/README.md), their PNG previews and the illustrated architecture guide remain the design walkthrough. API unit tests pass 9/9; targeted production-code regressions cover bootstrap, private transport, exact discovery, dispatch, recovery timestamps, durability, lifecycle context, schedule bindings and publication.

## Decision review

The [accepted decisions](DECISIONS-ACCEPTED.md) contain D01-D16. D13 selects Azure-allocated Standard static IPv4 and excludes BYOIP and feature registration. D14 removes Firewall, its hub, DNS proxy and appliance UDRs. Two directly peered VNets use Azure DNS/private-zone links, operations NAT/Bastion, and retained private service access. D15 constrains the separately approved temporary exemption.

Live investigation found an inherited public-IP append policy adding `FirstPartyUsage=/Unprivileged`. Its rule, assignment and initiative contained no RG-tag opt-out. Exact identifiers stay in ignored local evidence. The helper still rejects conflicting payloads. The D15 waiver was created only after explicit user authorization; no invented tag or feature registration was used.

Official compilation, ARM validation and exact-owned previews preceded deployments. Effective public-IP payloads, private endpoint contracts, identity-dependent IDs and source-derived preview repairs were verified without relaxing the ownership guard. The complete infrastructure and subsequent private runtime succeeded.

The entire lab, including its network and management resources, must be created and deleted. Mandatory Azure-managed remnants are accepted; avoidable purge protection remains disabled.

## Remaining qualification

A disconnected 24-hour soak, delayed automatic dispatch, later PostgreSQL automatic-restart reconciliation, explicit-replica/combined faults, preview cancellation and interrupted-run recovery still require qualification. Initial failed-build watchdog enforcement and the unified crash-safe journal remain engineering gaps. See the [readiness assessment](docs/development-readiness.md).

## Validation gap

HA-AZ-001 is blocked until a supported injection method and evidence of correlated real-zone loss are established. Component tests provide bounded evidence and cannot close this gap alone.

## Next steps

Use the measured bounded cycle as the development baseline and preserve its exact scope/thresholds. Follow the readiness sequence for remaining engineering and broader acceptance. Fresh execution requires a new manifest, approved private context, any required finite exemption and current validation. Keep `HA-AZ-001` blocked until qualifying real-zone evidence is obtained.

The [research document](docs/research.md) records the platform capabilities and constraints supporting the design.
