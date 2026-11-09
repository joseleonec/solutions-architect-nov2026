# Step 13: HA, fault tolerance, DR and auto-healing

**Inputs:** Step 0 (QAS-01 99.99% / 99.95%, QAS-02 RTO 15 min / RPO 1 min critical, 4 h / 1 h non-critical, QAS-03 Core slow, QAS-09 payday, QAS-14 auto-healing, A-07/A-08), Step 2 (continuity management with RTO/RPO per critical process, annual tests, remote recovery site that doesn't share the primary's risks, alternate providers, ISO 22301), Step 3 (ADR-003: us-east-1 primary, us-east-2 DR), Step 4 (tiers T1/T2/T3), Step 8 (EKS, MSK, Kong), Step 9 (Aurora Global Database, DynamoDB global tables, ElastiCache Global Datastore).

---

## 1. Targets per tier

| Tier                             | Services                                                                                                                                                                                          | Availability                        | RTO                                  | RPO                                                                                   |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------- |
| **T1** (critical journeys) | CloudFront/WAF, Kong, Web BFF, Mobile BFF, Device, Accounts, Movements, Transfer, Beneficiary & Limits, Risk Scoring, Core Adapter, Interbank Connector (incoming and outgoing), Customer Profile | **99.99%** (~4.3 min a month) | **15 min**                     | **1 min**                                                                       |
| **T2**                     | Onboarding, Notification, Audit, Customer Info Adapter                                                                                                                                            | 99.95%                              | 1 h (Notification: 15 min, see note) | Audit and Notification: **0** in practice (events kept in Kafka and the outbox) |
| **T3**                     | AML Monitoring, reporting, back-office batch                                                                                                                                                      | 99.9%                               | 4 h                                  | 1 h                                                                                   |

**Note:** Notification is T2 as a service, but regulatory notices for transfers can't be lost. The outbox and Kafka keep them; they're delivered when the service is back. It's deployed with T1 in the DR region so the delay stays short.

**External dependencies outside our control** (state them in the PDF): the Core and complementary system (on-premises, the bank's own DR), the identity product, the payment network / BCE, notification and eKYC vendors. The platform's availability can't exceed the Core's for operations that need the Core; section 6 shows how reads keep working without it.

---

## 2. High availability inside the primary region (multi-AZ)

| Component                               | HA design                                                                                                                                                                | AZ failure behaviour                                                                                     |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| CloudFront, WAF, Route 53               | Global services                                                                                                                                                          | Not affected                                                                                             |
| NLB                                     | Spread over 3 AZs                                                                                                                                                        | Stops sending to the failed AZ                                                                           |
| EKS (Kong, BFFs, services)              | Node pools in **3 AZs**; ≥ 3 replicas per T1 service with **topology spread constraints**; **PodDisruptionBudgets**; capacity for losing one AZ (N+1) | Pods in healthy AZs take the load; Karpenter adds nodes there                                            |
| Aurora PostgreSQL                       | Writer + 2 readers in different AZs                                                                                                                                      | Automatic failover to a reader, typically **< 30 s**; apps reconnect (RDS Proxy keeps connections) |
| DynamoDB                                | Regional, replicated across 3 AZs by AWS                                                                                                                                 | Transparent                                                                                              |
| ElastiCache                             | Cluster mode, replica per shard in another AZ, Multi-AZ auto-failover                                                                                                    | Replica promoted in seconds                                                                              |
| MSK                                     | 3 brokers per AZ group across 3 AZs, replication factor 3, `min.insync.replicas=2`                                                                                     | Writes continue with 2 of 3 replicas                                                                     |
| Direct Connect                          | 2 links at different locations and providers + VPN                                                                                                                       | Traffic moves to the surviving path (BGP)                                                                |
| **Zonal shift / autoshift** (ARC) | Enabled on the NLB and EKS                                                                                                                                               | Traffic moved away from an impaired AZ automatically, even for "grey" failures                           |

This covers **QAS-01**: an AZ failure causes no customer-visible outage.

---

## 3. ADR-018: Disaster recovery strategy

**Status:** Proposed (completes ADR-003)

### Strategies compared

| Strategy                                                              | RTO                    | RPO                          | Extra cost vs primary (rough) | Fits               |
| --------------------------------------------------------------------- | ---------------------- | ---------------------------- | ----------------------------- | ------------------ |
| Backup & restore                                                      | Hours                  | Hours (or minutes with PITR) | ~5–10%                       | T3                 |
| Pilot light (data replicated, compute off)                            | Tens of minutes to 1 h | Seconds                      | ~10–20%                      | T2                 |
| **Warm standby** (data replicated, scaled-down compute running) | **Minutes**      | **Seconds**            | ~30–50%                      | **T1**       |
| Multi-site active/active                                              | Near zero              | Near zero                    | ~80–100% + complexity        | Not chosen (below) |

**Decision.** **Warm standby in us-east-2 for T1 and Notification**, **pilot light for the rest of T2**, **backup & restore for T3**. Failover is **orchestrated** with **Amazon Application Recovery Controller (ARC) Region switch** plans and started by a **human decision** (incident commander), not automatically.

### Justifications

1. **Meets RTO 15 min / RPO 1 min at a reasonable cost.** Data is already in us-east-2 (Aurora Global Database typically < 1 s lag, DynamoDB global tables, MSK Replicator, ElastiCache Global Datastore), and compute is already running at reduced size, so failover is a promotion and a scale-up, not a rebuild. Active/active would roughly double the cost for a gain the statement doesn't require.
2. **Active/active doesn't fit the system of record.** Transfers need a **single writer** for idempotency keys, saga state and limits, and the Core is a single on-premises site. Running writes in two regions would add conflict handling on money movement for little benefit, since every transfer still ends in the same Core.
3. **Satisfies the SB rule on remote recovery sites.** us-east-2 is in a different geography and power grid from us-east-1, so it doesn't share the primary site's risks. It runs continuously and is tested regularly, which provides the evidence for the annual continuity test.
4. **Human-started, machine-executed failover avoids flapping.** A regional failover has side effects (possible loss of the last second of writes, a later failback). A person decides; ARC executes a tested, ordered plan in minutes.

### What runs in us-east-2 all the time

| Layer          | Standby state                                                                                                                  |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| EKS            | Same manifests (GitOps); T1 services at **~25–30% of primary capacity** (more before payday); Kong with the same config |
| Aurora         | **Global Database secondary** cluster (read-only), sized one class smaller; scaled up by the Region switch plan          |
| DynamoDB       | **Global tables** replica, active (Device, Movements read model, Notification log)                                       |
| ElastiCache    | **Global Datastore** secondary (critical keys: dashboards, balances) so failover doesn't start with a cold cache         |
| MSK            | Cluster with **MSK Replicator** copying all topics (including `audit.*`, `transfers.*`)                              |
| S3             | Cross-Region Replication (audit archive with Object Lock on the replica)                                                       |
| Network        | Same VPC layout; **Direct Connect gateway** reaches both regions; VPN backup                                             |
| Secrets / keys | Multi-Region KMS keys; Secrets Manager replication                                                                             |
| Edge           | CloudFront origin groups / Route 53 records ready to point to us-east-2                                                        |

### Failover runbook (Region switch plan)

| #               | Step                                                                                                                         | Target time                         |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| 1               | Detection: multi-signal alarms (synthetic journeys failing from outside AWS, regional health, error rates)                   | ≤ 5 min                            |
| 2               | Decision by incident commander; announce incident; freeze deployments                                                        | ≤ 3 min                            |
| 3               | **Stop accepting writes** in us-east-1 (if reachable): gateway returns "temporarily unavailable" for transfers         | 1 min                               |
| 4               | **Aurora Global Database failover** to us-east-2 (and Aurora scaling block to match the primary instance class)        | ~1–3 min                           |
| 5               | **EKS scaling block**: T1 deployments to full replica counts; Karpenter adds nodes                                     | ~2–4 min (parallel to 4)           |
| 6               | Switch Kafka producers/consumers to the us-east-2 MSK cluster (configuration flag, consumers resume from replicated offsets) | ~1 min                              |
| 7               | **Route traffic**: ARC routing control / Route 53 to us-east-2 origins                                                 | ~1 min                              |
| 8               | Smoke tests (synthetic login, balance, own transfer) and reopen writes                                                       | ~2 min                              |
| **Total** |                                                                                                                              | **≈ 12–15 min**, within RTO |

**After failover:**

- **In-flight transfers:** the Transfer service resumes sagas from Aurora state. Writes from the last < 1 s may be lost; idempotency keys (customers retry with the same key) and **reconciliation against the Core** (the system of record) close the gap. Interbank payments in `SENT` or `UNKNOWN` status are resolved with a status query (Step 8), never blindly resent.
- **Failback** is planned (not urgent): rebuild us-east-1 as the secondary, let replication catch up, then switch over in a maintenance window with **zero data loss** (Aurora switchover, not failover).

### Regional dependencies to keep in mind

- **Identity product:** must also be available in both regions (or at the bank's sites with the same RTO). If it isn't, existing sessions keep working until tokens expire, but new logins fail. This is a requirement on the bank's product.
- **Payment network connection:** the Interbank Connector's link to the network must exist from both regions (or from on-premises, reachable from both).
- **Providers' allowlists:** SMS, email, eKYC and the network must accept calls from us-east-2 egress IPs (registered in advance).

---

## 4. Auto-healing (QAS-14)

| Failure                                       | Mechanism                                                                                                                                     | Time to recover |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| Process crash                                 | Kubernetes restarts the container                                                                                                             | Seconds         |
| Hung process (no crash)                       | **Liveness probe** fails → restart                                                                                                     | < 1 min         |
| Instance not ready (warming, dependency down) | **Readiness probe** removes it from load balancing                                                                                      | Seconds         |
| Node failure                                  | Pods rescheduled; Karpenter replaces the node                                                                                                 | 1–2 min        |
| Load spike                                    | **HPA** (CPU / requests per second), **KEDA** (Kafka lag), Karpenter (nodes)                                                      | 1–2 min        |
| Bad deployment                                | **Progressive delivery** (Argo Rollouts canary 5% → 25% → 100%) with automatic **rollback** on error-rate or latency SLO breach | Minutes         |
| Configuration drift                           | **GitOps** (Argo CD) restores declared state                                                                                            | Minutes         |
| Database writer failure                       | Aurora automatic failover                                                                                                                     | < 30 s          |
| Impaired AZ                                   | ARC zonal autoshift                                                                                                                           | Minutes         |
| Dependency failing                            | Circuit breaker opens, fallback served, closes automatically when it recovers (Step 8)                                                        | Automatic       |

Probes are designed carefully: **liveness** checks only the process itself (never dependencies, to avoid restart storms when the Core is slow); **readiness** may check critical local dependencies.

---

## 5. Payday and peak capacity (QAS-09)

- **Scheduled scaling** before known peaks (payday, end of month, holidays): minimum replicas and node capacity raised the night before; DR standby also raised.
- **Pre-warming** caches (Step 9) at a rate the Core can absorb.
- **Load test** at 3× normal peak before each payday season and after major releases.
- **Load shedding** at the gateway protects transfers and login first (Step 8).

---

## 6. Graceful degradation (fault tolerance, QAS-03 / QAS-04)

| Dependency down               | What customers can still do                                                                                                                                                             | What they can't                                                                                                                   |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| **Core slow or down**   | Log in, see balances and movements **"as of hh:mm"** from cache / read model, manage beneficiaries, receive notifications                                                         | New postings: transfers rejected cleanly with a clear message (not queued silently: the customer must know the money didn't move) |
| Complementary customer system | Everything except the "detailed data" screen                                                                                                                                            | Detailed data                                                                                                                     |
| eKYC vendor or Registro Civil | Everything; onboarding cases wait as "pending"                                                                                                                                          | Finish onboarding instantly                                                                                                       |
| Payment network               | Own-account transfers, everything else                                                                                                                                                  | Interbank: rejected before debit if the network is known to be down (circuit open), or pending if already sent                    |
| One SMS provider              | Everything (failover)                                                                                                                                                                   | —                                                                                                                                |
| Notification service          | Everything; notices delayed, not lost                                                                                                                                                   | Immediate notices                                                                                                                 |
| Audit service                 | Everything; events wait in Kafka                                                                                                                                                        | —                                                                                                                                |
| Risk Scoring                  | **Fail closed** for transfers to new beneficiaries / high amounts; fail open only for low-risk, registered-beneficiary transfers within small limits (decision for the risk team) | Risky transfers                                                                                                                   |
| Redis cache                   | Everything, slower (reads go to read models and, rate-limited, to the Core)                                                                                                             | —                                                                                                                                |

---

## 7. Backups (defence against corruption and ransomware)

Replication copies mistakes too, so backups are separate:

| Data              | Backup                                                                                                                                                       | Retention                              |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------- |
| Aurora            | Continuous backup with **point-in-time recovery** (35 days) + daily snapshots                                                                          | 35 days PITR; monthly snapshots 1 year |
| DynamoDB          | **PITR** (35 days) + AWS Backup                                                                                                                        | Same                                   |
| EKS configuration | Git (GitOps) is the backup; cluster rebuilt from code                                                                                                        | —                                     |
| Kafka             | Topics replicated; events recoverable from the outbox tables and audit archive                                                                               | —                                     |
| All of the above  | **AWS Backup** with copies to a separate **backup account** and to us-east-2, **Vault Lock (compliance mode)** so backups can't be deleted | Per policy                             |

**Restore tests** quarterly, with measured restore times.

---

## 8. Testing: chaos engineering and DR drills

| Test                                                                         | Tool                                                                                   | Frequency                                                                   |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Kill pods, nodes; inject latency into the Core Adapter; fail an SMS provider | **AWS Fault Injection Service (FIS)**, in staging, then controlled in production | Monthly (staging), quarterly (production game days)                         |
| AZ failure simulation                                                        | FIS AZ power interruption scenario / zonal shift                                       | Quarterly                                                                   |
| **Full regional failover**                                             | ARC Region switch plan, real switch to us-east-2 and failback                          | **Twice a year** (the SB asks for at least an annual continuity test) |
| Load test at 3× peak                                                        | k6 / Gatling                                                                           | Before payday seasons and major releases                                    |
| Backup restore                                                               | AWS Backup restore testing                                                             | Quarterly                                                                   |

Results feed the continuity plan (ISO 22301) and the SB dossier.

---

## 9. Deployment view (for the PDF)

```text
                         Route 53 + ARC (routing controls, Region switch plan)
                                             │
                          CloudFront + WAF + Shield (global edge)
                         ┌───────────────────┴─────────────────────┐
             ┌─────────── us-east-1 (PRIMARY) ──────────┐  ┌──────── us-east-2 (WARM STANDBY) ────────┐
             │  AZ-a        AZ-b        AZ-c            │  │  AZ-a        AZ-b        AZ-c            │
             │  NLB ─────────────────────────────       │  │  NLB                                     │
             │  EKS: Kong, BFFs, T1/T2 services (N+1)   │  │  EKS: same, T1 at ~25–30% capacity        │
             │  Aurora writer │ reader │ reader ────────┼──┼─► Aurora Global secondary (read-only)     │
             │  DynamoDB (3 AZ) ◄───── global tables ───┼──┼─► DynamoDB replica                        │
             │  ElastiCache primary ──Global Datastore──┼──┼─► ElastiCache secondary                   │
             │  MSK (3 AZ) ─────── MSK Replicator ──────┼──┼─► MSK                                     │
             │  S3 (audit, Object Lock) ───── CRR ──────┼──┼─► S3 replica (Object Lock)                │
             └───────────────┬──────────────────────────┘  └───────────────┬──────────────────────────┘
                             └──────── Direct Connect gateway ─────────────┘
                                   2 DX links (different providers) + VPN
                                                 │
                       Bank on-premises: Core Banking, Complementary system (+ bank's own DR site)
```

In Structurizr this becomes `deploymentEnvironment "Production"` with `deploymentNode` for AWS, each region, each AZ, EKS, Aurora, MSK, and `containerInstance` for the services (Step 17).

---

## 10. Sources

- [AWS whitepaper: Disaster Recovery of Workloads on AWS (strategies)](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html)
- [AWS ARC: Region switch plans](https://docs.aws.amazon.com/r53recovery/latest/dg/region-switch-plans.html)
- [AWS ARC: Region switch execution blocks (Aurora Global Database, EKS scaling)](https://docs.aws.amazon.com/r53recovery/latest/dg/working-with-rs-execution-blocks.html)
- [AWS What&#39;s New: Region switch adds Aurora scaling (Jun 2026)](https://aws.amazon.com/about-aws/whats-new/2026/06/region-switch-aurora-scaling-neptune-failover)
- [AWS ARC: zonal shift and zonal autoshift](https://docs.aws.amazon.com/r53recovery/latest/dg/arc-zonal-shift.html)
- [Amazon Aurora Global Database: failover and switchover](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery.html)
- [AWS Fault Injection Service scenarios](https://docs.aws.amazon.com/fis/latest/userguide/scenario-library.html)
- [AWS Backup Vault Lock](https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html)
- [Kubernetes: liveness, readiness and startup probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/)
- [AWS Well-Architected Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html)

---

## Step 13 checklist

- [X] RTO / RPO / availability per tier
- [X] Multi-AZ HA per component (QAS-01)
- [X] DR strategies compared and chosen (ADR-018: warm standby T1, pilot light T2, backup & restore T3)
- [X] Failover runbook within 15 min, in-flight transfers and failback
- [X] Auto-healing mechanisms (QAS-14)
- [X] Graceful degradation per dependency
- [X] Backups isolated from replication (ransomware)
- [X] Chaos engineering and DR drill plan
- [X] Deployment view
- [x] Write the Structurizr deployment view `04-Deployment-Production` (Step 17)
- [x] State as an assumption that the identity product and payment-network link are available from both regions (PDF risks table: DR prerequisite)
