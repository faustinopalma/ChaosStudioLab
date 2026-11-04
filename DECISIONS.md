# Decisions requiring confirmation

Record unresolved architectural choices here. Move confirmed outcomes to the [accepted decisions](DECISIONS-ACCEPTED.md).

The [development readiness assessment](docs/development-readiness.md) identifies technical contracts to define and platform paths to verify before dependent implementation. These remain within the approved architecture; a requirement-changing alternative needs a new explicit decision.

## Deployment inputs and technical checks

These are prerequisites rather than additional design choices:

- Supply the subscription ID. Resolve and verify its tenant and the authenticated Owner identity.
- Check Microsoft Entra permissions for creation and deletion of lab-owned application registrations and database identity bootstrap. Subscription Owner does not automatically grant directory permissions. If denied, obtain tenant authorization or have a tenant administrator bootstrap a new lab-owned registration with an agreed cleanup path.
- Verify regional capacity, APIs, private connectivity, preview behavior, replica fault execution, and supported stop/start operations.
- Apply D13's Azure-allocated public-IP contract. An observed inherited rule adds a conflicting `FirstPartyUsage=/Unprivileged` IP tag; exact governance identifiers stay in ignored local evidence. Feature registration is excluded. Governance changes, exemptions, or another deployment target require separate authorization.
- Establish qualifying affected-zone evidence before declaring HA-AZ-001 successful.
