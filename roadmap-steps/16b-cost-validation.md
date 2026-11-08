# Step 16b: Cost validation with the AWS Price List

Supporting file for Step 16 and the PDF cost section. It shows where each figure comes from and how to reproduce it.

- **Date checked:** 8 Nov 2026 (price files published 2026-11-08T20:34Z).
- **Source of unit prices:** the public **AWS Price List bulk API** (no login): `https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<service>/current/us-east-1/index.json`, on-demand terms, USD, region **US East (N. Virginia)**. EC2 instance prices come from the file the AWS pricing page uses: `https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/ec2/USD/current/ec2-ondemand-without-sec-sel/US%20East%20(N.%20Virginia)/Linux/index.json`. CloudFront uses the global file (`AmazonCloudFront/current/index.json`), South America edge prices (Ecuadorian users).
- **Convention:** 730 hours a month. List prices, no enterprise discount (EDP), no taxes. Savings Plans / reservations noted separately.
- **Status:** **Verified** = unit price read from the Price List (quantity is still an assumption). **Partial** = unit price verified, part of the volume or cost estimated. **Estimated** = not in the Price List or depends on a quote.

## Sizing assumptions (from Step 0 / Step 16)

| Driver | Value |
| --- | --- |
| API requests | ~2.6 B a month (1,000 req/s average, 5,000 peak) |
| Monetary transactions / notices | ~164 M a month |
| Movements into the read model | ~300 M a month |
| Audit records | ~86 M a day (~2.6 B a month) |
| Edge data out | ~13 TB a month |
| Password logins (go through WAF Fraud Control) | ~5 M a month (most logins are biometric refreshes) |

## Production, line by line

| Component | Configuration | Unit price (Price List) | USD / month | Status |
| --- | --- | --- | --- | --- |
| EKS control plane | 2 clusters (primary + DR) | 0.10 / cluster-hour | 146 | Verified |
| EC2 nodes (Graviton) | m7g.xlarge: ~50 primary (avg) + ~15 DR; Compute Savings Plan on ~60% of primary | 0.1632 / hour | ≈ 6,700 | Verified (SP discount estimated) |
| Aurora PostgreSQL | Transfer: 3 × db.r7g.2xlarge; 4 other clusters: 2 × db.r7g.large; DR secondaries one size smaller | 1.106 / hour (r7g.2xlarge), 0.276 / hour (r7g.large) | ≈ 5,250 | Verified |
| Aurora storage and I/O | ~2 TB × 2 regions; ~2.5 B I/O (incl. replicated writes) | 0.10 / GB-month; 0.20 / M I/O | ≈ 900 | Partial |
| DynamoDB requests | Writes: movements 300 M, audit index 2.6 B, notifications 330 M, all × 2 regions (global tables); reads ~0.7 B | 0.625 / M WRU; 0.125 / M RRU | ≈ 4,100 | Partial |
| DynamoDB storage + PITR | ~4.5 TB per region × 2 | 0.25 / GB-month (+ PITR) | ≈ 4,000 | Partial |
| ElastiCache (Valkey) | 6 × cache.r7g.xlarge primary, 3 DR | 0.3496 / node-hour (Valkey) | ≈ 2,300 | Verified |
| MSK | 6 × kafka.m7g.xlarge primary, 3 DR, 9 TB storage, MSK Replicator | 0.408 / broker-hour; 0.10 / GB-month | ≈ 4,100 | Partial (Replicator estimated) |
| Direct Connect ports | 2 × 10G dedicated | 2.25 / port-hour | ≈ 3,300 | Verified |
| Carrier circuits Ecuador → DX location | 2 diverse international circuits | — | Quote | Estimated |
| Network Firewall | 3 endpoints × 2 regions, ~20 TB processed | 0.38–0.395 / endpoint-hour; 0.065 / GB | ≈ 3,000 | Verified |
| NAT, Transit Gateway, VPC endpoints, NLB | 2 regions | — | ≈ 1,500 | Estimated |
| CloudFront (South America) | 2.6 B HTTPS requests; 13 TB out | 0.022 / 10k HTTPS requests; 0.110 / GB first 10 TB, 0.105 next 40 TB | ≈ 7,100 | Verified |
| AWS WAF | Requests (Shield-protected web ACLs have no ACL fee) | 0.60 / M requests; 1.00 / rule | ≈ 1,600 | Verified |
| WAF Bot Control (targeted) | Scoped to ~150 M sensitive requests | 10 / M requests | ≈ 1,500 | Verified |
| WAF Fraud Control (ATP) | ~5 M password logins | 1.00 / 1,000 requests (tier 1, lower tiers above) | ≈ 5,000 | Verified (volume assumed) |
| Shield Advanced | Organization subscription | 3,000 / month (pricing page) + data-transfer fees | ≈ 3,000 | Partial |
| CloudHSM | 2 HSMs × 2 regions | 1.60 / HSM-hour | ≈ 4,700 | Verified |
| GuardDuty, Security Hub, Inspector, Macie, Security Lake, KMS | Usage-based | — | ≈ 5,000 | Estimated |
| Observability | Managed Prometheus, Grafana, CloudWatch Logs IA, traces, RUM, Synthetics | — | ≈ 10,000 | Estimated |
| S3, backups, Athena | Audit archive, AWS Backup copies | — | ≈ 1,500 | Estimated |
| Amazon SES | ~164 M emails | 0.10 / 1,000 recipients | ≈ 16,400 | Verified |
| **Production total** | | | **≈ 91,000** | > 60% verified |
| Non-production (scheduled shutdown) | Staging ~30%, dev/QA ~15% of the variable lines | | ≈ 20,000–25,000 | Estimated |
| **AWS total** | | | **≈ 111,000–116,000** | |

### Outside AWS

| Item | Basis | USD / month | Status |
| --- | --- | --- | --- |
| SMS (local aggregator) | ~164 M messages × 0.005–0.02 | 0.8 M – 3.3 M | Estimated (quote) |
| Registro Civil (SNIC) | 50 k × 0.30 | 15,000 | Verified (gob.ec) |
| eKYC vendor | 50 k × 0.5–2 | 25,000–100,000 | Estimated (quote) |
| Kong Enterprise, RASP SDK, PagerDuty, fraud engine | Licences | Quote | Estimated |

## What changed versus the first estimate (Step 16)

- Compute is lower (≈ 6.7 k vs 8 k): m7g.xlarge list price is 0.1632/h.
- DynamoDB is higher (≈ 8 k vs 5 k): the audit hot index (2.6 B writes a month) replicated to two regions dominates. **Lever:** keep the audit hot index in one region (it can be rebuilt from the S3 archive after a failover) and use the Standard-IA table class: saves ≈ 3 k a month.
- WAF Fraud Control is priced per login request (1 USD per 1,000 at tier 1), so it must stay scoped to password logins.
- Totals stay inside the original range (AWS ≈ USD 105–120 k a month).

## How to reproduce one line

```bash
curl -s https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonElastiCache/current/us-east-1/index.json \
  | python -c "import json,sys; d=json.load(sys.stdin)
for k,p in d['products'].items():
  a=p['attributes']
  if a.get('usagetype')=='NodeUsage:cache.r7g.xlarge':
    for t in d['terms']['OnDemand'][k].values():
      for pd in t['priceDimensions'].values(): print(pd['description'])"
```
