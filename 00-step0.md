# Step 0: Frame the problem

Goal: before designing anything, know exactly **what** must be built, **how well** it must work, what is **fixed** by the statement, and what we **assume**. Every later decision (ADR) should trace back to an item here.

> Source: [assessment-statement.md](assessment-statement.md). Items marked *(added)* are not in the statement word for word. They are implied by it or needed to make the system work.

---

## 1. Functional requirements

| ID | Requirement | Source in the statement | Notes |
| --- | --- | --- | --- |
| FR-01 | **Onboarding** of new customers in the mobile app with **facial recognition** | §3.5 | Includes document capture, liveness and face match. The result feeds into creating the identity. |
| FR-02 | **Login** with username and password through the company's **OAuth 2.0** product (SPA and mobile) | §3.4 | We recommend the flow and don't implement the identity provider. |
| FR-03 | **Biometric login** (fingerprint / Face ID) after onboarding, and optionally other methods | §3.5 | Must specify at least one method in the architecture. |
| FR-04 | **Query of movement history** (report and query) | §3 | Data comes from the Core. |
| FR-05 | **Query of basic customer data**, plus **detailed data** from the complementary system when needed | §3.1, §3.7 | 2 data sources; aggregation needed. |
| FR-06 | **Transfers between own accounts** | §3 | Internal, through the Core. |
| FR-07 | **Interbank transfers** | §3, §3.7 | Calls external services, which depend on the transfer type. |
| FR-08 | **Payments** between own and interbank accounts | §3 | Scope is ambiguous, see A-10. |
| FR-09 | **Notify customers of every movement** through **at least 2** notification systems | §3.2 | Required by regulation. |
| FR-10 | **Audit log** of all customer actions | §3.6 | Stored in a dedicated audit database. |
| FR-11 | **Persistence for frequent clients** for a better and faster experience | §3.6 | Must be based on design patterns. |
| FR-12 | **Integration layer** with an **API Gateway** that routes to services by transaction type | §3.7 | 3 base services. More can be added. |
| FR-13 | *(added)* Transaction status tracking for asynchronous interbank transfers | Implied by §3.7 | The customer must see pending, completed or failed. |
| FR-14 | *(added)* Beneficiary (contacts) management for third-party and interbank transfers | Implied by FR-07 | Common banking feature. Reduces input errors. |
| FR-15 | *(added)* Step-up confirmation (OTP or biometric) for sensitive operations | Implied by security and regulation | Applies to transfers, new beneficiaries and limit changes. |

---

## 2. Constraints (fixed by the statement, not up for debate)

| ID | Constraint |
| --- | --- |
| C-01 | Two front-ends: an **SPA** and a **mobile app built with a multiplatform framework**. We must compare 2 options. |
| C-02 | Authentication uses the company's existing **OAuth 2.0 product**. We configure it and don't build it. |
| C-03 | Customer data comes from the **Core platform** and an **independent complementary system**. |
| C-04 | Access to customer data goes **through an API Gateway**. |
| C-05 | Base services: **basic data query, movements query, transfers**. |
| C-06 | **At least 2** notification systems, external or in-house. |
| C-07 | A dedicated **audit database**. |
| C-08 | Cloud is **optional**, but if used it must be **AWS or Azure**. Budget is available. |
| C-09 | Documented with the **C4 model** down to the component level. Infrastructure diagram in any notation. |
| C-10 | Deliverable: a **PDF** (in CoderPad and in a public GitHub repo) within **72 h**. |

---

## 3. Quality attributes (non-functional requirements)

| ID | Attribute | Required by |
| --- | --- | --- |
| NFR-01 | High availability (HA) | Statement §4 |
| NFR-02 | Fault tolerance | Statement §4 |
| NFR-03 | Disaster recovery (DR) | Statement §4 |
| NFR-04 | Security | Statement §4, regulation |
| NFR-05 | Monitoring / observability | Statement §4 |
| NFR-06 | Operational excellence | Statement §4 |
| NFR-07 | Auto-healing | Statement §4 |
| NFR-08 | Low latency | Statement §4 (cloud) |
| NFR-09 | Cost efficiency | Grading criterion |
| NFR-10 | Decoupling, reusability, cohesion (modifiability) | Statement §4 |
| NFR-11 | Regulatory compliance (personal data, banking rules) | Statement §4 |
| NFR-12 | Auditability and traceability | Statement §3.6 |
| NFR-13 | *(added)* Scalability for peak days (payday, end of month) | Implied by HA and latency |

### 3.1 Quality attribute scenarios

Format from *Software Architecture in Practice*: **source → stimulus → artifact → environment → response → measure**. The numbers come from the assumptions in section 4.

| ID | NFR | Scenario | Response measure |
| --- | --- | --- | --- |
| QAS-01 | HA | One availability zone fails during business hours. Traffic shifts to the healthy zones. | No customer-visible outage. Monthly availability ≥ **99.99%** for critical journeys (login, balance, transfers) and ≥ **99.95%** for the rest (see A-07). |
| QAS-02 | DR | The primary region becomes unavailable. Traffic fails over to the DR region. | Critical journeys: **RTO ≤ 15 min**, **RPO ≤ 1 min**. Non-critical: RTO ≤ 4 h, RPO ≤ 1 h (see A-08). |
| QAS-03 | Fault tolerance | The Core platform responds slowly or not at all. The circuit breaker opens, queries are served from cache or the read model, and transfers are queued or rejected cleanly. | The app shows data marked "as of hh:mm". No thread exhaustion. Recovers on its own when the Core returns. |
| QAS-04 | Fault tolerance | The primary notification provider fails. The system fails over to the secondary provider. | The notification is delivered within **≤ 60 s**, and none are lost. |
| QAS-05 | Fault tolerance | A customer retries a transfer because of a network timeout. The idempotency key prevents a duplicate. | **0 duplicate debits**. |
| QAS-06 | Performance | A frequent client opens the app and loads their dashboard (profile and recent movements). | p95 **< 500 ms**, served from cache. |
| QAS-07 | Performance | A customer queries 3 months of movement history. | p95 **< 1.5 s**. |
| QAS-08 | Performance | An own-account transfer is submitted. | Confirmation p95 **< 3 s**. An interbank transfer returns "accepted" in < 3 s, with the final status asynchronous. |
| QAS-09 | Scalability | On payday, traffic reaches **3× the normal peak** (about 500 TPS, see section 4.2). Auto-scaling adds capacity. | Latency targets still met. Error rate **< 0.1%**. |
| QAS-10 | Security | An attacker steals an access token. | Token lifetime **≤ 5–10 min**, tokens are sender-constrained, and transfers require step-up. The token can't be used to move money. |
| QAS-11 | Security | During onboarding, someone uses a photo, video or mask (presentation attack). | Liveness detection rejects it. The vendor is certified to **ISO/IEC 30107-3**. |
| QAS-12 | Auditability | An insider tries to change or delete audit records. | Storage is immutable (WORM) and the records are tamper-evident. The attempt is detected and alerted. |
| QAS-13 | Observability | Error rates spike on the transfer service. | Alert within **≤ 5 min**. The trace with its correlation ID shows the failing dependency. |
| QAS-14 | Auto-healing | A service instance crashes or hangs. | Health checks restart or replace it in **≤ 2 min** without human action. |
| QAS-15 | Modifiability | The business asks for a new channel (for example, a chatbot) or a new service (for example, loans). | Added without changing existing services. Reuses the gateway, identity, notifications and audit. |
| QAS-16 | Cost | Traffic at night is about 10% of the peak. | Compute scales down, so cost follows usage. |

---

## 4. Assumptions (explicit and to be justified in the PDF)

The statement only says "BP". We assume **BP = Banco Pichincha (Ecuador)** and size the system with its public figures. Say this explicitly in the PDF. If the evaluator meant a fictional entity, the numbers still describe a realistic large bank.

### 4.1 Public data on Banco Pichincha

> Most figures come from the bank's own statements reported by the press, not from audited reports. Cite them as "according to the bank". For official numbers, check the [2025 annual report](https://www.pichincha.com/sites/default/files/documents/2026-05/memoria_2025_bp_1.pdf) (the PDF is large, so open it in a browser).

| Fact | Value | Source |
| --- | --- | --- |
| Total clients | **6.5 M**, present in all cantons of Ecuador | [Primicias, Oct 2026](https://www.primicias.ec/economia/banco-pichincha-concentra-transacciones-canales-digitales-134017/), [Vistazo, Apr 2026](https://www.vistazo.com/patrocinado/2026-04-27-aniversario-banco-pichincha-institucion-clave-desarrollo-economico-ecuador-EI10905504) |
| Clients who operate digitally | **8 out of 10** (it was 17% in 2019) | [El Mercurio, Oct 2026](https://elmercurio.com.ec/nacional/2026/10/01/8-de-cada-10-clientes-de-la-banca-operan-en-digital-en-ecuador/) |
| Active users on digital channels | **> 5.5 M** | [Vistazo, Oct 2026](https://www.vistazo.com/negocios/sectores/2026-10-05-transformacion-digital-sistema-financiero-adultos-ecuador-AE11262471) |
| Banca Móvil app users | **> 5.2 M** | Bank infographic (2026) |
| Share of transactions done digitally | **79%** of all transactions, **83%** of monetary transactions | Vistazo / Primicias, Oct 2026 |
| Mobile transactions | **164 M in one month**, about **USD 15 B** moved | Primicias, Oct 2026 |
| Digital processing rate | **> 100 transactions per second** | Vistazo, Oct 2026 |
| Transfers as a share of mobile operations | **3 out of 4** | Primicias, Oct 2026 |
| Interbank transfer growth (2025) | **+11%** | Primicias, Oct 2026 |
| DEUNA (the group's separate digital wallet) | ~6 M users, 630 k merchants | Bank statements (2025) |
| Cloud modernization | Plan to modernize and migrate **380+ applications** to a new cloud platform. The provider is **not public**. | [McKinsey case study](https://www.mckinsey.com/capabilities/mckinsey-digital/how-we-help-clients/rewired-in-action/pichincha-building-a-new-digital-bank-and-ecosystem) |

**The key incident (it justifies the HA and DR targets):**

- **June–July 2025:** repeated failures of the mobile app and website. Customers couldn't see their balances or movements. The Superintendencia de Bancos assigned a technical team to monitor corrective actions 24/7 ([Vistazo, 25 Jul 2025](https://www.vistazo.com/actualidad/2025-07-25-superintendencia-bancos-supervisa-acciones-correctivas-entidad-fallas-aplicacion-movil-EG9833170)).
- **4 Aug 2025:** the intermittent digital failures, together with social-media disinformation, triggered a run on the bank. Customers withdrew **USD 160 M in one day**, against about USD 58 M on a normal day (+276%). The regulator opened an **administrative sanctioning process for repeated failures** ([Vistazo, 7 Aug 2025](https://www.vistazo.com/actualidad/2025-08-07-banco-pichincha-retiraron-160-millones-dolares-panico-ecuador-EG9901170), [El Comercio](https://www.elcomercio.com/actualidad/negocios/banco-pichincha-respuesta-rumores-fondos-clientes/)).
- **Takeaway for the PDF:** for this bank, a digital outage is not only a technical problem. It caused regulatory sanctions, reputational damage and a liquidity event. That's the business case for the availability, DR, auto-healing and monitoring investment.

### 4.2 Derived sizing

These are estimates from the public numbers. Show the calculation in the PDF so the evaluator can follow it.

| Metric | Calculation | Result |
| --- | --- | --- |
| Average transaction rate | 164 M ÷ (30 days × 86,400 s) | **~63 TPS** on average, which matches the "> 100 TPS" the bank reports at busy times |
| Normal peak (business hours) | Average × ~2.5 (traffic concentrated in daytime) | **~160 TPS** |
| Payday or end of month | Normal peak × 3 (the 2025 run showed 2.76× normal withdrawals) | **~500 TPS** |
| API requests (reads included) | ~10 API calls per monetary transaction (login, balance, movements, beneficiaries) | **~1,600 req/s** normal peak, **~5,000 req/s** payday |
| Daily active users | 164 M per month ÷ 5.5 M active users ≈ 30 transactions per user per month. Assume about 35% are active on any given day. | **~2 M DAU** |
| Concurrent sessions | 2 M DAU, ~12% in the peak hour, 4-minute sessions: 240 k × 4/60 | **~16 k** normal peak, **~50–80 k** on payday |

### 4.3 Assumptions table

| ID | Assumption | Proposed value | Why it matters |
| --- | --- | --- | --- |
| A-00 | Who BP is | **Banco Pichincha**, the largest private bank in Ecuador | Grounds every number in public data. |
| A-01 | Jurisdiction | **Ecuador**: Superintendencia de Bancos, LOPDP (the bank publishes a [personal data protection policy](https://www.pichincha.com/sites/default/files/documents/2026-07/politica-general-proteccion-datos-personales-banco-pichincha.pdf)) | Sets the regulation (Step 2) and the cloud region and latency (Step 3). |
| A-02 | Registered digital users | **~6.5 M** (all clients, assuming digital access for everyone over time) | Sizing for identity and storage. |
| A-03 | Active digital users / daily active users | **5.5 M** active, **~2 M DAU** | Sizing for the frequent-client cache. |
| A-04 | Peak concurrent sessions | **~16 k** normal, **up to 80 k** on payday | Gateway, BFF and session sizing. |
| A-05 | Peak throughput | **~160 TPS** normal, **500 TPS** design target for monetary transactions. **~5,000 req/s** design target at the API Gateway. Plan **2× headroom** for growth. | Auto-scaling, and protecting the Core with rate limiting and caching. |
| A-06 | Read/write ratio | **~90 / 10** of API calls. Transfers are 75% of the *monetary* operations, but each one comes with several reads. | Justifies caching and CQRS. |
| A-07 | Availability target | **99.99%** for critical journeys (login, balance, transfers), about 4.3 min of downtime a month. **99.95%** for the rest. | The 2025 outages led to sanctions and a run. Drives multi-AZ and active failover. |
| A-08 | RTO / RPO | Critical: **15 min / 1 min**. Non-critical: **4 h / 1 h**. | Drives the DR strategy (warm standby or active-active for the critical path) and its cost. |
| A-09 | Audit retention | **7 years** with WORM (to be confirmed against the regulation in Step 2) | Storage tiering and cost. |
| A-10 | Meaning of "payments" | Payments to third-party and interbank accounts and to the customer's own credit cards and loans. Utility and bill payments are a future extension. | Bounds the scope of the payments service. |
| A-11 | The Core and complementary system | On-premises, exposing APIs (REST/SOAP). We can't modify them. The Core has limited capacity. This fits the bank's ongoing, gradual cloud migration. | Hybrid connectivity, an anti-corruption layer, and protecting the Core. |
| A-12 | The OAuth 2.0 product | Supports OIDC, Authorization Code + PKCE, MFA, custom claims, and token introspection or JWKS. | Basis for the authentication recommendation. |
| A-13 | Interbank transfers | Go through the national interbank payment system. Some are near-real-time, others are processed in batches. | Asynchronous design and status tracking (FR-13). |
| A-14 | Users and channels | Retail customers, Spanish-speaking, nationwide. About **90% mobile and 10% web** (5.2 M app users out of 5.5 M active digital users). | Mobile-first priorities. The SPA is secondary but still required. |
| A-15 | Interaction with DEUNA | DEUNA is a separate product. It's **out of scope**, but the API layer should be reusable by it in the future. | Supports the reusability requirement (QAS-15). |

---

## 5. Out of scope

- Building the OAuth 2.0 / identity provider (C-02).
- Changes to the Core and the complementary system.
- Back-office or internal employee applications.
- Card issuing, loans origination and investments (they could plug in later, see QAS-15).
- The DEUNA wallet itself (A-15).

---

## 6. Open questions (answered in later steps)

| Question | Step |
| --- | --- |
| Which regulations apply, and do they restrict hosting data outside the country? | 2 |
| AWS or Azure, and which region for the lowest latency to users? | 3 |
| Which services to add beyond the base 3? | 4 |
| Which SPA framework and which mobile framework? | 5 |
| Which OAuth flow, how tokens are stored, and how step-up works? | 6 |
| Which KYC and liveness vendor, and how onboarding creates the identity? | 7 |
| Sync vs async communication, and how a transfer handles failure (Saga)? | 8 |
| Which pattern implements frequent-client persistence? | 9 |
| How audit records are captured and kept immutable? | 10 |
| Which 2 or more notification providers, and how failover works? | 11 |

---

## 7. Traceability to the grading criteria

| # | Grading criterion | Covered by |
| --- | --- | --- |
| 1 | Requirements met and justified | FR-01..15, ADRs |
| 2 | Quality of the C4 diagrams | Step 17 (all FRs and constraints must appear) |
| 3 | Separation of responsibilities and decoupling | NFR-10, QAS-15 |
| 4 | Architecture patterns | QAS-03, 05, 06, 12 (circuit breaker, idempotency, cache-aside, outbox, Saga) |
| 5 | Integration with external services | FR-05, 07, 09, A-11, A-13 |
| 6 | Front-end and mobile architecture | C-01, FR-01, 03, A-14 |
| 7 | Data access architecture | FR-04, 05, 11, A-06 |
| 8 | Cloud knowledge | C-08, NFR-01..03, 08 |
| 9 | Cost management | NFR-09, QAS-16, A-02..05 |
| 10 | Authentication architecture | FR-02, 03, 15, QAS-10, A-12 |
| 11 | Onboarding integration | FR-01, QAS-11 |
| 12 | Audit solution design | FR-10, NFR-12, QAS-12, A-09 |
| 13 | Banking regulation and security standards | NFR-04, NFR-11, A-01 |
| 14 | HA and fault tolerance | NFR-01, 02, 07, QAS-01..05, 14, A-07, A-08 |
| 15 | Monitoring | NFR-05, QAS-13 |

---

## Step 0 checklist

- [x] Functional requirements listed and traced to the statement
- [x] Constraints separated from decisions
- [x] Quality attributes turned into measurable scenarios
- [x] Assumptions grounded in public data on Banco Pichincha
- [x] Scope boundaries defined
- [x] Open questions mapped to later steps
- [x] Grading criteria traced to requirements
- [ ] **Your review:** validate the sizing estimates in 4.2 and confirm the figures against the 2025 annual report
