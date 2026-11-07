# Architecture Solution Roadmap: BP Internet Banking

A step-by-step guide to research and build the proposal yourself. It doesn't give the answers. Each step lists:

- **Investigate:** the questions to answer and the concepts to study.
- **Compare:** candidate options to evaluate. They're starting points, not recommendations.
- **Output:** what you should have when the step is done. It goes into the PDF.

> **Rule for every decision:** write it as an ADR (Architecture Decision Record) with the context, the options considered, the decision, **at least 2 theoretical justifications**, and the trade-offs. The grading rewards this explicitly.

---

## Step 0: Frame the problem

**Investigate**

- Re-read the statement and list every **functional requirement**: history, own-account and interbank transfers, payments, notifications, onboarding, login, audit, frequent-client data.
- List the **quality attributes**: HA, fault tolerance, DR, security, monitoring, operational excellence, auto-healing, low latency, cost, decoupling.
- Decide on **explicit assumptions**: number of users, concurrent sessions, transactions per second, country or jurisdiction, and target RTO/RPO.
- Read: *Software Architecture in Practice* (quality attribute scenarios) and the ISO/IEC 25010 quality model.

**Output:** a requirements table, a quality-attribute scenario table, and an assumptions list. Map each one to a grading criterion.

---

## Step 1: Learn the notation and pick tooling

**Investigate**

- The C4 model at c4model.com: the levels, the notation rules, and what belongs in context, containers and components.
- How to show external systems, actors, protocols and cloud services in C4.

**Compare:** draw.io (it has C4 shapes), Structurizr DSL, IcePanel, and PlantUML with C4-PlantUML.

**Output:** the chosen tool and a diagram style guide (colours, legend, labels like `[HTTPS/JSON]`).

---

## Step 2: Regulatory and compliance baseline

**Investigate**

- **Confirm the jurisdiction.** If it's Ecuador, look up the Ley Orgánica de Protección de Datos Personales (LOPDP), the Código Orgánico Monetario y Financiero, and the Superintendencia de Bancos and Junta de Política y Regulación Financiera rules on information security, cloud outsourcing and data residency.
- International standards: PCI DSS (if cards are involved), ISO/IEC 27001/27002, NIST CSF, SOC 2, and GDPR as a reference.
- Data retention rules for transactions and audit logs, and the rules on customer notifications.
- Whether financial data can be hosted in a foreign cloud region.

**Output:** a regulatory table (norm → what it requires → how the architecture complies).

> Do this early. Data residency and retention can change the cloud region and the audit design.

---

## Step 3: Choose the cloud provider and region strategy

**Investigate**

- Region availability **close to your users**, for latency. Check the regions in or near the country and the edge/CDN locations.
- The managed services each provider offers for what you need: gateway, Kubernetes, messaging, cache, identity, and HSM/KMS.
- Compliance certifications and financial-services reference architectures for each provider.
- Read the AWS Well-Architected Framework (Financial Services Industry Lens) and the Azure Well-Architected Framework.

**Compare:** AWS vs Azure, and single-region multi-AZ vs multi-region.

**Output:** an ADR for the provider choice, plus the regions and zones.

---

## Step 4: Domain decomposition (microservices)

**Investigate**

- Domain-Driven Design: bounded contexts, context mapping, and the Anti-Corruption Layer (to wrap the Core).
- Which services to add beyond the 3 given (basic data, movements, transfers). Possible additions: customer profile aggregation, payments, notifications, audit, beneficiaries, limits and fraud checks, onboarding.
- Microservices vs a modular monolith, and when each one fits.

**Output:** a service catalogue (responsibility, owned data, sync/async interfaces).

---

## Step 5: Front-end and mobile architecture

**Investigate**

- **SPA:** the framework, the hosting (static site + CDN + WAF), and how tokens are handled securely in a browser.
- **Backend for Frontend (BFF)** pattern: one BFF per channel, or a shared gateway?
- **Mobile:** you must compare 2 multiplatform frameworks. Look at performance, biometric API support, security plugins (secure storage, root/jailbreak detection, certificate pinning), team skills, ecosystem maturity, and banking-industry adoption.
- Mobile security standards: OWASP MASVS/MASTG, and RASP solutions.
- Micro-frontends: is the extra complexity worth it here?

**Compare**

- SPA: React vs Angular vs Vue.
- Mobile: Flutter vs React Native (optionally Kotlin Multiplatform or .NET MAUI).

**Output:** two ADRs (SPA framework, mobile framework) and the front-end container design.

---

## Step 6: Authentication and authorization (OAuth 2.0 / OIDC)

**Investigate**

- OAuth 2.0 grant types and which ones are now **deprecated** (Implicit, Resource Owner Password).
- Authorization Code + **PKCE**. Read RFC 7636, RFC 8252 (OAuth for native apps), RFC 9700 (OAuth 2.0 Security Best Current Practice), and the "OAuth 2.0 for Browser-Based Apps" draft.
- OpenID Connect, ID token vs access token, refresh token rotation, token lifetimes, and where tokens are stored (BFF / token-handler pattern for the SPA).
- **FAPI 2.0** (Financial-grade API) profile: PAR, DPoP or mTLS-bound tokens.
- **Step-up authentication** and MFA for sensitive operations like transfers. Look at transaction signing and dynamic linking (PSD2 SCA as a reference).
- Biometrics after onboarding: FIDO2/WebAuthn/passkeys, device binding, and native biometrics (Face ID / fingerprint) unlocking a key in the secure enclave.
- How the API Gateway validates tokens (JWT validation, scopes, introspection).

**Compare** (the identity product is "provided", but name what it could be): Keycloak, Okta/Auth0, Microsoft Entra External ID, Amazon Cognito, Ping/ForgeRock.

**Output:** an authentication flow sequence diagram for SPA, mobile login, biometric login and step-up, plus an ADR for the recommended flow.

---

## Step 7: Onboarding with facial recognition

**Investigate**

- The eKYC flow: document capture and verification, selfie, **liveness detection** (ISO/IEC 30107-3 presentation attack detection), and face matching against the document or the government civil registry.
- Whether a national identity-registry API exists to validate citizens.
- How onboarding hands off to the identity provider: create the user, set credentials, enrol the device and biometrics.
- Privacy: biometric data is sensitive personal data under data-protection law. Where is it stored, and for how long?

**Compare:** FaceTec, Jumio, Onfido, Veridas, iProov, AWS Rekognition (Face Liveness), Azure AI Face (limited access).

**Output:** an onboarding sequence diagram and an ADR for the KYC/biometric vendor.

---

## Step 8: Integration layer and communication patterns

**Investigate**

- The API Gateway's responsibilities: routing, authN/authZ, rate limiting, throttling, caching, versioning.
- Sync vs async communication, REST vs gRPC, event-driven architecture.
- Patterns: API Composition/Aggregator, **Saga** (for transfers), **Transactional Outbox**, **Circuit Breaker**, Retry with backoff, Bulkhead, Timeout, **Idempotency keys**, Anti-Corruption Layer, Strangler Fig.
- **Interbank transfers:** how the local interbank payment network works (in Ecuador, the Central Bank's payment system), message standards (ISO 20022), and settlement timing.
- Service mesh (mTLS, traffic policies): needed or not?

**Compare**

- Gateway: AWS API Gateway, Azure API Management, Kong, Apigee.
- Messaging: Kafka (MSK / Confluent), SQS/SNS/EventBridge, Azure Service Bus / Event Hubs.
- Compute: Kubernetes (EKS/AKS), managed containers (ECS Fargate / Azure Container Apps), serverless (Lambda / Functions).

**Output:** ADRs for the gateway, messaging and compute, plus a transfer sequence diagram showing the Saga and failure handling.

---

## Step 9: Data access architecture and frequent-client persistence

**Investigate**

- Integrating with the Core: direct calls vs replication, CDC (Change Data Capture), and read models.
- **CQRS** for movement history (a read-optimized store).
- Caching patterns: **Cache-Aside**, Read-Through, Write-Through, TTL and invalidation strategies, and what is safe to cache in banking (balances vs profile data).
- Database-per-service, polyglot persistence, and SQL vs NoSQL per service.
- Encryption at rest and in transit, tokenization, and masking of personal data.

**Compare:** Redis (ElastiCache / Azure Cache for Redis), DynamoDB / Cosmos DB, PostgreSQL (RDS/Aurora / Azure Database), Debezium for CDC.

**Output:** a data architecture view and an ADR for the frequent-client persistence pattern.

---

## Step 10: Audit solution

**Investigate**

- Patterns: **Event Sourcing**, Observer / Publish-Subscribe, Outbox (no audit event lost), Decorator / Interceptor / AOP to capture actions.
- What an audit record needs: who, what, when, where (IP/device), result, correlation ID.
- Immutability and tamper evidence: WORM storage, hash chaining, separation of duties.
- Retention periods required by regulation, and hot vs cold storage tiers.
- How audit differs from application logging and from SIEM.

**Compare:** S3 Object Lock / Azure immutable Blob storage, DynamoDB / Cosmos DB, OpenSearch for querying, and stream ingestion (Kafka / Kinesis / Event Hubs). Check the **service lifecycle status** of each, since some ledger-style services have been retired.

**Output:** an audit component design and an ADR.

---

## Step 11: Notifications (at least 2 channels or providers)

**Investigate**

- Channels: push, SMS, email, in-app. Which ones does regulation require?
- Event-driven notifications: transaction event → notification service → providers.
- Provider **failover** (primary/secondary), templates, user preferences, delivery tracking, retries and dead-letter queues.

**Compare:** Firebase Cloud Messaging / APNs, Amazon SNS / SES, Twilio, SendGrid, Azure Communication Services / Notification Hubs, and local SMS aggregators. Again, check each service's end-of-support status.

**Output:** a notification component design and an ADR.

---

## Step 12: Security architecture (cross-cutting)

**Investigate**

- OWASP Top 10, OWASP API Security Top 10, Zero Trust principles, defence in depth.
- Perimeter: WAF, DDoS protection, bot protection.
- Secrets and keys: KMS / Key Vault, HSM, key rotation.
- Network: VPC/VNet segmentation, private endpoints, mTLS between services.
- Fraud detection and transaction limits, DevSecOps (SAST/DAST/SCA), and penetration testing.

**Output:** a security view (layers and controls) mapped to the regulations from Step 2.

---

## Step 13: HA, fault tolerance, DR and auto-healing

**Investigate**

- Defining RTO and RPO for each service tier.
- DR strategies: Backup & Restore, Pilot Light, Warm Standby, Multi-site Active/Active. Compare their cost against RTO/RPO.
- Multi-AZ deployment, database replication and failover, global DNS failover.
- Auto-healing: Kubernetes liveness/readiness probes, auto-scaling groups, health checks, self-healing deployments.
- Chaos engineering (AWS FIS / Azure Chaos Studio).

**Output:** an infrastructure / deployment diagram (multi-AZ, DR region) and an ADR for the DR strategy.

---

## Step 14: Monitoring and observability

**Investigate**

- The three pillars (logs, metrics, traces), **OpenTelemetry**, and correlation IDs across services.
- SLIs, SLOs and error budgets, plus alerting and on-call.
- Business monitoring: transfers per minute, failure rates, onboarding conversion.
- Security monitoring with a SIEM.

**Compare:** CloudWatch + X-Ray / Azure Monitor + Application Insights vs Datadog, Dynatrace, Grafana stack, Elastic. Microsoft Sentinel / Splunk as the SIEM.

**Output:** an observability component design and an ADR.

---

## Step 15: Operational excellence

**Investigate**

- Infrastructure as Code: Terraform vs CloudFormation/CDK vs Bicep.
- CI/CD and GitOps, plus deployment strategies (blue/green, canary, feature flags).
- Environments (dev / QA / staging / prod), runbooks, incident management.

**Output:** a short DevOps section with the pipeline diagram.

---

## Step 16: Cost management

**Investigate**

- The provider's pricing calculator: estimate the main components for your assumed load.
- Reserved instances / savings plans vs on-demand vs serverless; auto-scaling to cut idle cost.
- FinOps practices: tagging, budgets, alerts, and right-sizing.
- The cost impact of the DR strategy you chose.

**Output:** a rough monthly cost estimate table and cost-optimization decisions.

---

## Step 17: Draw the C4 diagrams

1. **Context:** BP Internet Banking in the centre. Actors: customer, new customer. External systems: Core, complementary customer system, OAuth/identity, biometric/KYC, notification providers, interbank network. Plain language.
2. **Containers:** SPA, mobile app, CDN/WAF, API Gateway, BFFs, each microservice, databases, cache, message broker, audit store, identity provider. Label the protocols.
3. **Components:** go inside the key containers (for example, the transfer service and the integration layer). Show patterns (Saga, Outbox, Circuit Breaker, ACL), security (JWT validation, mTLS) and cloud services.
4. **Supporting diagrams:** infrastructure/deployment, authentication sequence, onboarding sequence, transfer sequence.

Check that every element in a diagram is explained somewhere in the text.

---

## Step 18: Assemble and review the PDF

Suggested structure:

1. Executive summary
2. Requirements and assumptions
3. Regulatory considerations
4. C4 diagrams with explanations
5. Detailed designs: front-end, authentication, onboarding, integration, data, audit, notifications
6. Non-functional design: security, HA/DR, monitoring, operations
7. Cost estimate
8. ADRs (decision log with alternatives and 2+ justifications each)
9. Risks and future evolution

**Final review:** go through the checklist in [assessment-statement.md](assessment-statement.md#6-checklist-de-cobertura) and the 15 grading criteria. Then upload the PDF to CoderPad and to a public GitHub repository, and put the repository URL in the comment.

---

## Suggested time split (72 h window)

| Block                                         | Steps  | Share |
| --------------------------------------------- | ------ | ----- |
| Framing, compliance, cloud                    | 0–3   | ~15%  |
| Domain, front-end, authentication, onboarding | 4–7   | ~25%  |
| Integration, data, audit, notifications       | 8–11  | ~25%  |
| Non-functionals and cost                      | 12–16 | ~15%  |
| Diagrams and PDF                              | 17–18 | ~20%  |
