# Step 19: Delivery plan and evolution (ADR-022)

The architecture in Steps 4–17 is the **target**. It is not built in one go before a customer sees it: it is reached in **four stages**, and each stage must prove something before the next one is paid for. Spend and risk grow with demonstrated demand.

## 1. Stages

| Stage | Technique | Scope | Indicative AWS cost (USD / month) |
| --- | --- | --- | --- |
| **1. Pretotype** (4–6 weeks) | Pretotyping: *Fake Door* (a "Transfers" button that measures intent and answers "coming soon, tell us if you want it"), *Pinocchio* (navigable app), *Mechanical Turk* (staff do onboarding review by hand) | App and SPA through the gateway to **mock endpoints generated from the OpenAPI contracts**; eKYC in the vendor's sandbox; feature flags and product analytics. No Core, no real customer data | 1,000–2,000 |
| **2. Read-only MVP** | Minimum viable product: real value, low risk | Profile, Accounts and Movements with **hexagonal architecture** (domain isolated from the Core Adapter); real Core and identity integration; login with biometrics; basic audit; one region, multi-AZ; pilot cohort | 15,000–25,000 |
| **3. Transactional** | Iterative expansion: own-account first, then interbank, by cohort and behind flags | Transfer Saga, idempotency, outbox, Beneficiary & Limits, Risk Scoring, Notifications (SMS + email), full Audit, Kafka, real onboarding, step-up; **warm standby DR before transfers open beyond the pilot** | 60,000–80,000 (+ SMS by volume) |
| **4. Enterprise scale** | Hardening driven by measured load and regulator requirements | Full multi-region (ARC Region switch), frequent-client refresh-ahead and CQRS at full scale, Shield Advanced, CloudHSM, chaos and DR drills, push to reduce SMS | 117,000–122,000 (+ SMS) |

## 2. Go / no-go gates

Each gate is a falsifiable hypothesis of the form *"at least X% of Y will do Z"* (the "XYZ" test from Alberto Savoia, *The Right It*). Thresholds are examples to agree with Product.

| Gate | Hypothesis | If it fails |
| --- | --- | --- |
| End of stage 1 | ≥ 70% of pilot users complete login and onboarding unaided; ≥ 25% tap "Transfers" within two weeks | Change the flow or the features; don't build the integration yet |
| End of stage 2 | ≥ 40% of the pilot checks balance or movements weekly; read p95 within target; no Sev-1 incident in four weeks | Fix experience or performance before adding features |
| End of stage 3 | ≥ 15% of active users complete a transfer in the first month; transfer success ≥ 99.5%; notification delivery ≥ 99% | Keep transfers behind the flag and fix reliability |
| End of stage 4 | SLOs met for two consecutive months; regional DR drill within RTO 15 min / RPO 1 min | Keep hardening before broad launch communication |

A fake-door test in a bank must be honest ("coming soon — tell us if you want it") and reviewed by Legal and Compliance.

## 3. Minimum resilience per stage (never below this line)

| Stage | Minimum |
| --- | --- |
| 1 | No real customer data at all |
| 2 | Multi-AZ in one region, backups with **tested restore**, all infrastructure as code so DR can be built on demand, audit trail on |
| 3 | **Warm standby DR and a first drill before transfers open beyond the pilot**, or a risk acceptance signed by Risk and Compliance; regulatory notifications (SMS + email) live from the first real transfer |
| 4 | Full targets of Step 13 (99.99%, RTO 15 min, RPO 1 min) |

## 4. Technical debt accepted deliberately

| Debt | Paid back when |
| --- | --- |
| Mock endpoints (stage 1) | Stage 2 replaces them; they are deleted |
| In-process event publisher instead of Kafka (stage 2) | Stage 3 plugs Kafka in behind the same port (hexagonal) |
| Single region with restore-based recovery (stage 2) | Warm standby before transfers open beyond the pilot |
| No refresh-ahead / frequent-client classifier until stage 4 | Measurements show Core latency or payday load hurting the dashboard SLO |
| No push channel | SMS cost or usage justifies it (and the SB accepts push as "mobile messaging") |
| Audit hot index replicated to two regions | Move to single-region + rebuild from archive when DynamoDB cost matters (Step 16b) |

## 5. Practices that make the staging work

- **Contracts first** (OpenAPI, Kafka schemas): a mock and a real service are interchangeable without rewriting clients.
- **Gateway routing by path or cohort**: traffic moves from mock to real, or old to new (strangler fig), per customer group.
- **Hexagonal architecture**: adapters (Core, events, vendors) can be swapped stage by stage.
- **Feature flags** and **progressive delivery** (Step 15) for cohorts and kill switches.

## ADR-022: Staged delivery with pretotyping and decision gates

**Decision:** deliver in four stages with hypothesis-based gates, a minimum resilience line per stage and an explicit technical-debt register.

**Alternatives:** single big-bang delivery; prototype-then-rewrite.

**Justifications:**

1. **Evidence before investment.** Each stage tests a demand or reliability hypothesis before the next, more expensive stage is funded, so money isn't spent on features customers don't use.
2. **Cost and risk grow with demand.** Cloud cost goes from ~USD 1–2 k a month (stage 1) to the full ~USD 117–122 k only when usage justifies it; regulatory risk is controlled by the minimum resilience line (no real data in stage 1, DR before transfers scale).
3. **No throw-away rewrite.** Contracts first, hexagonal adapters and gateway routing let each stage replace the previous one in place.
