# Step 15: Operational excellence

**Inputs:** Step 2 (isolated dev / test / prod, masked data outside production, annual pentest, change control), Step 3 (Control Tower landing zone, accounts per environment), Step 8 (EKS, Kong config in Git), Step 12 (DevSecOps controls, signed images, admission control), Step 13 (progressive delivery, GitOps, chaos and DR drills), Step 14 (SLOs, error budgets, incident process).

---

## 1. Principles

1. **Everything as code:** infrastructure, Kubernetes manifests, gateway routes, dashboards, alerts and runbooks live in Git.
2. **No manual changes in production:** changes reach production only through the pipeline; humans have break-glass access only (Step 12).
3. **Small, frequent, reversible releases:** canary deployments with automatic rollback and feature flags make each change low-risk.
4. **You build it, you run it:** each team owns its services in production, supported by a platform team and SRE practices (SLOs, error budgets).
5. **Learn from failure:** blameless post-incident reviews, game days and DR drills.

---

## 2. ADR-020: Infrastructure as Code

**Status:** Proposed

| Criterion | Terraform / OpenTofu | AWS CDK | CloudFormation | Bicep |
| --- | --- | --- | --- | --- |
| Covers AWS **and** non-AWS resources (Kong, PagerDuty, Grafana, GitHub, Cloudflare/DNS) | Yes, thousands of providers | AWS only (plus some via custom resources) | AWS only | Azure only, not applicable |
| State and drift detection | Plan / state, drift visible | Through CloudFormation | Drift detection | — |
| Skills in the market | Very common | Developers who know TypeScript/Java | Common on AWS | — |
| Portability (ADR-002 lock-in mitigation) | High | Low | Low | — |
| Licence | Terraform: BUSL since 2023; **OpenTofu**: open source (MPL), compatible fork | Apache 2.0 | AWS service | MIT |

**Decision:** **Terraform** (or **OpenTofu**, its open-source fork, if the bank prefers an open-source licence), with remote state in S3 (versioned, encrypted, locked), modules per layer, and policy checks before every apply.

### Justifications

1. **One tool for the whole platform.** Besides AWS, the platform needs Kong, Grafana, PagerDuty, GitHub and DNS configured as code; Terraform has providers for all of them.
2. **Plan before apply.** `terraform plan` shows exactly what will change, which becomes the evidence for change approval (section 6) and is checked by policy tools (Checkov / OPA) for security rules.
3. **Portability and skills.** HCL is widely known, and the same skills apply if part of the platform moves to another cloud or on-premises.

### Repository layout

| Repository | Contents | Deployed by |
| --- | --- | --- |
| `platform-infra` | Terraform modules: landing zone add-ons, VPCs, EKS, Aurora, DynamoDB, MSK, ElastiCache, KMS, WAF, Direct Connect | Terraform pipeline |
| `gitops-environments` | Kubernetes manifests / Helm values per environment and region, Kong declarative config, Istio policies | **Argo CD** |
| One repo per service (e.g. `transfer-service`) | Code, Dockerfile, OpenAPI, Kafka schemas, Helm chart, tests | Service CI pipeline |
| `shared-libraries` | Audit interceptor, OTel config, resilience defaults, security filters | Versioned packages |
| `mobile-app`, `web-app` | Flutter and Angular apps | App pipelines |
| `runbooks`, `observability` | Runbooks, dashboards, alert rules as code | Pipeline |

---

## 3. Environments

| Environment | Account | Purpose | Data |
| --- | --- | --- | --- |
| **Dev** | dev | Developer integration; **ephemeral preview environments** per pull request (namespace) | Synthetic |
| **QA** | dev / test | Functional and contract tests; vendor sandboxes (eKYC, SMS test numbers, payment network test environment) | Synthetic |
| **Staging** | staging | **Production-like** (same Terraform modules, smaller); performance tests at 3× peak, chaos experiments, DR rehearsal, pentest target | Synthetic / **masked** (never real) |
| **Production** | prod (us-east-1 + us-east-2) | Customers | Real |

Promotion is the **same image digest** from QA → staging → production; only configuration changes per environment. This satisfies the SB rule on isolated environments and masked data outside production (Step 2).

---

## 4. CI/CD pipeline

```text
 Developer ─► Pull request
               │
               ▼
 ┌──────────────────── CI (GitHub Actions) ──────────────────────────────────────────┐
 │ build ─► unit tests ─► SAST + secret scan ─► SCA + SBOM ─► contract tests          │
 │ (OpenAPI, Kafka schemas: backward compatible?) ─► container build (distroless)     │
 │ ─► image scan ─► sign image (cosign) ─► push to ECR                                │
 │ Terraform changes: fmt/validate ─► Checkov/OPA ─► plan attached to the PR           │
 └───────────────────────────────────────────────────────────────────────────────────┘
               │ merge to main (2 reviewers, all checks green)
               ▼
 ┌──────────────────── CD (GitOps) ─────────────────────────────────────────────────┐
 │ update image digest in gitops-environments (automated PR)                          │
 │ Argo CD syncs ─► Dev ─► QA (integration + E2E tests) ─► Staging (performance,      │
 │ DAST, smoke) ─► approval gate (automated evidence) ─► Production                   │
 │ Production: Argo Rollouts canary 5% ─► 25% ─► 50% ─► 100%,                          │
 │ analysis on SLO metrics (errors, p95) at each step ─► automatic rollback on breach  │
 │ us-east-1 first, then us-east-2 (standby kept on the same version)                  │
 │ Kyverno admission: only signed images from the bank's ECR                           │
 └───────────────────────────────────────────────────────────────────────────────────┘
               │
               ▼
 Observability: deployment markers in Grafana; error budget checked before the next release
```

### Mobile and web pipelines

| App | Pipeline |
| --- | --- |
| **Flutter** | GitHub Actions (macOS runners for iOS) + **Fastlane**: tests, obfuscated build, signing, MASVS checks, RASP SDK integration check → internal testing → **staged rollout** (Play staged rollout, App Store phased release). **Minimum version** and **feature flags** served by the Mobile BFF (Step 5), because app releases take days to reach everyone. |
| **Angular SPA** | Build, tests, SCA, CSP check → upload to versioned S3 prefix → CloudFront invalidation; rollback = point to the previous prefix. |

---

## 5. Deployment strategies

| Change type | Strategy |
| --- | --- |
| Service code | **Canary** with automated analysis and rollback (Argo Rollouts) |
| New feature | Deployed **dark** behind a **feature flag** (OpenFeature API; AWS AppConfig as flag store), enabled gradually per customer segment; **kill switch** for each risky feature |
| Database schema | **Expand / contract**: add new columns first, deploy code that writes both, migrate, then remove old columns in a later release; migrations run by the pipeline (Flyway / Liquibase) |
| Event / API contracts | Backward-compatible changes only within a version; breaking changes = new version (`/v2/`, `*.v2` topic) with both running in parallel |
| Gateway routes | Kong declarative config through Git; canary routes possible per header / percentage |
| Infrastructure | Terraform plan reviewed and approved; applied to staging first; blue/green for EKS cluster upgrades (new node pools, then drain) |
| Mobile | Staged rollout + server-side flags + forced update for security fixes |

**Release calendar:** freeze windows around **payday and month-end** for non-urgent changes; security fixes always allowed.

---

## 6. Change management in a regulated bank

- Bank change management (CAB) is kept, but **standard changes** are **pre-approved** when the pipeline proves the controls: tests passed, scans clean, plan reviewed, canary analysis active, rollback automatic.
- The **evidence** (PR, reviewers, scan results, Terraform plan, deployment record, canary result) is stored automatically, so auditors and the SB get traceability without manual paperwork.
- High-risk changes (Core Adapter postings, interbank messages, authentication) need an extra reviewer from the owning team and Security.

---

## 7. Runbooks, incidents and readiness

| Practice | Detail |
| --- | --- |
| **Runbooks** | One per alert and per known failure (Core down, SMS provider down, regional failover, CDC lag, Kafka DLQ growth); stored in Git; tested in game days |
| **Incident management** | Severity matrix, incident commander, communication templates, customer status page; **SB report ≤ 5 days, root cause ≤ 10 days**; **SPDP ≤ 5 days** for personal-data breaches (Step 12) |
| **Post-incident review** | Blameless, within 5 working days, actions tracked to closure |
| **Operational readiness review** | Before a service goes live: SLOs defined, dashboards and alerts, runbooks, load test passed, DR tested, security review, on-call ready |
| **Game days and DR drills** | Step 13: monthly chaos in staging, quarterly in production, full regional failover twice a year |
| **Delivery metrics (DORA)** | Deployment frequency, lead time for changes, change failure rate, time to restore. Reviewed monthly with SLOs |

---

## 8. Team organisation

| Team | Owns |
| --- | --- |
| **Stream-aligned teams** (one per group of bounded contexts) | e.g. Payments (Transfer, Interbank Connector, Beneficiary & Limits), Accounts & Movements, Identity & Devices, Onboarding, Channels (BFFs, web, mobile) |
| **Platform team** | Landing zone, EKS, Kong, Kafka, observability stack, pipelines, golden paths (service templates) |
| **Security (enabling)** | DevSecOps tooling, threat modelling, reviews of high-risk changes, SIEM |
| **SRE** | SLO framework, incident process, chaos and DR drills |

A **service template** (golden path) gives every new service the shared libraries, pipeline, Helm chart, dashboards and alerts on day one, which keeps 14 services consistent (QAS-15: new services added without reinventing the platform).

---

## 9. Sources

- [OpenTofu](https://opentofu.org/) and [HashiCorp licence change (BUSL, 2023)](https://www.hashicorp.com/blog/hashicorp-adopts-business-source-license)
- [Argo CD](https://argo-cd.readthedocs.io/) and [Argo Rollouts](https://argoproj.github.io/rollouts/)
- [OpenFeature](https://openfeature.dev/) and [AWS AppConfig feature flags](https://docs.aws.amazon.com/appconfig/latest/userguide/what-is-appconfig.html)
- [Fastlane](https://docs.fastlane.tools/)
- [DORA metrics](https://dora.dev/guides/dora-metrics-four-keys/)
- [AWS Well-Architected: Operational Excellence Pillar](https://docs.aws.amazon.com/wellarchitected/latest/operational-excellence-pillar/welcome.html)
- [Team Topologies](https://teamtopologies.com/key-concepts)

---

## Step 15 checklist

- [x] IaC tool chosen (ADR-020: Terraform / OpenTofu) and repository layout
- [x] Environments and data rules
- [x] CI/CD pipeline with security gates and GitOps (diagram)
- [x] Deployment strategies (canary, flags, expand/contract, staged mobile rollout)
- [x] Change management with automated evidence
- [x] Runbooks, incidents, readiness reviews, DORA metrics
- [x] Team organisation and golden path
