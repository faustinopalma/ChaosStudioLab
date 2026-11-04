# Project status

This document contains dated notes and project progress. It can be deleted without changing the README, specification, or research documentation. Those documents do not link to this file.

Last updated: 4 November 2026  
Research last verified: 3 November 2026

## Current phase

Documentation now targets **private Azure App Service across three observed availability zones** under D17-D19. App Service requires both inbound Private Endpoint and outbound VNet Integration, private application/SCM DNS, and retained PostgreSQL HA. The three-zone gate checks the actual plan's capability and the application's observed `physicalZone`, health and traffic evidence.

The source refactor and fresh App Service deployment have not started. Existing templates/configuration/scripts still implement Container Apps. The revised workflow removes Automation/Hybrid Workers, automatic suspension and automatic destruction; deployment runs from the PC, tests are explicit and resource-group deletion is manual. No current App Service acceptance PASS is claimed.

The operator took over verification of the previous groups' deletion; final cleanup/purge has not been independently certified. No further background environment monitoring is authorized.

## Historical Container Apps cycle

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

## Historical decision review

The [accepted decisions](DECISIONS-ACCEPTED.md) preserve D01-D16 as the earlier record, with D17-D19 controlling the new App Service design. D13 selects Azure-allocated Standard static IPv4 and excludes BYOIP and feature registration. D14 removes Firewall, its hub, DNS proxy and appliance UDRs. Two directly peered VNets use Azure DNS/private-zone links, operations NAT/Bastion, and retained private service access. D15 constrains the separately approved temporary exemption.

Live investigation found an inherited public-IP append policy adding `FirstPartyUsage=/Unprivileged`. Its rule, assignment and initiative contained no RG-tag opt-out. Exact identifiers stay in ignored local evidence. The helper still rejects conflicting payloads. The D15 waiver was created only after explicit user authorization; no invented tag or feature registration was used.

Official compilation, ARM validation and exact-owned previews preceded deployments. Effective public-IP payloads, private endpoint contracts, identity-dependent IDs and source-derived preview repairs were verified without relaxing the ownership guard. The complete infrastructure and subsequent private runtime succeeded.

The current operator-managed deletion scope still includes all lab-owned network, workload and runner resources. Mandatory Azure-managed retention is disclosed separately.

## Historical qualification gaps

The earlier implementation left disconnected 24-hour suspension, delayed dispatch, PostgreSQL automatic-restart reconciliation and its crash-safe lifecycle contracts unqualified. D18 removes that automatic-lifecycle scope from the current refactor. Native App Service instance/zone faults, combined effects, cancellation and three-zone runtime evidence require fresh qualification under the [current readiness assessment](docs/development-readiness.md).

## Validation gap

HA-AZ-001 is blocked until a supported injection method and evidence of correlated real-zone loss are established. Component tests provide bounded evidence and cannot close this gap alone.

## Next steps

Refactor the source to the current App Service specification before fresh provisioning. Verify three-zone scale-unit capability, actual app placement, private SCM publication, both private network paths and native modern Actions. Preserve the historical cycle's bounded evidence without treating it as App Service qualification. Keep `HA-AZ-001` blocked until qualifying real-zone evidence is obtained.

The [research document](docs/research.md) records the platform capabilities and constraints supporting the design.
