# Decisions requiring confirmation

Record unresolved architectural choices here. Move confirmed outcomes to the [accepted decisions](DECISIONS-ACCEPTED.md).

The [current specification](docs/specification.md) and accepted D17-D19 require private Azure App Service across three observed zones, retained PostgreSQL HA, modern Chaos Workspaces and local deployment/manual deletion. No further decision is needed to restate those requirements. The App Service source refactor and its deployment remain pending.

## Deployment inputs and technical checks

These are prerequisites rather than additional design choices:

- Supply the subscription ID. Resolve and verify its tenant and the authenticated Owner identity.
- Check Microsoft Entra permissions for creation and deletion of lab-owned application registrations and database identity bootstrap. Subscription Owner does not automatically grant directory permissions. If denied, obtain tenant authorization or have a tenant administrator bootstrap a new lab-owned registration with an agreed cleanup path.
- Verify the actual App Service plan's `maximumNumberOfZones >= 3`, per-app placement across three observed `physicalZone` values, Windows/runtime/native Action compatibility, private SCM publication, outbound VNet Integration and PostgreSQL HA eligibility.
- Keep readiness blocked if capability or placement evidence is incomplete. A two-zone fallback, classic-mode fallback, public data-plane workaround or architectural change requires explicit operator approval.
- Apply D13's Azure-allocated public-IP contract. An observed inherited rule adds a conflicting `FirstPartyUsage=/Unprivileged` IP tag; exact governance identifiers stay in ignored local evidence. Feature registration is excluded. Governance changes, exemptions, or another deployment target require separate authorization.
- Establish qualifying affected-zone evidence before declaring HA-AZ-001 successful.
