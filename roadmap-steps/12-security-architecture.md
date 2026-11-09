# Step 12: Security architecture (cross-cutting)

**Inputs:** Step 2 (SB electronic-channel and cloud rules, LOPDP, biometrics, breach notification), Step 3 (landing zone with separate accounts, SCPs), Step 5 (SPA and mobile security, MASVS L2 + R), Step 6 (FAPI 2.0, DPoP, step-up, device binding), Step 8 (Kong, Istio mTLS), Step 9 (encryption, tokenization, masking), Step 10 (immutable audit), Step 11 (notification security).

This step pulls the controls from earlier steps into **one view**, fills the gaps (perimeter, network, keys, detection, DevSecOps, fraud), and maps everything to the regulation.

---

## 1. Principles

| Principle | What it means here |
| --- | --- |
| **Zero Trust** (NIST SP 800-207) | No implicit trust from network location. Every call is authenticated and authorized: customer → BFF (token + device), service → service (mTLS identity + policy), staff → console (SSO + phishing-resistant MFA). |
| **Defence in depth** | Each threat is stopped by at least two independent layers (e.g. stolen token: DPoP binding **and** step-up **and** risk scoring). |
| **Least privilege** | One IAM role per service, per-route scopes, write-only access to the audit archive, no standing admin access. |
| **Secure by default** | Encryption everywhere, private networking, deny-by-default network and IAM policies, security headers, hardened images. |
| **Assume breach** | Detect fast (SIEM, GuardDuty), limit blast radius (accounts, segments, bulkheads), keep immutable evidence (Step 10). |

---

## 2. Security view (layers and controls)

```text
┌─ 1. Client ───────────────────────────────────────────────────────────────────────────────┐
│ Mobile: RASP, Play Integrity / App Attest, cert pinning, keys in Secure Enclave/StrongBox,  │
│         obfuscation, screenshot blocking (MASVS L2+R)                                       │
│ Web:    no tokens in browser (BFF), CSP + Trusted Types, HttpOnly SameSite cookies, HSTS    │
├─ 2. Edge ─────────────────────────────────────────────────────────────────────────────────┤
│ CloudFront (TLS 1.2+/1.3) · AWS WAF (OWASP managed rules, Bot Control, Account Takeover    │
│ Prevention, rate-based rules, geo rules) · Shield Advanced (DDoS + response team)          │
├─ 3. API ──────────────────────────────────────────────────────────────────────────────────┤
│ Kong: JWT + DPoP validation, scopes, acr per route, rate limits per customer/device,        │
│ schema validation, size limits, revocation list · BFF session controls                      │
├─ 4. Identity ─────────────────────────────────────────────────────────────────────────────┤
│ OIDC/FAPI 2.0: PAR, PKCE, DPoP, private_key_jwt · 2-of-3 factors · step-up with dynamic     │
│ linking · device binding · lockout after 3 failures · staff SSO + FIDO2 MFA                 │
├─ 5. Service ──────────────────────────────────────────────────────────────────────────────┤
│ Istio ambient mTLS + authorization policies · object-level authorization in every service   │
│ · input validation · idempotency · secure libraries · Risk Scoring before money moves       │
├─ 6. Network ──────────────────────────────────────────────────────────────────────────────┤
│ VPC per account · private subnets only · VPC endpoints (PrivateLink) for AWS services ·     │
│ Network Firewall with egress allowlist · Transit Gateway + Direct Connect (MACsec/IPsec) ·   │
│ Kubernetes NetworkPolicies (deny by default)                                                │
├─ 7. Data ─────────────────────────────────────────────────────────────────────────────────┤
│ KMS customer-managed keys per domain · CloudHSM for HSM-bound keys · field-level encryption │
│ · tokenization · masking · Macie for S3 · crypto-shredding                                  │
├─ 8. Detection and response ───────────────────────────────────────────────────────────────┤
│ CloudTrail (org) · GuardDuty (incl. EKS runtime) · Security Hub · Inspector · Security Lake │
│ → SIEM / 24×7 SOC · immutable audit (Step 10) · incident runbooks (SB 5/10 days, SPDP 5 d)  │
├─ 9. Governance and supply chain ──────────────────────────────────────────────────────────┤
│ Control Tower + SCPs · IaC only (Terraform) · DevSecOps pipeline · signed images + admission│
│ control · annual pentest · MASVS verification · DPIA                                        │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Perimeter

| Control | Configuration |
| --- | --- |
| **CloudFront** | Only entry point; origins (S3, NLB) not reachable from the internet (Origin Access Control, origin secret header, security groups with the CloudFront prefix list). |
| **AWS WAF** | AWS Managed Rules (core rule set, known bad inputs, SQL injection, Linux/Java), **Bot Control** (targeted), **Account Takeover Prevention** on the login endpoints (credential stuffing), rate-based rules per IP, body size limits. Rules in count mode first, then block. |
| **Shield Advanced** | Layer 3/4/7 DDoS protection, cost protection for scaling during attacks, access to the AWS Shield Response Team. Justified by the bank's size and the 2025 outages. |
| **Kong** | Second line: per-customer and per-device rate limits, which the WAF can't see because it doesn't know the user. |

---

## 4. Network

| Control | Detail |
| --- | --- |
| Account separation | Production, staging, development, shared networking, security tooling, log archive (Step 3). Production data never leaves production. |
| Subnets | Public subnets only for the NLB; EKS nodes, databases, Kafka, Redis in **private subnets** with no public IPs. |
| Private access to AWS services | **VPC endpoints** (S3, DynamoDB, KMS, Secrets Manager, ECR, STS, CloudWatch) so traffic doesn't cross the internet. |
| Egress control | **AWS Network Firewall** with an **allowlist** of domains: eKYC vendor, SMS and email providers, FCM/APNs, payment network. Everything else denied (limits data exfiltration and malware call-backs). |
| On-premises link | Transit Gateway → 2 Direct Connect links (+ VPN backup), encrypted (MACsec or IPsec). Only the Core Adapter, Customer Info Adapter and Debezium can reach on-prem ranges. |
| Inside the cluster | Istio ambient **mTLS** for all service traffic; authorization policies (only Transfer may call the Core Adapter's posting API); Kubernetes **NetworkPolicies** deny by default. |
| Segmentation by tier | Payment-related services (Transfer, Interbank Connector, Core Adapter) in their own namespace and node pool. |

---

## 5. Secrets, keys and certificates

| Item | Where | Rotation |
| --- | --- | --- |
| Data encryption keys | **AWS KMS** customer-managed keys, one per data domain and environment | Automatic yearly; key policies limit use to the owning service role |
| Keys that must live in a dedicated HSM (e.g. OTP seeds, payment-network signing keys if the BCE or the network require it) | **AWS CloudHSM** (FIPS 140-3 Level 3) | Per the network's key policy |
| Token signing keys (IdP) | KMS / HSM of the identity product | Regularly, published via JWKS with overlap |
| Audit digest signing key | KMS asymmetric key used only by the Audit service | Yearly, old keys kept for verification |
| DB passwords, API keys of providers | **Secrets Manager**, fetched at runtime (EKS Pod Identity), never in images or Git | Automatic (30–90 days) |
| Internal certificates (mesh) | Istio CA backed by **AWS Private CA** | Hours (automatic) |
| Public certificates | **ACM** on CloudFront and NLB | Automatic |

Step 2 requires "purpose-specific technology to generate and validate passwords, always encrypted": passwords are hashed by the identity product (Argon2 / bcrypt / PBKDF2 per its configuration), OTP seeds in the HSM.

---

## 6. Application and API security (OWASP mapping)

| OWASP API Security Top 10 (2023) | Control in this design |
| --- | --- |
| API1 Broken Object Level Authorization | Every service checks the account / beneficiary belongs to `sub` (Step 6) |
| API2 Broken Authentication | FAPI 2.0, DPoP, MFA, lockout, ATP rules in WAF |
| API3 Broken Object Property Level Authorization | Response DTOs per screen in the BFFs (no internal fields exposed); request schema validation |
| API4 Unrestricted Resource Consumption | Rate limits at WAF and Kong, pagination limits, request size limits, load shedding |
| API5 Broken Function Level Authorization | Scopes + `acr` per route at Kong; admin APIs not exposed through the public gateway |
| API6 Unrestricted Access to Sensitive Business Flows | Risk Scoring, limits, step-up, velocity checks, bot control |
| API7 Server-Side Request Forgery | No user-supplied URLs fetched; egress allowlist |
| API8 Security Misconfiguration | IaC with policy checks, CIS benchmarks via Security Hub, hardened images |
| API9 Improper Inventory Management | All APIs declared in OpenAPI and in Kong config from Git; versioning and sunset rules |
| API10 Unsafe Consumption of APIs | Vendor responses validated and treated as untrusted (ACLs, schema validation, timeouts) |

OWASP Top 10 (web) is covered by Angular defaults + CSP (XSS), parameterized queries (injection), security headers, dependency scanning (vulnerable components) and the BFF session model.

---

## 7. Fraud prevention and transaction controls

Step 2 requires **real-time risk profiling** that allows or rejects monetary transactions and notifies the customer.

| Element | Design |
| --- | --- |
| **Risk Scoring service** (Step 4) | Called synchronously by Transfer before posting (budget 300 ms). Returns **allow / step-up / reject**. |
| Signals | Device (new, binding age, RASP alerts, attestation verdict), behaviour (usual hours, amounts, beneficiaries), velocity (transfers per hour / day), beneficiary risk (new, flagged as mule, many incoming from different senders), session (IP reputation, geolocation change, SIM-swap signal if the carrier provides one) |
| Engine | Rules first (explainable, fast to change by the fraud team) + an ML score as one more input. Rules and models versioned; every decision stored and audited. |
| Limits | Per transaction, per day, per beneficiary type; customer-configurable within bank maximums (Beneficiary & Limits); **cooling period** for new beneficiaries (lower limits first 24 h). |
| Response | Reject → customer notified with reason (Step 2); suspicious patterns → AML Monitoring (asynchronous) and fraud case management. |
| Mule accounts | Incoming payment patterns watched by AML Monitoring (Step 8 incoming payments). |
| Social engineering | In-app warnings on first transfer to a new beneficiary, and a **confirmation screen showing the beneficiary name** returned by the network's key lookup (`acmt`, Step 8). |

**Buy vs build:** the platform design allows a commercial fraud engine (e.g. Feedzai, FICO Falcon, NICE Actimize) behind the Risk Scoring interface. Decide with the bank's fraud team; the architecture doesn't change.

---

## 8. Detection, monitoring and incident response

| Control | Purpose |
| --- | --- |
| **CloudTrail** organization trail → log archive (Object Lock) | All API activity on the AWS accounts |
| **GuardDuty** (including EKS audit logs and runtime monitoring, S3, RDS protection) | Threat detection: compromised credentials, crypto-mining, unusual data access |
| **Security Hub** (AWS Foundational Security Best Practices, CIS) | Configuration posture, findings in one place |
| **Inspector** | Vulnerabilities in container images and EC2 |
| **Macie** | Finds personal data in S3 buckets where it shouldn't be |
| **Amazon Security Lake** → **SIEM** (the bank's SIEM, e.g. Splunk / Microsoft Sentinel) | Correlation with on-premises and identity events; 24×7 SOC |
| Audit trail (Step 10) | Evidence for investigations; integrity alerts |
| **Incident runbooks** | Severity levels; **SB**: formal report ≤ 5 days, root cause ≤ 10 days; **SPDP** personal-data breach: processor → bank ≤ 2 days, bank → SPDP ≤ 5 days, plus affected customers. Contract clauses with every provider for the 2-day rule. |
| 24/7 blocking channel (Step 2) | Call center → Device service / IdP to block devices and sessions |

---

## 9. DevSecOps and supply chain

| Stage | Control |
| --- | --- |
| Code | Branch protection, mandatory review, **SAST** (e.g. Semgrep / SonarQube), **secret scanning** |
| Dependencies | **SCA** (Dependabot / Snyk), license policy, **SBOM** generated per build |
| Infrastructure as code | Terraform with **policy checks** (Checkov / OPA) before apply; no console changes in production (SCP + break-glass only) |
| Build | Minimal base images (distroless), image scanning (Inspector / Trivy), **image signing** (Sigstore cosign) |
| Deploy | Kubernetes **admission control** (Kyverno): only signed images from the bank's ECR, no privileged pods, resource limits required |
| Test | **DAST** against staging (OWASP ZAP), API fuzzing, MASVS checks for the apps |
| Run | GuardDuty runtime, Inspector continuous scanning |
| Periodic | **Annual independent penetration test** (Step 2) of web, mobile and APIs; red-team exercises; DR and incident drills |

---

## 10. Staff access

| Control | Detail |
| --- | --- |
| Workforce identity | **IAM Identity Center** federated with the bank's directory; **phishing-resistant MFA (FIDO2)** |
| No standing admin | Just-in-time elevation with approval and time limit; **break-glass** accounts monitored and alerted |
| Production data access | Only through audited tools (compliance console, back office), never direct DB queries; every access logged with who, system, IP, date, time and data viewed (Step 2, Step 10) |
| Separation of duties | Developers can't deploy to production without the pipeline; Security owns the log archive and audit keys |

---

## 11. Mapping to the regulation (Step 2)

| Requirement | Controls | Steps |
| --- | --- | --- |
| Encryption of communications and confidential data | TLS 1.2+/1.3 everywhere, mTLS, KMS, field-level encryption, HSM | 8, 9, 12 |
| Strong authentication 2 of 3 factors (login, unregistered beneficiaries) | OIDC + MFA, device key + biometrics, step-up with dynamic linking | 6 |
| Transactions only from authorized devices | Device binding, DPoP, attestation | 5, 6 |
| Block after 3 failed attempts + notification | IdP lockout, WAF ATP, Notification | 6, 11 |
| Idle timeout, last-login display | BFF sessions, Customer Profile | 5, 6 |
| Real-time risk profiling | Risk Scoring, limits | 7, here |
| Anti-malware / anti-tampering on channels | RASP, attestation, WAF, Bot Control | 5, here |
| Notify every transaction (SMS + email) and every login | Notification service | 11 |
| Mask account numbers | Templates, UI, logs | 9, 11 |
| 12-month transaction history with IP; staff access logs | Audit trail | 10 |
| Masked data in non-production; environment isolation | Separate accounts, synthetic data, SCPs | 3, 9 |
| Synchronized clocks | Amazon Time Sync on all hosts | 10 |
| Annual penetration test | DevSecOps periodic controls | here |
| Cloud: ISO 27001/27017/27018, Tier III, annual audit, contract clauses | AWS Artifact evidence, DPA | 3 |
| Incident reporting to the SB (5 / 10 days) | SIEM, runbooks, audit, traces | here, 14 |
| LOPDP breach notification (2 / 5 days) | Detection, data classification, contracts | here |
| Biometric data rules (DPIA, consent, no templates kept) | Onboarding design | 7 |
| AML monitoring | AML Monitoring service, events | 4, 8 |

---

## 12. ADR-017: Security tooling

**Status:** Proposed

**Decision:** use **AWS-native security services** (WAF, Shield Advanced, GuardDuty, Security Hub, Inspector, Macie, KMS, CloudHSM, Network Firewall, Security Lake) for the cloud platform, and forward their findings to the **bank's existing SIEM and SOC** through Security Lake (OCSF format).

### Justifications

1. **Native coverage with no agents to run** for most controls: these services see CloudTrail, VPC flow logs, EKS audit logs and S3 access directly, and evolve with the platform.
2. **One SOC for the whole bank.** The bank already monitors its on-premises systems; sending cloud findings to the same SIEM lets analysts correlate an attack across channels, Core and cloud, and supports the SB incident deadlines.
3. **Compliance evidence.** Security Hub standards (CIS, AWS Foundational Best Practices) produce continuous evidence for the annual audits required by the SB for cloud services.

**Trade-off:** AWS-specific. Portability matters less here than at the application layer (ADR-002): security tooling is tied to the platform it protects anyway.

---

## 13. Sources

- [NIST SP 800-207: Zero Trust Architecture](https://csrc.nist.gov/pubs/sp/800/207/final)
- [OWASP API Security Top 10 (2023)](https://owasp.org/API-Security/editions/2023/en/0x11-t10/)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [AWS WAF: Bot Control and Account Takeover Prevention](https://docs.aws.amazon.com/waf/latest/developerguide/waf-managed-protections.html)
- [AWS Shield Advanced](https://docs.aws.amazon.com/waf/latest/developerguide/shield-chapter.html)
- [AWS Security Reference Architecture](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/welcome.html)
- [AWS Well-Architected: Financial Services Industry Lens](https://docs.aws.amazon.com/wellarchitected/latest/financial-services-industry-lens/welcome.html)
- [Amazon GuardDuty EKS runtime monitoring](https://docs.aws.amazon.com/guardduty/latest/ug/runtime-monitoring.html)
- [Amazon Security Lake](https://docs.aws.amazon.com/security-lake/latest/userguide/what-is-security-lake.html)
- [AWS CloudHSM](https://docs.aws.amazon.com/cloudhsm/latest/userguide/introduction.html)
- [Sigstore cosign](https://docs.sigstore.dev/) and [Kyverno](https://kyverno.io/)

---

## Step 12 checklist

- [x] Principles (Zero Trust, defence in depth, least privilege)
- [x] Layered security view
- [x] Perimeter, network, keys, application, fraud, detection, DevSecOps and staff access controls
- [x] OWASP API Top 10 mapping
- [x] Regulation mapping (Step 2 → controls → steps)
- [x] Security tooling decision (ADR-017)
- [x] Layered view: kept as the layer/controls table in PDF §12, with the three security boundaries described in §4.4; not redrawn in draw.io, so every diagram still comes from the single Structurizr model (ADR-001)
