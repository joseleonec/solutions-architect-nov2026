# Step 9: Data access architecture and frequent-client persistence

**Inputs:** Step 0 (FR-04/05/11, QAS-03/06/07, A-03 ~2 M DAU, A-06 90/10 read/write, A-09 retention, A-11 Core with limited capacity), Step 2 (12 months of transaction history online, LOPDP minimisation and deletion), Step 3 (~90 ms to the Core over Direct Connect, us-east-1 + us-east-2), Step 4 (database per service), Step 8 (MSK, outbox, Core Adapter with bulkheads and rate limit).

> **Statement requirement (§3.6):** *"there is a persistence mechanism for frequent clients… propose an alternative based on design patterns that relates the components that must interact to achieve it."* Section 3 answers it.

---

## 1. Principles

1. **The Core is the system of record** for balances, accounts and posted movements. Copies in the cloud are **read models**, never the authority for moving money.
2. **Database per service.** No service reads another service's database; data is shared through APIs or events.
3. **Read from the closest copy, write to the owner.** Reads (90% of calls) are served from cache or read models; money-moving writes always go to the Core through the Core Adapter.
4. **Keep only what's needed, for as long as it's needed** (LOPDP minimisation): short TTLs in caches, IDs instead of personal data in events.

---

## 2. Data stores per service (polyglot persistence)

| Service                | Store                                             | Why                                                                                                             |
| ---------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Transfer               | **Aurora PostgreSQL** (Global Database)     | ACID: order, idempotency key and outbox row in one transaction. Saga state.                                     |
| Beneficiary & Limits   | **Aurora PostgreSQL**                       | Relational, transactional, low volume.                                                                          |
| Onboarding             | **Aurora PostgreSQL**                       | Case state, consent, evidence references.                                                                       |
| Customer Profile       | **Aurora PostgreSQL** + Redis cache         | Cloud-owned data (preferences, last login, contact verification) + cached Core data.                            |
| Device                 | **DynamoDB** (global table)                 | Checked on **every** request (Step 6): key-value lookups at thousands per second, active in both regions. |
| Movements (read model) | **DynamoDB** (global table)                 | Billions of items, access always by account + date range.                                                       |
| Accounts (balances)    | **Redis** (cache only)                      | Balances belong to the Core; the service caches them with short TTLs.                                           |
| Risk Scoring           | **Redis** (features) + DynamoDB (decisions) | Millisecond feature lookups during the transfer.                                                                |
| Notification           | **DynamoDB**                                | Delivery log, provider status, retries.                                                                         |
| Interbank Connector    | **Aurora PostgreSQL**                       | ISO 20022 message log, status, reconciliation.                                                                  |
| Audit                  | Step 10                                           | Immutable store.                                                                                                |

Only **three data technologies** (Aurora PostgreSQL, DynamoDB, Redis-compatible cache), so the team keeps a small, well-understood set.

### ADR-012: Data store technologies

**Decision:** Aurora PostgreSQL for transactional services, DynamoDB for high-volume key-value and read models, ElastiCache (Valkey / Redis OSS) for caching.

| Criterion                                        | Aurora PostgreSQL                                                                            | DynamoDB                                   | ElastiCache (Valkey / Redis)           |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------- | ------------------------------------------ | -------------------------------------- |
| Transactions, constraints, joins                 | Strong                                                                                       | Limited (single-item / small transactions) | None                                   |
| Scale for billions of items, predictable latency | Needs partitioning and tuning                                                                | Strong, single-digit ms at any size        | In memory, sub-ms, size limited by RAM |
| Multi-region                                     | **Global Database**: replication typically < 1 s, managed failover (RPO 1 min, Step 3) | **Global tables**: active-active     | **Global Datastore**             |
| Operations                                       | Managed, some tuning                                                                         | Serverless                                 | Managed                                |

#### Justifications

1. **Right tool per access pattern.** Transfers need ACID (outbox + idempotency in one transaction), while movement history is a huge, append-only, key-range workload where DynamoDB keeps latency flat as data grows (QAS-07).
2. **Meets the DR targets with managed replication.** Aurora Global Database and DynamoDB global tables give an RPO well under 1 minute for critical data without custom replication code (QAS-02).
3. **Few technologies.** Three stores cover every service; adding a fourth needs an ADR.

**Rejected:** a single shared database (couples services, single point of failure); MongoDB / DocumentDB (no advantage over DynamoDB here, extra skills); OpenSearch for movement history (only needed if free-text search is required later).

---

## 3. ADR-013: Frequent-client persistence

**Status:** Proposed

**Context.** ~2 M customers use the app daily (A-03), most check their balance and recent movements, and every call to the Core costs ~90 ms of network plus Core capacity (A-11). The 2025 outages showed that when the Core or channel is slow, customers can't see anything. QAS-06 asks for a dashboard p95 < 500 ms for frequent clients.

**Frequent client:** a customer with **≥ 4 logins in the last 30 days** (configurable). Computed daily from login events; roughly the daily-active population.

### Options considered

| Option                                                                                                      | Verdict                                                                                                                                  |
| ----------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| A. Call the Core on every request                                                                           | Rejected: ~90 ms + Core load on every screen, no protection when the Core is slow (QAS-03).                                              |
| B. Cache-aside only (Redis, TTL)                                                                            | Better, but the first request of the day still hits the Core, and a payday morning with cold caches sends a burst of misses to the Core. |
| C. Copy everything from the Core into the cloud (full replica)                                              | Too heavy, duplicates the system of record, larger personal-data footprint.                                                              |
| **D. CQRS read model + cache-aside + event-driven invalidation + refresh-ahead for frequent clients** | **Chosen.**                                                                                                                        |
| E. Cache only on the device                                                                                 | Useful for instant display (Step 5), but can't be the source for web or for a new device, and is limited by device security.             |

### Decision: patterns and how they work together

| Pattern                                     | Applied to                            | What it does                                                                                                                                                                                                                                                        |
| ------------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **CQRS** (read model)                 | Movements                             | Writes go to the Core; a separate **read model in DynamoDB** is fed by **CDC** events from the Core and by our own transfer events. History queries never touch the Core.                                                                               |
| **Cache-aside**                       | Balances, profile, dashboard snapshot | The service reads Redis first; on a miss it reads the source, then stores the result with a TTL.                                                                                                                                                                    |
| **Event-driven invalidation**         | Balances, dashboard                   | `TransferCompleted`, `IncomingPaymentCredited` and Core CDC events **evict or update** the affected keys within seconds.                                                                                                                                  |
| **Refresh-ahead (pre-warming)**       | Frequent clients                      | On a `LoginSucceeded` event of a frequent client, a **Dashboard Precompute** worker (a component of the Accounts service, not a new service) builds the dashboard snapshot while the customer is still finishing login, so the first screen is a cache hit. |
| **Materialized view**                 | Dashboard                             | One pre-composed object per customer (accounts with balances, last 10 movements, alerts) instead of 3 calls per screen.                                                                                                                                             |
| **Request coalescing** + jittered TTL | All caches                            | Only one request rebuilds a missing key; TTLs are spread to avoid mass expiry.                                                                                                                                                                                      |
| **Stale-while-revalidate fallback**   | Balances, movements                   | If the Core is down, serve the last known value **marked "as of hh:mm"** (QAS-03).                                                                                                                                                                            |

### Justifications

1. **Meets QAS-06 and protects the Core.** A frequent client's dashboard is served from a pre-built snapshot in memory (few ms), so p95 is dominated by the ~90 ms network trip, well under 500 ms. Most reads never reach the Core, which keeps it within its capacity even on payday (QAS-09).
2. **Each pattern covers a weakness of the others.** Cache-aside alone has cold starts → refresh-ahead fixes it for frequent clients. TTLs alone serve stale balances → event-driven invalidation fixes it. A cache can't hold 12 months of history → the CQRS read model does.
3. **Fault tolerance as a side effect.** Because the read path doesn't depend on the Core, customers can still see balances (marked with time) and movements during a Core incident, the exact failure that caused the 2025 sanctions.

### Components that interact (for the component diagram)

```text
                    LoginSucceeded (Kafka)
Identity Provider ───────────────────────────► Dashboard Precompute (worker)
                                                    │ builds snapshot
                                                    ▼
Mobile/Web BFF ──► Accounts svc ──► Redis: balance:{acct} (TTL 60 s) ──miss──► Core Adapter ──► Core
      │       └──► Profile svc ───► Redis: profile:{cust} (TTL 24 h) ──miss──► Aurora + Core / Customer Info
      │       └──► Movements svc ─► DynamoDB read model (12-13 months) ──older──► Core (on demand)
      └──────────► Redis: dashboard:{cust} (TTL 5 min, materialized view)
                                                    ▲
Core DB ──CDC (Debezium)──► MSK ──► Movements projector ──► DynamoDB read model
                              └──► Cache invalidator ──► evict balance / dashboard keys
Transfer svc ──outbox──► MSK ─┘
```

---

## 4. What is safe to cache

| Data                                                | Cache?                                                              | TTL              | Invalidation                 | Rule                                                                                                                                        |
| --------------------------------------------------- | ------------------------------------------------------------------- | ---------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| **Balance** (shown on screen)                 | Yes                                                                 | 60 s             | On every movement event      | Shown with "as of" time if from fallback. **Never used to authorise a debit**: the Core checks the available balance at posting time. |
| Posted movements                                    | Yes (read model)                                                    | Long (immutable) | New movements appended       | Pending vs posted status clearly shown.                                                                                                     |
| Basic profile (name, products)                      | Yes                                                                 | 24 h             | `CustomerUpdated`          |                                                                                                                                             |
| Detailed data from the complementary system (FR-05) | Only when requested                                                 | 15 min           | TTL                          | Fetched **on demand**, not pre-loaded (minimisation).                                                                                 |
| Beneficiaries                                       | Yes                                                                 | 1 h              | `BeneficiaryAdded/Removed` | Writes go to the Beneficiary service first.                                                                                                 |
| Limits, device trust                                | Short                                                               | 1–5 min         | Event                        | Security-relevant: short TTL, revocations are pushed immediately (Step 6 revocation list).                                                  |
| Reference data (bank list, BIC, FX)                 | Yes, also at gateway                                                | 1 h–24 h        | Publish                      | Not personal.                                                                                                                               |
| OTPs, passwords, tokens                             | **No** (tokens only in the Web BFF's encrypted session store) | —               | —                           |                                                                                                                                             |

---

## 5. Integrating with the Core: getting changes out

### ADR-014: Change Data Capture from the Core

| Option                                                                       | Freshness | Load on Core                          | Needs from the Core team                         | Verdict                                                  |
| ---------------------------------------------------------------------------- | --------- | ------------------------------------- | ------------------------------------------------ | -------------------------------------------------------- |
| **Log-based CDC (Debezium)** on a Core **read replica**          | Seconds   | Very low (reads the transaction log)  | Read access to the replica's log; no code change | **Chosen**                                         |
| Vendor replication tool (e.g. Oracle GoldenGate, if the Core runs on Oracle) | Seconds   | Low                                   | Licence                                          | Alternative if Debezium isn't supported by the Core's DB |
| Polling Core APIs per account                                                | Minutes   | **High** (millions of accounts) | None                                             | Fallback for small tables only                           |
| End-of-day batch files                                                       | Hours     | Low                                   | File export                                      | Only for reconciliation                                  |

#### Justifications

1. **Fresh data without touching the Core's code** (A-11): log-based CDC reads the database's change log, so movements from **any** channel (branch, ATM, other systems) reach the read model in seconds.
2. **Very low load on the Core.** No query per account; reading from a replica keeps even log reading off the primary.
3. **Fits the event platform.** Debezium runs on Kafka Connect and writes to MSK (ADR-010), so the same consumers (projector, invalidator, AML) handle Core and cloud events alike.

The **Movements projector** is the anti-corruption layer for CDC: it maps Core tables to our `MovementPosted` event, so a Core change only affects this one component. A **nightly reconciliation** job compares read-model totals with the Core and repairs differences.

**If CDC isn't allowed** by the Core owner: the read model is fed by our own transfer events plus incremental polling of the Core's "movements since cursor" API for accounts of active customers only, with a lower freshness target.

---

## 6. Movements read model design (DynamoDB)

| Item            | Value                                                                                                           |
| --------------- | --------------------------------------------------------------------------------------------------------------- |
| Partition key   | `accountId`                                                                                                   |
| Sort key        | `postedAt#movementId` (date range queries, newest first)                                                      |
| Attributes      | amount, currency, type, counterparty (masked), channel, status, balance after                                   |
| Secondary index | `customerId` + date (all accounts of a customer)                                                              |
| Online window   | **13 months** (12 months required online by Step 2, plus one month margin), then removed by **TTL** |
| Older history   | On-demand query to the Core or archive (S3) through an async "statement request"                                |
| Idempotency     | Upsert by `movementId` (CDC and transfer events can both report the same movement)                            |

**Sizing (order of magnitude):** if all channels post ~300 M movements a month, 13 months is ~4 billion items at ~0.5 KB, roughly **2 TB** per region. DynamoDB handles this with constant latency. A 3-month history query (QAS-07) is a single paginated range query.

**Cache sizing:** ~2 M dashboard snapshots × ~4 KB + ~5.5 M profiles × ~2 KB ≈ **20–30 GB** in memory, e.g. a 3-shard cluster with 1–2 replicas per shard across AZs.

---

## 7. Payday and cold-cache protection

- **Scheduled pre-warming** before payday morning: snapshots for frequent clients are built gradually overnight, at a rate the Core Adapter's rate limit allows.
- **Request coalescing** in the Accounts service: 1,000 simultaneous misses for the same account become 1 Core call.
- **Priority:** balance refreshes for customers about to transfer take priority over background refreshes.
- **DR:** caches are replicated with ElastiCache Global Datastore for the critical keys, so a regional failover (Step 13) doesn't start with an empty cache and flood the Core.

---

## 8. Data protection

| Control                | Implementation                                                                                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Encryption at rest     | All stores encrypted with **customer-managed KMS keys**, one key per data domain (customer, transactions, onboarding, audit). Deleting a key **crypto-shreds** its data. |
| Encryption in transit  | TLS 1.2+ everywhere: clients, services (mesh mTLS), databases, Redis, Kafka, Direct Connect (plus MACsec or IPsec on the link).                                                      |
| Field-level encryption | ID number (cédula), phone, email and address encrypted in the application (envelope encryption) before storing, so DB administrators can't read them.                               |
| Tokenisation           | Events and logs carry a **token** or customer ID instead of the cédula or account number.                                                                                     |
| Masking                | Account numbers shown as `****1234` in UI, logs and notifications.                                                                                                                 |
| Least privilege        | Each service has its own IAM role and DB credentials (rotated by Secrets Manager); no shared users.                                                                                  |
| Retention and deletion | TTLs in caches and read models; deletion requests (LOPDP rights) handled by the owning service, except records under legal retention (KYC, AML, audit).                              |
| Non-production         | Synthetic or masked data only; production data never copied to dev or test (Step 2 environment isolation).                                                                           |

---

## 9. Data architecture view (for the PDF)

```text
            ┌──────────────────────── AWS us-east-1 (replicated to us-east-2) ────────────────────────┐
 Apps ─► BFFs ─► services
            │   Transactional (Aurora PostgreSQL Global DB): Transfer, Beneficiary & Limits,
            │        Onboarding, Customer Profile, Interbank Connector  ──outbox──┐
            │   Key-value / read models (DynamoDB global tables): Movements, Device,  │
            │        Notification, Risk decisions                                  ▼
            │   Cache (ElastiCache Valkey/Redis + Global Datastore):         MSK (Kafka) ─► Audit (Step 10)
            │        balances, profiles, dashboard snapshots, risk features     ▲   └──► AML, Notification
            └─────────────────────────────────────────────────────────────────── │ ───────────────────┘
                                                                     Debezium (Kafka Connect)
 On-premises:  Core Banking DB (read replica) ───────────────────────────────────┘
               Core APIs ◄── Core Adapter (postings, balance checks)
               Complementary customer system ◄── Customer Info Adapter (on demand)
```

---

## 10. Sources

- [microservices.io: CQRS, Database per Service, Transactional Outbox](https://microservices.io/patterns/data/cqrs.html)
- [Microsoft Azure Architecture Center: Cache-Aside pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/cache-aside) and [Materialized View pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/materialized-view)
- [AWS: Database caching strategies using Redis (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/database-caching-strategies-using-redis/welcome.html)
- [Debezium documentation](https://debezium.io/documentation/reference/stable/index.html)
- [Amazon Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html)
- [Amazon DynamoDB global tables](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html)
- [Amazon ElastiCache for Valkey and Global Datastore](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Redis-Global-Datastore.html)
- [AWS Encryption SDK (envelope encryption)](https://docs.aws.amazon.com/encryption-sdk/latest/developer-guide/introduction.html)

---

## Step 9 checklist

- [X] Store chosen per service (ADR-012: Aurora PostgreSQL, DynamoDB, ElastiCache)
- [X] Frequent-client persistence pattern chosen and justified (ADR-013: CQRS + cache-aside + event invalidation + refresh-ahead)
- [X] Components that interact for frequent-client persistence identified (for the component diagram)
- [X] What is safe to cache, with TTLs and invalidation
- [X] Core integration via CDC (ADR-014: Debezium on a read replica), with fallback and reconciliation
- [X] Movements read model and cache sized
- [X] Data protection controls
- [ ] Draw the component view of the Accounts / Movements / Dashboard Precompute path in Structurizr (Step 17)
- [ ] **Your review:** check DynamoDB and ElastiCache costs with the AWS Pricing Calculator in Step 15

---

## Update (8 Nov 2026): event-driven frequent-client classifier

The classifier is now **event-driven** instead of a daily batch: it consumes login and access events, keeps a **sliding-window activity score** per customer in Redis, applies a **configurable rule behind a feature flag** (default ≥ 4 logins in 30 days) and publishes `FrequentClientAdded` / `FrequentClientRemoved`. The Dashboard Precompute Worker pre-builds the snapshot on `FrequentClientAdded` and on each frequent client's login. Lookup order stays: **cache → read model → Core**.
