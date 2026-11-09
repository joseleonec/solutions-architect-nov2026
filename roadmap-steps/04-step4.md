# Step 4: Domain decomposition (microservices)

**Inputs:** the functional requirements from Step 0 (FR-01..15) and the regulatory requirements from Step 2 (device binding, risk scoring, login notification, contact-change controls, channel blocking).

**Method:** Domain-Driven Design (DDD). First find the **bounded contexts** (areas of the business with their own language and rules), then decide **which contexts become services**, then map how they talk to each other and to external systems (**context map**).

---

## 1. ADR-004: Architectural style

**Status:** Proposed

### Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| **Modular monolith** | Simple to deploy and debug. Local transactions. Lowest operational cost. | One deployment unit: a failure or a heavy load in one module affects all of them. Scaling is all-or-nothing. Harder for many teams to work in parallel. |
| **Microservices by bounded context** | Independent scaling, deployment and failure isolation. Clear data ownership. Teams can work in parallel. | Distributed transactions (needs Sagas), more infrastructure, harder observability. |
| Fine-grained microservices (one per entity or operation) | Maximum independence. | Very chatty, distributed monolith risk, high cost. Not justified at this size. |

### Decision

**Microservices aligned to bounded contexts**, kept **coarse-grained** (14 domain services, one or two per bounded context), with a shared platform for the cross-cutting concerns (gateway, identity, observability, messaging).

### Justifications

1. **Independent scaling for an uneven load.** ~90% of calls are reads (A-06), and payday multiplies transfers by 3 (QAS-09). Movements and accounts queries must scale separately from onboarding or beneficiaries. In a monolith you pay to scale everything. (Scale cube, Y-axis: functional decomposition.)
2. **Fault isolation (bulkheads).** The 2025 outages showed a channel failure becomes a business and regulatory event. With separate services, a failure in, say, notifications or onboarding can't take down balances and transfers. (Release It!, bulkhead pattern.)
3. **Regulatory and data isolation.** Biometric data (sensitive under the LOPDP), audit records (immutable, 10-year retention) and transaction data have different security and retention rules. Separate services with their own stores make those boundaries enforceable and auditable. (DDD bounded contexts: one model and one data owner per context.)
4. **Decoupling and reuse required by the statement.** Notifications, audit, risk scoring and the Core adapter are reusable by future channels and products (QAS-15, DEUNA in A-15).

### Consequences

- Cross-service consistency uses **Sagas** and the **Transactional Outbox** (Step 8), not distributed transactions.
- Requires a mature platform: container orchestration, CI/CD, distributed tracing (Steps 13–15).
- **Guardrail against over-splitting:** a new service is created only if it has its own data, its own scaling profile, or its own compliance boundary. Otherwise it's a module inside an existing service.

---

## 2. Bounded contexts

| # | Bounded context | Core question it answers | Type |
| --- | --- | --- | --- |
| 1 | **Identity & Devices** | Who is this user, and is this device trusted? | Supporting (the IdP itself is external) |
| 2 | **Onboarding** | Can this person become a customer? | Core |
| 3 | **Customer** | What do we know about this customer? | Supporting |
| 4 | **Accounts & Movements** | What does the customer have, and what happened in their accounts? | Core |
| 5 | **Transfers & Payments** | Move money between accounts and banks safely. | Core |
| 6 | **Beneficiaries & Limits** | Who can the customer send money to, and how much? | Supporting (regulatory) |
| 7 | **Risk & Fraud** | Should this operation be allowed? | Core (regulatory) |
| 8 | **Notifications** | Tell the customer what happened, on 2+ channels. | Generic |
| 9 | **Audit** | Prove what every actor did, immutably. | Generic (regulatory) |
| 10 | **Core Integration** | Translate between our model and the Core / complementary systems. | Anti-corruption layer |

**Core** = where the bank competes (invest the most effort). **Supporting** = needed but specific to us. **Generic** = common problems, candidates to buy or reuse.

---

## 3. Service catalogue

Data stores are named by role here. The technology is chosen in Step 9.

**Tier** (from A-07): **T1** = critical journeys (99.99%, RTO 15 min / RPO 1 min). **T2** = important (99.95%). **T3** = back-office / compliance queries.

### 3.1 Experience layer

| Service | Responsibility | Tier |
| --- | --- | --- |
| **Web BFF** | Backend for the SPA: aggregates calls for web screens, holds tokens server-side (token handler pattern, Step 6), applies the session idle timeout. | T1 |
| **Mobile BFF** | Backend for the mobile app: screen-shaped responses, device context, app version checks. | T1 |
| **API Gateway** (platform) | Single entry point: token validation, rate limiting, throttling, routing by transaction type (FR-12). | T1 |

### 3.2 Domain services

| Service | Context | Responsibilities | Owns data | Exposes (sync) | Publishes (events) | Consumes | Tier |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Device Service** | 1 | Device registration and **binding** (mobile only from authorized devices), device trust status, biometric/FIDO key registration, device blocking | Devices, public keys, trust status | Register device, verify device, list/revoke devices | `DeviceBound`, `DeviceRevoked` | `OnboardingCompleted` | T1 |
| **Onboarding Service** | 2 | Orchestrates the onboarding **Saga**: document capture, liveness and face match (vendor), civil registry check, AML screening, consent, account opening in the Core, user creation in the IdP | Onboarding cases, consent records, vendor references (not raw biometrics) | Start / continue onboarding, case status | `OnboardingStarted`, `OnboardingCompleted`, `OnboardingRejected` | Vendor callbacks | T2 |
| **Customer Profile Service** | 3 | **Base service "basic data"**: merges basic data (Core) with detailed data (complementary system) when needed; contact data changes (strong auth + notify old and new contacts); preferences; last login | Profile cache, preferences, contact-change history | Get profile (basic / detailed), update contact data, preferences | `ContactDataChanged`, `PreferencesChanged` | `CustomerLoggedIn` | T1 (read) / T2 (write) |
| **Accounts Service** | 4 | Account list and balances, including a short-lived cache for frequent clients | Balance cache (Core is the source of truth) | List accounts, get balance | — | `TransferCompleted` (invalidate cache) | T1 |
| **Movements Service** | 4 | **Base service "movements"**: history and search, served from a **read model** (CQRS) fed by the Core | Movements read model | Query movements (paged, filters), movement detail | — | Core change events (CDC), `TransferCompleted` | T1 |
| **Transfer Service** | 5 | **Base service "transfers"**: own-account, third-party internal, interbank, and payments to own cards and loans (A-10). Strategy per transfer type. **Idempotency**, **Saga** orchestration, status tracking (FR-13) | Transfer orders, status history, idempotency keys | Create transfer, get status, list pending | `TransferInitiated`, `TransferCompleted`, `TransferFailed`, `TransferRejected` | Interbank status updates | T1 |
| **Interbank Connector** | 5 | Adapter for the BCE: **instant payments** (≤ 1 basic salary) and **SPI** (deferred). Message mapping, settlement status | Outbound/inbound message log | Send interbank payment | `InterbankSettled`, `InterbankReturned` | `TransferInitiated` (interbank type) | T1 |
| **Beneficiary & Limits Service** | 6 | Favourite / registered accounts (regulatory), customer-defined **maximum amounts**, account validation before saving | Beneficiaries, limits | Add/remove beneficiary (step-up), get/set limits, check limit | `BeneficiaryAdded`, `LimitChanged` | — | T2 (T1 for the limit check) |
| **Risk Scoring Service** | 7 | **Real-time** allow / reject / step-up decision for logins and monetary transactions (regulatory). Rules + model | Customer risk profiles, rule sets, decisions | Score operation | `OperationRejected`, `StepUpRequired` | `CustomerLoggedIn`, `TransferInitiated`, `DeviceBound` | T1 |
| **AML Monitoring** | 7 | **Asynchronous** pattern detection and suspicious-activity cases for the UAFE | Cases, alerts | Case queries (back office) | `SuspiciousActivityFlagged` | All transfer and onboarding events | T3 |
| **Notification Service** | 8 | Sends every notification on **2 channels simultaneously** (SMS/push + email), templates, **provider failover**, retries, delivery tracking, masking of account numbers | Templates, delivery log, provider health | (Internal only) send, delivery status | `NotificationDelivered`, `NotificationFailed` | `TransferCompleted`, `TransferFailed`, `CustomerLoggedIn`, `ContactDataChanged`, `BeneficiaryAdded`, `DeviceBound`, `OperationRejected`… | T1 (async, ≤ 60 s) |
| **Audit Service** | 9 | Records **every customer action** and staff access to customer data, into **immutable** storage. Compliance query API | Audit log (WORM), hot index | Query audit trail (compliance only) | — | **All** domain events + gateway access logs | T2 (write path never blocks T1) |
| **Core Adapter** | 10 | **Anti-corruption layer** for the Core: translates protocols and models, **circuit breaker**, rate limiting to protect the Core, posting of internal transfers | None (stateless), except an outbox | Get customer, accounts, balances, movements; post transaction | Core change events (via CDC) | — | T1 |
| **Customer Info Adapter** | 10 | Anti-corruption layer for the complementary customer system | None | Get detailed customer data | — | — | T2 |

### 3.3 Platform services (shared, not domain-specific)

API Gateway, Identity Provider (external, existing), message broker / event bus, secrets and key management, observability stack. These are chosen in Steps 6, 8, 12 and 14.

---

## 4. Context map

How the contexts relate to each other and to systems outside the boundary:

| Upstream (provides) | Downstream (consumes) | DDD relationship | Why |
| --- | --- | --- | --- |
| Core Banking | Core Adapter | **Anti-corruption layer** | The Core's model and protocols mustn't leak into our domain. We can't change the Core (A-11). |
| Complementary Customer System | Customer Info Adapter | **Anti-corruption layer** | Same reason. |
| Identity Provider (OAuth 2.0) | All services | **Conformist** (standard OIDC tokens) | It's an existing product; we conform to its tokens and claims. |
| BCE (SPI and instant payments) | Interbank Connector | **Published language** (BCE messaging standard) + ACL | A regulated standard we must follow exactly. |
| Biometric/KYC vendor | Onboarding Service | **Anti-corruption layer** | Lets us swap vendors without touching the onboarding flow. |
| Notification providers A and B | Notification Service | **Anti-corruption layer** | Lets us fail over and change providers freely. |
| Transfers & Payments | Notifications, Audit, AML, Accounts, Movements | **Published events** (open host service) | Downstream contexts react to events. Transfers doesn't know who listens. |
| Beneficiaries & Limits, Risk | Transfers | **Customer–supplier** (sync API) | Transfers needs an answer before it can proceed. |

---

## 5. Communication style (first cut; detailed in Step 8)

| Interaction | Style | Why |
| --- | --- | --- |
| Client → Edge → Gateway → BFF → services | **Synchronous** (HTTPS) | The user is waiting for an answer. |
| Transfer → Limits, Risk, Core Adapter | **Synchronous**, with timeouts and circuit breakers | A decision is needed before the money moves. |
| Transfer → Interbank Connector | **Asynchronous** (command via queue) + status updates | Settlement may take time (SPI deferred). FR-13 status tracking. |
| Any service → Notifications, Audit, AML | **Asynchronous events** | They must never slow down or break the critical path. Audit must not lose events (outbox). |
| Core → Movements read model | **Asynchronous** (CDC or batch) | Avoids a ~90 ms round trip to the Core on every history query (Step 3). |

---

## 6. Example flow: transfer to a registered beneficiary

1. Mobile app → **API Gateway** (token and DPoP validated) → **Mobile BFF** (device binding checked).
2. **Transfer Service** stores the order with its **idempotency key** (status `RECEIVED`).
3. **Beneficiary & Limits**: is the beneficiary registered and the amount within limits?
4. **Risk Scoring**: allow / reject / step-up. A new beneficiary always requires step-up with 2 of 3 factors (Step 2).
5. Internal: **Core Adapter** posts the debit and credit. Interbank: a command goes to the **Interbank Connector** (instant or SPI).
6. **Transfer Service** saves the new status and publishes `TransferCompleted` (or `TransferFailed`) through the **outbox**.
7. Consumers react independently: **Notification** (SMS/push + email), **Audit** (immutable record), **AML** (monitoring), **Accounts** (invalidate the balance cache), **Movements** (update the read model).

If any step fails after the debit, the Saga runs **compensating actions** (for example, reversing the debit when an interbank payment is returned).

---

## 7. Traceability: requirements → services

| Requirement | Service(s) |
| --- | --- |
| FR-01 Onboarding with facial recognition | Onboarding, Device |
| FR-02 / FR-03 Login and biometric login | Identity Provider (external), Device, Risk Scoring |
| FR-04 Movement history | Movements, Core Adapter |
| FR-05 Basic and detailed customer data | Customer Profile, Core Adapter, Customer Info Adapter |
| FR-06 / FR-07 / FR-08 Transfers and payments | Transfer, Interbank Connector, Core Adapter |
| FR-09 Notifications (2 channels) | Notification |
| FR-10 Audit | Audit |
| FR-11 Frequent-client persistence | Accounts, Movements, Customer Profile (caches and read models; pattern chosen in Step 9) |
| FR-12 Integration layer | API Gateway, BFFs, adapters |
| FR-13 Transfer status tracking | Transfer, Interbank Connector |
| FR-14 Beneficiaries and limits | Beneficiary & Limits |
| FR-15 Step-up | Risk Scoring, Identity Provider |
| Step 2: device binding | Device |
| Step 2: real-time risk scoring | Risk Scoring |
| Step 2: login notification, contact changes | Notification, Customer Profile |
| Step 2: AML monitoring | AML Monitoring |

The 3 base services from the statement map to: **basic data → Customer Profile Service**, **movements → Movements Service**, **transfers → Transfer Service**. The others were added for performance (Accounts, Movements read model), regulation (Device, Beneficiary & Limits, Risk, AML) and decoupling (adapters, Notification, Audit).

---

## 8. Impact on the C4 model

- The **Audit Store** is modelled in [workspace.dsl](../architecture/workspace.dsl) as a separate internal system. With this decomposition, **Audit becomes a service inside BP Internet Banking**, with its own database container. Move it into the `bp` system when the containers are added.
- The container diagram (Step 17) will show: SPA, mobile app, the 2 BFFs, the API Gateway, the 14 services above, their data stores, and the message broker.

---

## Step 4 checklist

- [x] Architectural style decided (ADR-004)
- [x] Bounded contexts identified and classified
- [x] Service catalogue with responsibilities, data ownership, APIs, events and tier
- [x] Context map with DDD relationships to external systems
- [x] First cut of sync vs async communication
- [x] Every requirement traced to a service
- [ ] **Your review:** check that no service is too small to justify on its own (guardrail in ADR-004)
- [x] Add the containers to `workspace.dsl` (done in Step 17)
