# Step 3: Cloud provider and region strategy

**Inputs:** Step 0 (A-04/A-05 load, A-07/A-08 availability and recovery, A-11 on-premises Core) and Step 2 (SB cloud and outsourcing conditions, LOPDP processor rules).

---

## 1. Facts that drive the decision

### 1.1 There is no hyperscaler region in Ecuador

| Location | AWS | Azure |
| --- | --- | --- |
| Ecuador | No region | No region |
| Colombia (Bogotá) | Local Zone announced, launch not confirmed | No region found |
| Peru (Lima) | **Local Zone** (parent: us-east-1) | No region |
| Chile (Santiago) | Local Zone (parent: us-east-1). **Full region announced for end of 2026, not yet confirmed as open.** | **Chile Central**, 3 availability zones |
| Mexico (Querétaro) | mx-central-1 | Mexico Central |
| Brazil (São Paulo) | sa-east-1 | Brazil South (paired with South Central US) |
| USA (Virginia / Ohio) | us-east-1 / us-east-2 | East US / East US 2 |

So the platform **will be hosted abroad** in any case. Step 2 says that's allowed if the bank **informs the SB**, uses **Tier III / TIA-942** data centres and **ISO 27001/27017/27018**-certified providers, has an **annual independent audit**, and signs a **LOPDP processing contract**. Both AWS and Azure meet the certification requirements.

### 1.2 Measured latency from Ecuador

Measured on 8 Nov 2026 from **Cuenca, Ecuador (ISP: ETAPA)**. The value is the TCP connect time to the regional EC2 endpoint, which is roughly one network round trip. 5 samples per region; the first sample includes DNS lookup and is excluded.

| AWS region | Round trip (ms) |
| --- | --- |
| **us-east-1** (N. Virginia) | **~90** |
| us-east-2 (Ohio) | ~103 |
| mx-central-1 (Mexico) | ~118 |
| ca-central-1 (Canada) | ~120 |
| sa-east-1 (São Paulo) | ~157 |
| us-west-2 (Oregon) | ~157 |

**Why São Paulo is slower than Virginia:** Ecuador's submarine cables land on the Pacific coast and connect mainly to the USA (Miami). Traffic to Brazil usually goes through Miami first. Geographic closeness doesn't mean network closeness.

> **To do:** repeat the test from Quito and Guayaquil, and run [azurespeed.com](https://www.azurespeed.com) in a browser for the Azure regions (including **Chile Central**). Add the results to this table. Azure's US East and Brazil regions are in the same metros as AWS's, so expect similar numbers; Chile Central is the unknown.

**Is ~90 ms enough?** QAS-06 asks for a dashboard p95 under 500 ms. With connection reuse (HTTP/2), one round trip (~90 ms) plus a cache hit (~10 ms) leaves plenty of margin. Terminating TLS at a CDN edge close to users (CloudFront / Front Door) also removes the handshake round trips from the critical path.

---

## 2. ADR-002: Cloud provider

**Status:** Proposed (Azure remains a valid alternative)

**Context.** The statement allows AWS or Azure. The system needs: low latency from Ecuador, regulatory evidence for the SB, multi-AZ and multi-region services that meet RTO 15 min / RPO 1 min for critical journeys, managed messaging, caching, immutable storage for audit, and edge security.

### Options compared

Scores from 1 (weak) to 5 (strong). Weights reflect the grading criteria and the Step 0 requirements.

| Criterion | Weight | AWS | Azure | Notes |
| --- | --- | --- | --- | --- |
| Latency from Ecuador | 20% | 5 | 4 | AWS us-east-1 measured at ~90 ms. Azure Chile Central is unmeasured and might be competitive. |
| Multi-region data services for the RPO/RTO target | 20% | 5 | 4 | AWS: Aurora Global Database (typical replication lag < 1 s), DynamoDB global tables, Route 53 Application Recovery Controller. Azure: SQL failover groups, Cosmos DB multi-region. Both work. AWS's managed global failover is more mature. |
| Regulatory evidence (ISO 27001/27017/27018, SOC 2, Tier III) | 15% | 5 | 5 | Both. AWS Artifact / Microsoft Service Trust Portal. |
| Immutable audit storage (WORM) | 10% | 5 | 5 | S3 Object Lock / Azure immutable Blob storage. |
| Edge security (CDN, WAF, DDoS) | 10% | 5 | 5 | CloudFront + WAF + Shield / Front Door + WAF + DDoS Protection. |
| Future proximity (South America) | 10% | 4 | 5 | Azure Chile Central exists today. AWS has Lima and Santiago Local Zones, with a Chile region announced. |
| Enterprise fit at the bank | 10% | 3 | 4 | Not public. Large banks often have Microsoft enterprise agreements, and the bank's known cloud product is Oracle (ERP). Neutral to slightly in Azure's favour. |
| Ecosystem and talent in the region | 5% | 4 | 4 | Both strong. |
| **Weighted total** | 100% | **4.65** | **4.45** | Close: the decision is defensible either way. |

**Decision:** **AWS.**

### Justifications

1. **Measured latency.** us-east-1 has the lowest measured round trip from Ecuador (~90 ms), and it's AWS's largest region with every service available. Low latency is an explicit requirement of the statement.
2. **Recovery targets met with managed services.** Aurora Global Database gives cross-region replication typically under 1 second, which meets the critical-journey RPO of 1 minute. Combined with Route 53 Application Recovery Controller, a managed regional failover fits within the 15-minute RTO. Less custom DR code means less operational risk, which matters given the bank's 2025 outages.
3. **Well-Architected Financial Services Industry Lens.** AWS publishes a framework specific to financial services (resilience, compliance and data protection controls). The proposal can use it as a reference to justify the design to the SB.

### Trade-offs and when to revisit

- Azure Chile Central might give lower latency to Ecuador. If measurements show it beats ~90 ms clearly, re-evaluate.
- Revisit when the **AWS Chile region** opens. It may offer lower latency and South American data residency.
- Lock-in mitigation: containers (Kubernetes), open protocols (OIDC, OpenTelemetry, Kafka-compatible messaging) and Terraform keep the application layer portable.

---

## 3. ADR-003: Region strategy

**Status:** Proposed

| Role | Region | Why |
| --- | --- | --- |
| **Primary** | **us-east-1** (N. Virginia), **3 availability zones** | Lowest measured latency. Multi-AZ covers HA (QAS-01). |
| **DR** | **us-east-2** (Ohio) | Second-lowest latency (~103 ms), so performance during failover stays acceptable. A different geography and power grid satisfies the SB rule that the alternate site **must not share the primary site's risks**. |
| Edge | CloudFront points of presence | TLS termination, caching of SPA assets, and WAF close to users. |

**Alternatives considered:** São Paulo as primary (higher latency and higher prices); us-east-1 + sa-east-1 (South American DR, but ~157 ms during failover); a single region with multi-AZ only (doesn't meet the SB's remote recovery site requirement or a region-wide failure).

**DR mode:** decided in Step 13. The target for critical journeys is **warm standby** (scaled-down but running in us-east-2). For non-critical services, a pilot light or backup-and-restore is enough.

---

## 4. Hybrid connectivity to the bank (Core and complementary system)

The Core and the complementary customer system stay **on-premises in Ecuador** (A-11). Every call from the cloud to the Core crosses ~90 ms of network, so:

- **Connectivity:** **2 AWS Direct Connect links** through **different providers and locations** (the SB requires alternate providers for critical services), plus a **Site-to-Site VPN** as a third backup path. Check which Direct Connect partners serve Ecuador.
- **Design consequences** (detailed in Steps 8–9):
  - Don't call the Core synchronously for every read. Use a **cache** and a **read model** in the cloud (CQRS) for movements and customer data.
  - Use **asynchronous** posting for interbank transfers.
  - Protect the Core with **circuit breakers** and **rate limiting**.

---

## 5. Landing zone and account structure

The SB requires isolated development, test and production environments with segregated access.

- **AWS Organizations + Control Tower** as the landing zone.
- **Separate accounts** for: production, staging, development, shared networking, security tooling, and **log archive** (where audit and CloudTrail logs land, with restricted access).
- **Service control policies (SCPs)** that block use of regions other than us-east-1 and us-east-2, so data can't end up anywhere else by mistake.

---

## 6. Compliance evidence for the SB dossier (from Step 2)

| SB / LOPDP condition | AWS evidence |
| --- | --- |
| Tier III / TIA-942 data centres | AWS data centre design attestations (request through the account team) |
| ISO 27001, 27017, 27018 | AWS Artifact certificates |
| Annual independent security audit | SOC 1/2/3 Type II reports (AWS Artifact) |
| Data used only for the contracted purpose; secure deletion | AWS Customer Agreement + Data Processing Addendum; customer-managed KMS keys, so data can be crypto-shredded |
| LOPDP processing contract | AWS Data Processing Addendum |
| Notify the SB of critical services hosted abroad | Prepared by the bank. The PDF architecture and risk sections feed it. |

---

## 7. Sources

- [AWS: Chile region announcement (May 2025)](https://press.aboutamazon.com/aws/2025/5/amazon-to-invest-more-than-4-billion-to-launch-infrastructure-region-in-chile)
- [AWS: Chile data privacy page (region expected 2H 2026)](https://aws.amazon.com/compliance/chile-data-privacy/)
- [AWS: available Local Zones](https://docs.aws.amazon.com/local-zones/latest/ug/available-local-zones.html)
- [Microsoft: Azure availability zones overview](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview)
- [Azure regions list (third-party summary)](https://www.azurespeed.com/Information/AzureRegions)
- [Oracle: Banco Pichincha uses Oracle Fusion Cloud ERP](https://blogs.oracle.com/oracle-latinoamerica/banco-pichincha-toma-decisiones-mas-agiles-y-rentables-con-oracle-fusion-cloud-erp)
- Latency: measured from this machine (Cuenca, Ecuador), 8 Nov 2026

---

## Step 3 checklist

- [x] Region availability near Ecuador checked
- [x] Latency measured from Ecuador (AWS)
- [x] Provider chosen with a weighted comparison (ADR-002)
- [x] Primary and DR regions chosen (ADR-003)
- [x] Hybrid connectivity to the on-premises Core outlined
- [x] Landing zone and environment isolation outlined
- [ ] **Your review:** measure Azure (especially Chile Central) at azurespeed.com, and from Quito/Guayaquil if possible
- [ ] **Your review:** confirm whether the AWS Chile region has opened
