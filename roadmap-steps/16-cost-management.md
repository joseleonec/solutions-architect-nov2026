# Step 16: Cost management

**Inputs:** Step 0 (A-02..A-06 load: ~5.5 M active users, ~2 M DAU, ~160 TPS normal / 500 TPS payday, ~5,000 req/s gateway peak; QAS-16 cost follows usage), Step 3 (us-east-1 + us-east-2, Direct Connect), Step 7 (Registro Civil USD 0.30 per check), Steps 8–14 (component choices and sizing), Step 11 (SMS cost), Step 13 (warm standby).

> **How to read the numbers.** Order-of-magnitude estimates from **AWS list prices (us-east-1, on-demand unless stated)** and the sizing assumptions of earlier steps. They are meant to show **where the money goes** and which decisions matter. Before the final PDF, enter the main lines in the [AWS Pricing Calculator](https://calculator.aws/) and attach the export link. Vendor licences (Kong Enterprise, RASP, eKYC, fraud engine, PagerDuty) need quotes and are listed separately.

---

## 1. Sizing assumptions used for cost

| Driver | Value | Source |
| --- | --- | --- |
| API requests | ~1,000 req/s average, 5,000 peak → **~2.6 B requests a month** | A-05 |
| Monetary transactions | **~164 M a month** | Step 0 §4.1 |
| Movements written to the read model (all channels) | ~300 M a month | Step 9 |
| Audit records | ~86 M a day | Step 10 |
| Onboardings | ~50 k a month | Step 7 |
| Production compute (primary, average) | ~200 vCPU / 800 GB RAM (≈ 50 × 4-vCPU Graviton nodes), peaks ×2 | Steps 8, 13 |

---

## 2. Monthly cost estimate: AWS platform (production, both regions)

| Area | Main components | Estimate (USD / month) |
| --- | --- | --- |
| **Compute** | EKS control planes; ~50 Graviton nodes average in us-east-1 (Savings Plan on the baseline); warm standby in us-east-2 at ~30% | **~8,000** |
| **Aurora PostgreSQL** | 5 clusters (Transfer the largest: writer + 2 readers); Global Database secondaries one size smaller; reserved instances | **~6,500** |
| **DynamoDB** | Movements read model (~2 TB × 2 regions), Device, Notification log, audit hot index (~2.6 B writes a month), PITR | **~5,000** |
| **ElastiCache (Valkey)** | ~30 GB cluster, 3 shards × 2 nodes, Global Datastore secondary | **~2,500** |
| **MSK** | 6 brokers primary, 3 brokers DR, storage, MSK Replicator | **~4,500** |
| **Networking** | 2 Direct Connect dedicated ports, Transit Gateway, NAT gateways, Network Firewall (3 AZ × 2 regions), VPC interface endpoints, NLBs | **~7,000** |
| **Edge** | CloudFront (South America pricing for Ecuadorian users; ~2.6 B HTTPS requests, ~13 TB out), AWS WAF, Shield Advanced (USD 3,000 fixed), Bot Control / Account Takeover Prevention scoped to login endpoints | **~15,000–22,000** |
| **Security** | GuardDuty (incl. EKS runtime), Security Hub, Inspector, Macie, Security Lake, KMS, Secrets Manager, CloudHSM (2 HSMs × 2 regions) | **~10,000** |
| **Observability** | Managed Prometheus, Managed Grafana, CloudWatch Logs (Infrequent Access), traces (tail-sampled), RUM, Synthetics | **~10,000** |
| **Storage and backup** | S3 (audit archive, SPA, exports), AWS Backup copies, Athena | **~1,500** |
| **Email** | Amazon SES, ~164 M emails | **~16,000** |
| **Production subtotal** | | **≈ 85,000–95,000** |
| **Non-production** | Staging (~30% of prod, same modules), dev / QA (~15%), scheduled shutdown nights and weekends | **≈ 20,000–25,000** |
| **AWS total** | | **≈ 105,000–120,000 / month (≈ USD 1.3–1.4 M / year)** |

**Unit cost:** ~USD 110 k / 5.5 M active digital users ≈ **USD 0.02 per active user per month**, or ≈ **USD 0.0007 per monetary transaction**.

---

## 3. Third-party and usage costs (outside AWS)

| Item | Basis | Estimate (USD / month) |
| --- | --- | --- |
| **SMS** (regulatory notices + OTPs) | ~164 M+ messages × negotiated price | **~800,000 (at 0.005) to ~3,300,000 (at 0.02)** |
| Push notifications | FCM / APNs | 0 |
| **Registro Civil** checks | 50 k × USD 0.30 | ~15,000 |
| eKYC vendor | 50 k verifications × vendor price | Quote (typically USD 0.5–2 per verification → ~25,000–100,000) |
| Kong Enterprise, RASP SDK, PagerDuty, fraud engine (if bought), SIEM ingestion | Licences | Quotes |
| Payment network fees | Per transaction, set by the network / BCE | Bank's existing cost |

**The finding:** the cloud platform is **not** the main running cost. **SMS for regulatory notices costs 7–30 times more than all of AWS** (9–38 times once login notices are included, see 16b). Cost management effort should go first to the SMS price and to whether push can replace part of the SMS volume (Step 11).

---

## 4. Cost impact of the DR strategy (ADR-018)

| Strategy for T1 | Extra monthly cost (approx.) | RTO / RPO |
| --- | --- | --- |
| Backup & restore | ~USD 2,000 | Hours / hours: **doesn't meet** QAS-02 |
| Pilot light | ~USD 6,000 | ~1 h / seconds: doesn't meet RTO 15 min |
| **Warm standby (chosen)** | **~USD 10,000–12,000** (≈ 12–15% of production) | **≤ 15 min / ≤ 1 min** |
| Active/active | ~USD 50,000–60,000 (second full-size stack + conflict handling) | Near zero |

Warm standby buys the required RTO/RPO for about **USD 130–150 k a year**, which is small next to the cost of a multi-hour outage for the largest bank in the country (the 2025 outages led to sanctions and a deposit run of ~USD 160 M, Step 0).

---

## 5. ADR-021: Cost optimization approach

**Status:** Proposed

**Decision.** Commit to the **steady baseline** (Compute Savings Plans, Aurora reserved instances), scale **everything above the baseline** automatically, run on **Graviton (ARM)**, and manage cost continuously with **FinOps** practices (tagging, budgets, anomaly detection, unit metrics).

### Justifications

1. **The load has a clear baseline and predictable peaks** (nights ~10% of peak, payday 3×, Step 0). Committing only to the baseline (~60% of average) gets the Savings Plan discount without paying for idle peak capacity, and Karpenter / HPA / KEDA add and remove capacity for the rest (QAS-16).
2. **Graviton gives better price-performance** for Java services, Aurora, ElastiCache and MSK (AWS quotes up to ~40% better price-performance than comparable x86), with no code change for JVM workloads.
3. **Cost is a shared, measured responsibility.** Tags per service and team, budgets and anomaly alerts make every team see its own cost, so waste is found within days, not at the end of the quarter.

### Optimization levers

| Lever | Where | Expected effect |
| --- | --- | --- |
| **Compute Savings Plans** (1 or 3 years) on the baseline | EKS nodes | Large discount vs on-demand on ~60% of compute |
| **Reserved instances** | Aurora, ElastiCache, MSK brokers in production | Same idea for data services |
| **Graviton** everywhere | Compute and managed databases | Better price-performance |
| **Auto-scaling + Karpenter consolidation** | EKS | Nights and weekends shrink the cluster (QAS-16) |
| **Scheduled shutdown of non-production** | Dev / QA (off nights and weekends) | ~65% fewer running hours |
| **Spot instances** | CI runners, non-production, batch jobs (never T1 production) | Large discount on interruptible work |
| **Caching** (Step 9) | Fewer Core calls, fewer DynamoDB reads | Also protects the Core |
| **VPC endpoints** | S3, DynamoDB (gateway endpoints are free) | Less NAT data processing |
| **Scope WAF Bot Control / ATP** to login and sensitive routes | Edge | These are priced per request analysed |
| **CloudFront** compression, caching of static and reference data | Edge | Less transfer out |
| **Logs**: Infrequent Access class, no debug in production, short online retention; **tail sampling** of traces | Observability | Logs are usually the biggest observability cost |
| **S3 lifecycle** to Glacier Deep Archive | Audit archive (Step 10) | 10 years of audit for little cost |
| **DynamoDB capacity mode**: on-demand at launch, provisioned + auto-scaling once the pattern is stable | Read models | Lower cost on steady tables |
| **SMS price negotiation + push where allowed** | Notifications | The largest saving available |
| **Monthly right-sizing** with Compute Optimizer | All | Removes over-provisioning |

---

## 6. FinOps practices

| Practice | Implementation |
| --- | --- |
| **Tagging** | Mandatory tags `service`, `team`, `env`, `tier`, `cost-center`, enforced by **tag policies** and checked in the Terraform pipeline (Checkov) |
| **Account structure** | Cost per environment visible by account (Step 3) |
| **Budgets and alerts** | AWS Budgets per account and per team; alerts at 80% and 100% of forecast |
| **Anomaly detection** | AWS Cost Anomaly Detection per service, alerts to the owning team |
| **Reporting** | Cost and Usage Report (CUR 2.0) → Athena → Grafana dashboard next to the SLO dashboards (Step 14) |
| **Unit metrics** | Cost per active user, per transaction, per onboarding, per SMS: tracked monthly |
| **Showback** | Each team sees its monthly cost; reviewed in a monthly FinOps meeting with finance and engineering |
| **Commitment management** | Quarterly review of Savings Plans and reservation coverage and utilization |

---

## 7. Sources

- [AWS Pricing Calculator](https://calculator.aws/)
- [Amazon EKS pricing](https://aws.amazon.com/eks/pricing/), [EC2 Graviton](https://aws.amazon.com/ec2/graviton/), [Savings Plans](https://aws.amazon.com/savingsplans/)
- [Amazon Aurora pricing](https://aws.amazon.com/rds/aurora/pricing/)
- [Amazon DynamoDB pricing](https://aws.amazon.com/dynamodb/pricing/)
- [Amazon ElastiCache pricing](https://aws.amazon.com/elasticache/pricing/)
- [Amazon MSK pricing](https://aws.amazon.com/msk/pricing/)
- [Amazon CloudFront pricing](https://aws.amazon.com/cloudfront/pricing/), [AWS WAF pricing](https://aws.amazon.com/waf/pricing/), [AWS Shield pricing](https://aws.amazon.com/shield/pricing/)
- [AWS Direct Connect pricing](https://aws.amazon.com/directconnect/pricing/)
- [Amazon SES pricing](https://aws.amazon.com/ses/pricing/)
- [AWS Well-Architected: Cost Optimization Pillar](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/welcome.html)
- [FinOps Foundation: FinOps framework](https://www.finops.org/framework/)

---

## Step 16 checklist

- [x] Rough monthly estimate per area (AWS ≈ USD 105–120 k / month)
- [x] Third-party costs, with SMS identified as the dominant cost
- [x] Cost impact of each DR strategy
- [x] Optimization approach (ADR-021) and levers
- [x] FinOps practices
- [x] Price check: replaced by the AWS Price List validation in [16b-cost-validation.md](16b-cost-validation.md) (reproducible queries instead of a calculator link)

---

## Update (8 Nov 2026)

Unit prices were checked against the public AWS Price List: see [16b-cost-validation.md](16b-cost-validation.md). Production ≈ USD 97 k a month (> 60% of it from verified unit prices); AWS total ≈ USD 117–122 k a month. The validation also adds ~60 M **login notices** a month (SMS + email) that this first estimate missed: SMS becomes ≈ USD 1.1–4.5 M a month. Cost per delivery stage: [19-delivery-plan.md](19-delivery-plan.md).
