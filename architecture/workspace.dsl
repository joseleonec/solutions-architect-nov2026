/*
 * BP Internet Banking: C4 model (Structurizr DSL)
 *
 * Run locally (from the repo root):
 *   Git Bash:   MSYS_NO_PATHCONV=1 docker run -it --rm -p 8080:8080 -v "$(pwd -W)/architecture:/usr/local/structurizr" structurizr/structurizr local
 *   PowerShell: docker run -it --rm -p 8080:8080 -v "${PWD}/architecture:/usr/local/structurizr" structurizr/structurizr local
 * Then open http://localhost:8080
 *
 * Validate:
 *   MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W)/architecture:/usr/local/structurizr" structurizr/structurizr validate -workspace /usr/local/structurizr/workspace.dsl
 *
 * Decisions behind each element: roadmap-steps/04..16 (ADR-001..ADR-021).
 */
workspace "BP Internet Banking" "Online and mobile banking platform for Banco Pichincha (BP)." {

    !identifiers hierarchical

    model {
        // =====================================================================
        // People
        // =====================================================================
        customer = person "Customer" "Retail banking client. Checks balances and movements, makes transfers and payments." "Customer"
        prospect = person "New customer" "Person opening an account through mobile onboarding with facial recognition." "Customer"
        compliance = person "Operations & Compliance Staff" "BP staff: reviews doubtful onboarding cases (four-eyes), resolves manual transfer cases, investigates the audit trail for the SB, UAFE and customer claims." "Staff"

        // =====================================================================
        // The system being designed
        // =====================================================================
        bp = softwareSystem "BP Internet Banking" "Lets customers see their movements, make own-account and interbank transfers and payments, and open accounts from the mobile app." "InScope" {

            // ---------- Channels ----------
            spa = container "Web App (SPA)" "Customer web banking UI. Holds no tokens: talks only to its BFF with a session cookie." "Angular / TypeScript (S3 + CloudFront)" "WebApp"
            mobile = container "Mobile App" "Mobile banking, onboarding with facial recognition, biometric login, device binding. RASP, attestation, certificate pinning." "Flutter (iOS / Android)" "MobileApp"
            backoffice = container "Back-office Portal" "Internal web app for staff: manual onboarding review, manual transfer cases, audit queries. Staff SSO with FIDO2 MFA, role-based access." "Angular / TypeScript (internal)" "WebApp"

            // ---------- Edge and integration layer ----------
            edge = container "Edge (CDN + WAF)" "TLS termination, WAF (OWASP rules, bot control, account takeover prevention), DDoS protection, serves the SPA." "Amazon CloudFront + AWS WAF + Shield Advanced" "Infrastructure"

            gateway = container "API Gateway" "Single entry point: validates JWT + DPoP, scopes and acr, rate limits per customer/device, routes by transaction type, logs every call." "Kong Gateway on EKS" "Gateway" {
                rate = component "Rate Limiter & Load Shedder" "Limits per customer, device and IP; sheds low-priority traffic under overload." "Kong plugin"
                jwt = component "OIDC / JWT Validator" "Validates signature (cached JWKS), iss, aud, exp and scopes." "Kong plugin"
                dpop = component "DPoP Validator" "Checks the DPoP proof (htm, htu, jti replay, cnf.jkt) so stolen tokens can't be replayed." "Kong custom plugin"
                acr = component "Route Policy (scope + acr)" "Enforces the minimum authentication level per route (acr:2 login, acr:3 step-up)." "Kong plugin"
                revocation = component "Revocation Check" "Rejects tokens of blocked devices or sessions (money-moving routes)." "Kong plugin"
                router = component "Router" "Routes by transaction type: /accounts, /movements, /transfers, /beneficiaries, /profile, /devices, /onboarding." "Kong routes (declarative, GitOps)"
                accessLog = component "Access Logger" "Publishes one access record per call for audit." "Kong kafka-log plugin"
            }

            webBff = container "Web BFF" "Token handler: runs the OAuth code flow as a confidential client, keeps tokens server-side, aggregates calls for web screens." "Java 21 / Spring Boot"
            mobileBff = container "Mobile BFF" "Screen-shaped APIs for the app, device context, minimum app version, feature flags." "Java 21 / Spring Boot"

            // ---------- Domain services ----------
            device = container "Device Service" "Device registration and binding, device trust status, device blocking." "Java 21 / Spring Boot"
            onboarding = container "Onboarding Service" "Orchestrates the onboarding Saga: eKYC result, Registro Civil, AML screening, account opening, IdP user." "Java 21 / Spring Boot" {
                group "API layer: identity, attestation, webhook authentication" {
                    onbApi = component "Onboarding API" "Start case, submit data, get status. Returns only safe status messages to the app." "Spring Web"
                    attestation = component "Device Attestation Verifier" "Verifies Play Integrity / App Attest server-side; rejects emulators and tampered apps before any capture." "Java"
                    webhook = component "Vendor Webhook Endpoint" "Receives the verification result: HMAC signature, timestamp and replay protection. Never trusts the app." "Spring Web"
                    reviewApi = component "Manual Review API" "Staff role only; four-eyes rule; lists queued cases and records the reviewer's decision." "Spring Web"
                }
                group "Business layer: state machine and decisions" {
                    orchestrator = component "Onboarding Orchestrator" "Saga / state machine: STARTED > CAPTURED > VERIFIED > SCREENED > APPROVED | UNDER_REVIEW | REJECTED > ACTIVE; records consent." "Java"
                    decisionEngine = component "Decision Engine" "Combines vendor scores, registry match and screening: approve, review or reject. Rejections always reviewed by a person." "Rules"
                }
                group "Integration and data layer: adapters, provisioning, repository" {
                    vendorAdapter = component "eKYC Vendor Adapter" "Anti-corruption layer: creates verification sessions, polls results if a webhook is lost; vendor is replaceable." "Java"
                    registryAdapter = component "Registro Civil Adapter" "Validates ID data, photo and fingerprint code (SNIC)." "Java"
                    screeningClient = component "Screening Client" "PEP, sanctions, UAFE lists and duplicate-identity check via AML Monitoring." "Resilience4j"
                    accountClient = component "Account Opening Client" "Creates customer and account through the Core Adapter, idempotent on case ID." "Resilience4j"
                    idpClient = component "IdP Provisioning Client" "Creates the user with kyc_level=verified (OAuth client credentials, admin API)." "Java"
                    onbRepo = component "Case Repository & Outbox" "Case state and events in one transaction; relay publishes OnboardingCompleted / Rejected." "Spring Data JPA + Outbox"
                }
            }
            profile = container "Customer Profile Service" "Basic and detailed customer data, contact data, last login, preferences." "Java 21 / Spring Boot"

            accounts = container "Accounts Service" "Balances and dashboard for the customer. Frequent-client persistence: cache-aside, refresh-ahead, event-driven invalidation." "Java 21 / Spring Boot" {
                group "API layer" {
                    accApi = component "Accounts API" "Returns balances and the dashboard snapshot (with 'as of' time)." "Spring Web"
                }
                group "Business layer: frequent-client persistence" {
                    cacheAside = component "Balance & Dashboard Cache" "Cache-aside: cache, then read model, then Core. TTLs (balance 60 s, dashboard 5 min), request coalescing, jittered TTL." "Spring Data Redis"
                    precompute = component "Dashboard Precompute Worker" "Refresh-ahead: on LoginSucceeded or FrequentClientAdded, builds the dashboard snapshot before the first screen." "Spring Kafka"
                    invalidator = component "Cache Invalidator" "Evicts or updates balances and dashboards on movement and transfer events." "Spring Kafka"
                    classifier = component "Frequent Client Classifier" "Event-driven sliding-window activity score (logins, accesses); configurable rule behind a feature flag (default >= 4 logins in 30 days); publishes FrequentClientAdded / Removed." "Spring Kafka"
                }
                group "Integration layer" {
                    coreReader = component "Core Balance Reader" "Reads balances through the Core Adapter with bulkhead, rate limit and circuit breaker; stale-while-revalidate fallback." "Resilience4j"
                }
            }

            movements = container "Movements Service" "Movement history (CQRS read model, 13 months online); projector fed by Core CDC and transfer events." "Java 21 / Spring Boot"

            transfer = container "Transfer Service" "Own-account and interbank transfers and payments. Orchestrated Saga, idempotency, step-up check, outbox." "Java 21 / Spring Boot" {
                group "API layer: identity, authorization, step-up, idempotency" {
                    api = component "Transfer API" "POST /v1/transfers (202 Accepted + status URL), GET status. Validates request and object ownership (sub owns the account)." "Spring Web"
                    idempotency = component "Idempotency Filter" "Stores Idempotency-Key with its result; a retry returns the same result (0 duplicate debits)." "Spring filter"
                    stepUp = component "Step-up Checker" "Requires acr:3 for unregistered beneficiaries / high risk; checks authorization_details match the request (dynamic linking)." "Java"
                    opsApi = component "Operations Case API" "Staff role only: lists and resolves transfers that need manual action." "Spring Web"
                }
                group "Business layer: Saga, compensation, reconciliation" {
                    saga = component "Transfer Saga Orchestrator" "Persisted state machine RECEIVED > VALIDATED > DEBITED > SENT > COMPLETED, retries with backoff, status query on timeout." "Java"
                    compensation = component "Compensation Handler" "On final rejection or expiry: reverses the debit, publishes TransferFailed; unresolved cases go to manual operations." "Saga compensation"
                    reconciliation = component "Reconciliation Job" "Compares transfers with Core postings and interbank settlement reports; opens a case for every difference." "Scheduled job"
                    inbox = component "Interbank Events Consumer" "Consumes PaymentAccepted / Rejected / Irrevocable; ignores duplicates (inbox)." "Spring Kafka"
                }
                group "Integration and data layer: repository, outbox, clients" {
                    decisionClient = component "Limits & Risk Client" "Calls Beneficiary & Limits and Risk Scoring with 300 ms timeouts." "Resilience4j"
                    coreClient = component "Core Posting Client" "Debits, credits and reversals with idempotency key; 2 s timeout, circuit breaker, posting bulkhead." "Resilience4j"
                    repo = component "Transfer Repository" "Orders, saga state, idempotency keys, manual cases." "Spring Data JPA"
                    outbox = component "Outbox Writer & Relay" "Writes events in the same DB transaction as the state change; relay publishes them to Kafka." "Transactional Outbox"
                }
            }

            beneficiary = container "Beneficiary & Limits Service" "Registered beneficiaries, customer-set limits, cooling period for new beneficiaries." "Java 21 / Spring Boot"
            risk = container "Risk Scoring Service" "Real-time allow / step-up / reject for monetary operations (rules + ML score, device and RASP signals)." "Java 21 / Spring Boot"
            interbank = container "Interbank Connector" "Sends and receives ISO 20022 payments (pacs.008 / pacs.002), answers payment-key lookups (acmt), real-time and SPI routes." "Java 21 / Spring Boot"
            aml = container "AML Monitoring Service" "Asynchronous transaction monitoring and onboarding screening (PEP, sanctions, UAFE lists); cases for compliance." "Java 21 / Spring Boot"

            notification = container "Notification Service" "Sends regulatory notices by SMS and email simultaneously (+ push); provider failover; delivery tracking." "Java 21 / Spring Boot" {
                group "Event layer" {
                    notifConsumer = component "Event Consumer" "Consumes domain and security events; idempotent by event ID." "Spring Kafka"
                }
                group "Business layer: policy, recipients, templates" {
                    policy = component "Notification Policy" "Decides channels per event: regulatory = SMS + email in parallel; push as complement." "Java"
                    resolver = component "Recipient Resolver" "Gets contact data from Customer Profile (old and new contact on changes)." "Java"
                    renderer = component "Template Renderer" "Versioned Spanish templates, account masking, no links in SMS." "Java"
                    dispatcher = component "Priority Dispatcher" "Puts messages on priority lanes (OTP/security first, then transactions, then push)." "Spring Kafka"
                }
                group "Integration layer: provider adapters and tracking" {
                    smsSender = component "SMS Sender" "Primary local aggregator, failover to secondary provider; circuit breaker, health score." "Adapter + Strategy"
                    emailSender = component "Email Sender" "Amazon SES with second-region fallback." "Adapter"
                    pushSender = component "Push Sender" "FCM / APNs." "Adapter"
                    tracker = component "Delivery Tracker" "Stores sent / delivered / failed per message and provider; resends OTPs via the secondary after 45 s without receipt." "Java"
                }
            }

            audit = container "Audit Service" "Records every customer action and staff access into immutable, tamper-evident storage; compliance query API." "Java 21 / Spring Boot" {
                group "Ingestion layer" {
                    auditConsumer = component "Audit Event Consumer" "Consumes audit.* topics; idempotent by auditId." "Spring Kafka"
                    normalizer = component "Validator & Normalizer" "Checks the record schema, tokenizes personal data." "Java"
                    chainer = component "Hash Chainer & Digest Signer" "Hash chain per partition; signs a Merkle root every 5 min with a KMS key." "Java + AWS KMS"
                }
                group "Storage layer" {
                    archiveWriter = component "Archive Writer" "Writes Parquet files to the WORM archive." "Java"
                    indexWriter = component "Hot Index Writer" "Writes the last 90 days of searchable fields." "Java"
                }
                group "Query and integrity layer" {
                    queryApi = component "Audit Query API" "Search by customer, staff user, correlation ID or transaction; role-based, read-only; every query is itself audited." "Spring Web + Athena"
                    verifier = component "Integrity Verifier" "Daily job: recomputes chains and digests, alerts on mismatch." "Spring Batch"
                }
            }

            // ---------- Adapters (anti-corruption layers) ----------
            coreAdapter = container "Core Adapter" "Anti-corruption layer to the Core: balances, postings, reversals, customer creation. Separate pools for reads and postings; rate limit sized to Core capacity." "Java 21 / Spring Boot"
            customerInfoAdapter = container "Customer Info Adapter" "Anti-corruption layer to the complementary customer system (detailed data on demand)." "Java 21 / Spring Boot"
            cdc = container "Core CDC Connector" "Streams changes from the Core read replica's transaction log into Kafka." "Debezium on Kafka Connect (MSK Connect)"

            // ---------- Data and messaging ----------
            broker = container "Event Broker" "Domain events, commands, audit records, CDC events; retry and DLQ topics; replicated to the DR region." "Amazon MSK (Apache Kafka)" "Queue"
            cache = container "Cache" "Balances, profiles, dashboard snapshots, risk features, BFF sessions, rate-limit counters." "Amazon ElastiCache (Valkey)" "Cache"

            transferDb = container "Transfer DB" "Orders, saga state, idempotency keys, outbox." "Aurora PostgreSQL (Global Database)" "Database"
            beneficiaryDb = container "Beneficiary & Limits DB" "Beneficiaries, limits." "Aurora PostgreSQL (Global Database)" "Database"
            onboardingDb = container "Onboarding DB" "Cases, consent, evidence references (no raw biometrics)." "Aurora PostgreSQL (Global Database)" "Database"
            profileDb = container "Profile DB" "Cloud-owned profile data: preferences, last login, contact verification." "Aurora PostgreSQL (Global Database)" "Database"
            interbankDb = container "Interbank DB" "ISO 20022 message log, payment status, reconciliation." "Aurora PostgreSQL (Global Database)" "Database"
            deviceDb = container "Device DB" "Devices, public keys, trust status." "DynamoDB global table" "Database"
            movementsDb = container "Movements Read Model" "Movements by account and date (13 months)." "DynamoDB global table" "Database"
            notificationDb = container "Notification Log" "Delivery status per message and provider." "DynamoDB global table" "Database"
            auditIndex = container "Audit Hot Index" "Last 90 days of searchable audit fields." "DynamoDB (TTL)" "Database"
            auditArchive = container "Audit Archive (WORM)" "Immutable audit records (12 months online, up to 10 years), signed digests." "S3 Object Lock (compliance mode), log archive account" "Database"
        }

        // =====================================================================
        // BP internal systems (not in scope)
        // =====================================================================
        core = softwareSystem "Core Banking" "System of record: customers, accounts, balances and movements. On-premises." "Internal,Existing"
        customerInfo = softwareSystem "Complementary Customer System" "Detailed customer information. On-premises." "Internal,Existing"
        identity = softwareSystem "Identity Provider (OAuth 2.0 / OIDC)" "BP's existing OAuth 2.0 product, FAPI 2.0 profile: PAR, PKCE, DPoP, MFA, step-up." "Internal,Existing"

        // =====================================================================
        // External systems
        // =====================================================================
        biometrics = softwareSystem "eKYC / Biometric Provider" "Document verification, liveness (iBeta PAD Level 2) and face match." "External"
        registroCivil = softwareSystem "Registro Civil (DIGERCIC)" "National identity registry: demographic and biometric validation (SNIC)." "External"
        interbankNet = softwareSystem "Payment Network / BCE" "Real-time payments (RPI / SIP) and SPI; ISO 20022 messaging." "External"
        smsA = softwareSystem "SMS Provider A" "Local SMS aggregator with direct carrier connections (primary)." "External"
        smsB = softwareSystem "SMS Provider B" "AWS End User Messaging SMS (failover)." "External"
        email = softwareSystem "Email Provider" "Amazon SES (us-east-1, fallback us-east-2)." "External"
        push = softwareSystem "Push Services" "Firebase Cloud Messaging / Apple Push Notification service." "External"

        // =====================================================================
        // Context-level relationships (business language)
        // =====================================================================
        customer -> bp "Checks balances and movements, makes transfers and payments using" "HTTPS"
        prospect -> bp "Opens an account with facial recognition using" "HTTPS"
        customer -> identity "Logs in (password + in-app OTP; SMS OTP as fallback) through" "HTTPS, system browser"
        compliance -> bp "Reviews onboarding cases, resolves manual transfer cases and investigates the audit trail using" "HTTPS, staff SSO + FIDO2 MFA"
        bp -> identity "Authenticates users and gets tokens from" "OIDC / FAPI 2.0"
        bp -> core "Reads balances and posts transfers to" "REST / SOAP over Direct Connect"
        bp -> customerInfo "Reads detailed customer data from" "REST / SOAP over Direct Connect"
        bp -> biometrics "Verifies identity documents and liveness with" "HTTPS"
        bp -> registroCivil "Validates citizens' identity with" "HTTPS (SNIC)"
        bp -> interbankNet "Sends and receives interbank payments through" "ISO 20022 / mTLS"
        bp -> smsA "Sends SMS notices and OTPs through" "HTTPS / SMPP"
        bp -> smsB "Sends SMS on failover through" "HTTPS"
        bp -> email "Sends email notices through" "HTTPS"
        bp -> push "Sends push notifications through" "HTTPS"
        smsA -> customer "Sends SMS to"
        smsB -> customer "Sends SMS to"
        email -> customer "Sends email to"
        push -> customer "Sends push notifications to"

        // =====================================================================
        // Container-level relationships
        // =====================================================================
        // Channels
        customer -> bp.spa "Uses" "HTTPS"
        customer -> bp.mobile "Uses"
        prospect -> bp.mobile "Opens an account with"
        bp.spa -> bp.edge "Calls the Web BFF through" "HTTPS, HttpOnly session cookie" "Infra"
        bp.mobile -> bp.edge "Calls APIs through" "HTTPS, pinned TLS, DPoP-bound token" "Infra"
        bp.mobile -> identity "Obtains and refreshes tokens from" "OIDC: PAR + PKCE + DPoP (system browser)"
        bp.mobile -> biometrics "Captures cédula, selfie and liveness with" "Vendor SDK / HTTPS"
        push -> bp.mobile "Delivers push notifications to"

        // Edge and gateway
        bp.edge -> bp.gateway "Forwards API traffic to" "HTTPS (NLB)"
        bp.gateway -> bp.webBff "Routes web calls to" "HTTPS / mTLS"
        bp.gateway -> bp.mobileBff "Routes mobile calls to" "HTTPS / mTLS"
        bp.gateway -> identity "Fetches signing keys (JWKS) from" "HTTPS"
        bp.gateway -> bp.cache "Keeps rate-limit counters, DPoP replay cache and revocation list in" "TLS"
        bp.gateway -> bp.broker "Publishes access records to" "Kafka" "Async"

        // BFFs
        bp.webBff -> identity "Runs the OAuth code flow as a confidential client with" "OIDC: PAR, PKCE, private_key_jwt"
        bp.webBff -> bp.cache "Keeps encrypted sessions and tokens in" "TLS"
        bp.webBff -> bp.profile "Gets customer data from" "REST / mTLS"
        bp.webBff -> bp.accounts "Gets balances and dashboard from" "REST / mTLS"
        bp.webBff -> bp.movements "Queries movement history from" "REST / mTLS"
        bp.webBff -> bp.transfer "Submits transfers to" "REST / mTLS"
        bp.webBff -> bp.beneficiary "Manages beneficiaries and limits with" "REST / mTLS"
        bp.mobileBff -> bp.device "Checks device binding with" "REST / mTLS"
        bp.mobileBff -> bp.onboarding "Runs onboarding cases with" "REST / mTLS"
        bp.mobileBff -> bp.profile "Gets customer data from" "REST / mTLS"
        bp.mobileBff -> bp.accounts "Gets balances and dashboard from" "REST / mTLS"
        bp.mobileBff -> bp.movements "Queries movement history from" "REST / mTLS"
        bp.mobileBff -> bp.transfer "Submits transfers to" "REST / mTLS"
        bp.mobileBff -> bp.beneficiary "Manages beneficiaries and limits with" "REST / mTLS"

        // Transfers and payments
        bp.transfer -> bp.beneficiary "Checks beneficiary and limits with" "REST / mTLS"
        bp.transfer -> bp.risk "Requests a risk decision from" "REST / mTLS"
        bp.transfer -> bp.coreAdapter "Posts debits, credits and reversals through" "REST / mTLS"
        bp.transfer -> bp.transferDb "Reads and writes orders, saga state and outbox in" "SQL / TLS"
        bp.transfer -> bp.broker "Publishes transfer events and payment commands to; consumes payment events from" "Kafka" "Async"
        bp.beneficiary -> bp.beneficiaryDb "Reads and writes" "SQL / TLS"
        bp.beneficiary -> bp.broker "Publishes beneficiary events to" "Kafka" "Async"
        bp.risk -> bp.cache "Reads risk features from" "TLS"
        bp.risk -> bp.broker "Consumes device and security signals from" "Kafka" "Async"
        bp.interbank -> bp.broker "Consumes payment commands from; publishes payment events to" "Kafka" "Async"
        bp.interbank -> bp.interbankDb "Logs ISO 20022 messages and status in" "SQL / TLS"
        bp.interbank -> interbankNet "Sends pacs.008 and status queries, answers acmt lookups" "ISO 20022 / mTLS"
        interbankNet -> bp.interbank "Returns pacs.002 and delivers incoming pacs.008 to" "ISO 20022 / mTLS"
        bp.interbank -> bp.coreAdapter "Credits incoming payments through" "REST / mTLS"

        // Accounts, movements, profile (frequent-client persistence, CQRS)
        bp.accounts -> bp.cache "Reads and writes balances and dashboard snapshots in (cache-aside)" "TLS"
        bp.accounts -> bp.coreAdapter "Reads balances on cache miss through (rate-limited)" "REST / mTLS"
        bp.accounts -> bp.movements "Gets recent movements for the dashboard from" "REST / mTLS"
        bp.accounts -> bp.broker "Consumes login, movement and transfer events from" "Kafka" "Async"
        bp.movements -> bp.movementsDb "Queries and projects movements into" "HTTPS (DynamoDB API)"
        bp.movements -> bp.broker "Consumes Core CDC and transfer events from" "Kafka" "Async"
        bp.movements -> bp.coreAdapter "Requests history older than 13 months through" "REST / mTLS"
        bp.profile -> bp.profileDb "Reads and writes" "SQL / TLS"
        bp.profile -> bp.cache "Caches profiles in" "TLS"
        bp.profile -> bp.coreAdapter "Reads basic customer data through" "REST / mTLS"
        bp.profile -> bp.customerInfoAdapter "Requests detailed data on demand from" "REST / mTLS"
        bp.profile -> bp.broker "Publishes customer events to" "Kafka" "Async"
        bp.cdc -> core "Reads the transaction log of the Core read replica" "Log-based CDC over Direct Connect"
        bp.cdc -> bp.broker "Publishes Core change events to" "Kafka" "Async"
        bp.coreAdapter -> core "Calls" "REST / SOAP over Direct Connect"
        bp.customerInfoAdapter -> customerInfo "Calls" "REST / SOAP over Direct Connect"

        // Device and onboarding
        bp.device -> bp.deviceDb "Reads and writes devices and keys in" "HTTPS (DynamoDB API)"
        bp.device -> bp.broker "Publishes device events to" "Kafka" "Async"
        bp.onboarding -> bp.onboardingDb "Reads and writes cases and consent in" "SQL / TLS"
        bp.onboarding -> biometrics "Fetches verification results from (server-to-server)" "HTTPS"
        bp.onboarding -> registroCivil "Validates identity (demographic + biometric) with" "HTTPS (SNIC)"
        bp.onboarding -> bp.aml "Screens applicants (PEP, sanctions, UAFE lists) with" "REST / mTLS"
        bp.onboarding -> bp.coreAdapter "Creates customer and account through" "REST / mTLS"
        bp.onboarding -> identity "Creates the user in" "Admin API / SCIM"
        bp.onboarding -> bp.broker "Publishes onboarding events to" "Kafka" "Async"
        identity -> bp.broker "Publishes security events (login, lockout) to" "Kafka / webhook bridge" "Async"

        // AML
        bp.aml -> bp.broker "Consumes transfer, payment and onboarding events from" "Kafka" "Async"

        // Notification
        bp.notification -> bp.broker "Consumes events from; uses priority lanes in" "Kafka" "Async"
        bp.notification -> bp.profile "Gets contact data from" "REST / mTLS"
        bp.notification -> bp.notificationDb "Tracks delivery in" "HTTPS (DynamoDB API)"
        bp.notification -> smsA "Sends SMS through" "HTTPS / SMPP"
        bp.notification -> smsB "Sends SMS on failover through" "HTTPS"
        bp.notification -> email "Sends email through" "HTTPS"
        bp.notification -> push "Sends push through" "HTTPS (FCM v1 / APNs)"

        // Audit
        bp.audit -> bp.broker "Consumes audit records and domain events from" "Kafka" "Async"
        bp.audit -> bp.auditArchive "Writes immutable records and signed digests to" "HTTPS (S3 API)"
        bp.audit -> bp.auditIndex "Writes the 90-day search index to" "HTTPS (DynamoDB API)"
        compliance -> bp.backoffice "Uses" "HTTPS, staff SSO + FIDO2 MFA"
        bp.backoffice -> identity "Signs staff in with" "OIDC, SSO + FIDO2 MFA"
        bp.backoffice -> bp.gateway "Calls staff APIs through (internal route, role-based scopes)" "HTTPS"
        bp.gateway -> bp.onboarding "Routes staff review calls to" "HTTPS / mTLS"
        bp.gateway -> bp.audit "Routes audit queries to" "HTTPS / mTLS"
        bp.gateway -> bp.transfer "Routes manual-case calls to" "HTTPS / mTLS"
        biometrics -> bp.onboarding "Sends verification results to (signed webhook)" "HTTPS, HMAC signature"

        // =====================================================================
        // Component-level relationships
        // =====================================================================
        // API Gateway (Kong plugin chain)
        bp.edge -> bp.gateway.rate "Forwards requests to" "HTTPS"
        bp.gateway.rate -> bp.gateway.jwt "Passes request to"
        bp.gateway.jwt -> bp.gateway.dpop "Passes request to"
        bp.gateway.dpop -> bp.gateway.acr "Passes request to"
        bp.gateway.acr -> bp.gateway.revocation "Passes request to"
        bp.gateway.revocation -> bp.gateway.router "Passes request to"
        bp.gateway.router -> bp.webBff "Routes web calls to" "HTTPS / mTLS"
        bp.gateway.router -> bp.mobileBff "Routes mobile calls to" "HTTPS / mTLS"
        bp.gateway.router -> bp.gateway.accessLog "Hands completed call to"
        bp.gateway.jwt -> identity "Fetches JWKS from" "HTTPS"
        bp.gateway.rate -> bp.cache "Keeps counters in" "TLS"
        bp.gateway.dpop -> bp.cache "Checks jti replay cache in" "TLS"
        bp.gateway.revocation -> bp.cache "Reads revocation list from" "TLS"
        bp.gateway.accessLog -> bp.broker "Publishes access records to" "Kafka" "Async"

        // Transfer Service
        bp.mobileBff -> bp.transfer.api "Submits transfers to" "REST / mTLS"
        bp.webBff -> bp.transfer.api "Submits transfers to" "REST / mTLS"
        bp.transfer.api -> bp.transfer.idempotency "Checks Idempotency-Key with"
        bp.transfer.api -> bp.transfer.stepUp "Checks authentication level with"
        bp.transfer.api -> bp.transfer.saga "Starts transfer in"
        bp.transfer.idempotency -> bp.transferDb "Stores keys and results in" "SQL / TLS"
        bp.transfer.saga -> bp.transfer.decisionClient "Gets limits and risk decision from"
        bp.transfer.decisionClient -> bp.beneficiary "Checks beneficiary and limits with" "REST / mTLS"
        bp.transfer.decisionClient -> bp.risk "Requests a risk decision from" "REST / mTLS"
        bp.transfer.saga -> bp.transfer.coreClient "Debits / reverses through"
        bp.transfer.coreClient -> bp.coreAdapter "Posts through" "REST / mTLS"
        bp.transfer.saga -> bp.transfer.repo "Persists state with"
        bp.transfer.repo -> bp.transferDb "Reads and writes" "SQL / TLS"
        bp.transfer.saga -> bp.transfer.outbox "Records events and commands with"
        bp.transfer.outbox -> bp.transferDb "Writes outbox rows in the same transaction to" "SQL / TLS"
        bp.transfer.outbox -> bp.broker "Relays events and SendPayment commands to" "Kafka" "Async"
        bp.transfer.inbox -> bp.broker "Consumes payment events from" "Kafka" "Async"
        bp.transfer.inbox -> bp.transfer.saga "Advances or compensates the saga in"
        bp.transfer.saga -> bp.transfer.compensation "Hands failed or expired transfers to"
        bp.transfer.compensation -> bp.transfer.coreClient "Reverses the debit through"
        bp.transfer.compensation -> bp.transfer.repo "Opens manual cases in"
        bp.transfer.compensation -> bp.transfer.outbox "Publishes TransferFailed / TransferReversed with"
        bp.transfer.reconciliation -> bp.transfer.repo "Reads transfers and opens cases in"
        bp.transfer.reconciliation -> bp.coreAdapter "Reads Core postings through" "REST / mTLS"
        bp.transfer.reconciliation -> bp.interbank "Reads settlement reports from" "REST / mTLS"
        bp.transfer.opsApi -> bp.transfer.repo "Lists and resolves manual cases in"

        // Onboarding Service
        bp.mobileBff -> bp.onboarding.onbApi "Runs onboarding cases with" "REST / mTLS"
        bp.onboarding.onbApi -> bp.onboarding.attestation "Verifies the device with"
        bp.onboarding.onbApi -> bp.onboarding.orchestrator "Starts and advances cases in"
        biometrics -> bp.onboarding.webhook "Sends verification results to" "HTTPS, HMAC signature"
        bp.onboarding.webhook -> bp.onboarding.orchestrator "Passes verified result to"
        bp.onboarding.reviewApi -> bp.onboarding.orchestrator "Records reviewer decisions in"
        bp.onboarding.orchestrator -> bp.onboarding.vendorAdapter "Creates verification sessions / polls results with"
        bp.onboarding.vendorAdapter -> biometrics "Creates sessions and fetches results from" "HTTPS"
        bp.onboarding.orchestrator -> bp.onboarding.registryAdapter "Validates identity with"
        bp.onboarding.registryAdapter -> registroCivil "Validates ID data, photo and fingerprint code with" "HTTPS (SNIC)"
        bp.onboarding.orchestrator -> bp.onboarding.screeningClient "Screens the applicant with"
        bp.onboarding.screeningClient -> bp.aml "Screens PEP, sanctions, UAFE lists and duplicates with" "REST / mTLS"
        bp.onboarding.orchestrator -> bp.onboarding.decisionEngine "Asks for approve / review / reject"
        bp.onboarding.orchestrator -> bp.onboarding.accountClient "Opens the account with"
        bp.onboarding.accountClient -> bp.coreAdapter "Creates customer and account through" "REST / mTLS"
        bp.onboarding.orchestrator -> bp.onboarding.idpClient "Provisions the user with"
        bp.onboarding.idpClient -> identity "Creates the user (kyc_level=verified) in" "Admin API / SCIM"
        bp.onboarding.orchestrator -> bp.onboarding.onbRepo "Persists state and events with"
        bp.onboarding.onbRepo -> bp.onboardingDb "Writes cases, consent and outbox to" "SQL / TLS"
        bp.onboarding.onbRepo -> bp.broker "Relays OnboardingCompleted / Rejected to" "Kafka" "Async"

        // Accounts Service (frequent-client persistence)
        bp.mobileBff -> bp.accounts.accApi "Gets balances and dashboard from" "REST / mTLS"
        bp.webBff -> bp.accounts.accApi "Gets balances and dashboard from" "REST / mTLS"
        bp.accounts.accApi -> bp.accounts.cacheAside "Reads snapshot / balance from"
        bp.accounts.accApi -> bp.accounts.coreReader "On cache miss, reads from"
        bp.accounts.cacheAside -> bp.cache "Gets and sets keys with TTL in" "TLS"
        bp.accounts.coreReader -> bp.coreAdapter "Reads balances through (coalesced, rate-limited)" "REST / mTLS"
        bp.accounts.precompute -> bp.broker "Consumes LoginSucceeded from" "Kafka" "Async"
        bp.accounts.precompute -> bp.accounts.coreReader "Reads balances with"
        bp.accounts.precompute -> bp.movements "Gets last 10 movements from" "REST / mTLS"
        bp.accounts.precompute -> bp.accounts.cacheAside "Stores dashboard snapshot in"
        bp.accounts.invalidator -> bp.broker "Consumes movement and transfer events from" "Kafka" "Async"
        bp.accounts.invalidator -> bp.accounts.cacheAside "Evicts or updates keys in"
        bp.accounts.classifier -> bp.broker "Consumes login and access events from; publishes FrequentClientAdded / Removed to" "Kafka" "Async"
        bp.accounts.classifier -> bp.cache "Keeps sliding-window activity counters and flags in" "TLS"
        bp.accounts.precompute -> bp.accounts.classifier "Checks frequent-client flag with"

        // Notification Service
        bp.notification.notifConsumer -> bp.broker "Consumes domain and security events from" "Kafka" "Async"
        bp.notification.notifConsumer -> bp.notification.policy "Passes event to"
        bp.notification.policy -> bp.notification.resolver "Asks for recipients"
        bp.notification.resolver -> bp.profile "Gets contact data from" "REST / mTLS"
        bp.notification.policy -> bp.notification.renderer "Renders messages with"
        bp.notification.renderer -> bp.notification.dispatcher "Hands messages to"
        bp.notification.dispatcher -> bp.broker "Queues messages on priority lanes in" "Kafka" "Async"
        bp.notification.smsSender -> bp.broker "Consumes SMS lanes from" "Kafka" "Async"
        bp.notification.emailSender -> bp.broker "Consumes email lane from" "Kafka" "Async"
        bp.notification.pushSender -> bp.broker "Consumes push lane from" "Kafka" "Async"
        bp.notification.smsSender -> smsA "Sends SMS through (primary)" "HTTPS / SMPP"
        bp.notification.smsSender -> smsB "Sends SMS through (failover)" "HTTPS"
        bp.notification.emailSender -> email "Sends email through" "HTTPS"
        bp.notification.pushSender -> push "Sends push through" "HTTPS"
        bp.notification.smsSender -> bp.notification.tracker "Records sends with"
        bp.notification.emailSender -> bp.notification.tracker "Records sends with"
        bp.notification.pushSender -> bp.notification.tracker "Records sends with"
        smsA -> bp.notification.tracker "Sends delivery receipts to" "HTTPS webhook"
        smsB -> bp.notification.tracker "Sends delivery receipts to" "HTTPS / EventBridge"
        bp.notification.tracker -> bp.notificationDb "Stores delivery status in" "HTTPS (DynamoDB API)"
        bp.notification.tracker -> bp.notification.smsSender "Requests OTP resend via secondary when no receipt in 45 s"

        // Audit Service
        bp.audit.auditConsumer -> bp.broker "Consumes audit.* topics from" "Kafka" "Async"
        bp.audit.auditConsumer -> bp.audit.normalizer "Passes records to"
        bp.audit.normalizer -> bp.audit.chainer "Passes normalized records to"
        bp.audit.chainer -> bp.audit.archiveWriter "Passes chained records to"
        bp.audit.chainer -> bp.audit.indexWriter "Passes chained records to"
        bp.audit.archiveWriter -> bp.auditArchive "Writes Parquet files and signed digests to" "HTTPS (S3 API)"
        bp.audit.indexWriter -> bp.auditIndex "Writes index items to" "HTTPS (DynamoDB API)"
        bp.gateway.router -> bp.audit.queryApi "Routes audit queries to" "HTTPS / mTLS"
        bp.gateway.router -> bp.onboarding.reviewApi "Routes staff review calls to" "HTTPS / mTLS"
        bp.gateway.router -> bp.transfer.opsApi "Routes manual-case calls to" "HTTPS / mTLS"
        bp.audit.queryApi -> bp.auditIndex "Searches recent records in" "HTTPS (DynamoDB API)"
        bp.audit.queryApi -> bp.auditArchive "Queries history in (Athena)" "HTTPS"
        bp.audit.verifier -> bp.auditArchive "Recomputes chains and digests from" "HTTPS (S3 API)"

        // =====================================================================
        // Deployment: production (ADR-003, ADR-011, ADR-018)
        // =====================================================================
        prod = deploymentEnvironment "Production" {
            primary = deploymentGroup "Primary"
            standby = deploymentGroup "Standby"

            device = deploymentNode "Customer device" "" "iOS / Android / browser" {
                phone = deploymentNode "Mobile phone" "" "iOS / Android" {
                    mobileInst = containerInstance bp.mobile primary,standby
                }
                browser = deploymentNode "Web browser" "" "Chrome, Safari, Edge, Firefox" {
                    spaInst = containerInstance bp.spa primary,standby
                }
            }

            aws = deploymentNode "Amazon Web Services" "" "AWS" {
                global = deploymentNode "Global edge" "" "CloudFront PoPs, Route 53, ARC" {
                    route53 = infrastructureNode "Route 53 + ARC" "DNS, routing controls, Region switch plan for failover." "Amazon Route 53 / Application Recovery Controller"
                    edgeInst = containerInstance bp.edge primary,standby
                }

                use1 = deploymentNode "us-east-1 (primary)" "Primary region, 3 availability zones." "AWS Region" {
                    nlb1 = infrastructureNode "Network Load Balancer" "Spread over 3 AZs." "Elastic Load Balancing"
                    eks1 = deploymentNode "EKS cluster" "Nodes in 3 AZs, Karpenter, Istio ambient mTLS, Argo CD. Namespaces: platform (Kong, CDC), channels (Web/Mobile BFF), payments (Transfer, Beneficiary & Limits, Risk, Interbank, Core Adapter), customer (Accounts, Movements, Profile, Device, Onboarding, Customer Info Adapter), support (Notification, Audit, AML)." "Amazon EKS (Graviton)" {
                        platform = deploymentNode "platform namespace" "" "Kubernetes" {
                            gateway1 = containerInstance bp.gateway primary
                            containerInstance bp.cdc primary
                        }
                        deploymentNode "channels namespace" "" "Kubernetes" {
                            containerInstance bp.webBff primary
                            containerInstance bp.mobileBff primary
                        }
                        payments = deploymentNode "payments namespace" "" "Kubernetes" {
                            containerInstance bp.transfer primary
                            containerInstance bp.beneficiary primary
                            containerInstance bp.risk primary
                            containerInstance bp.interbank primary
                            coreAdapter1 = containerInstance bp.coreAdapter primary
                        }
                        deploymentNode "customer namespace" "" "Kubernetes" {
                            containerInstance bp.accounts primary
                            containerInstance bp.movements primary
                            containerInstance bp.profile primary
                            containerInstance bp.device primary
                            containerInstance bp.onboarding primary
                            containerInstance bp.customerInfoAdapter primary
                        }
                        deploymentNode "support namespace" "" "Kubernetes" {
                            containerInstance bp.notification primary
                            containerInstance bp.audit primary
                            containerInstance bp.aml primary
                        }
                    }
                    aurora1 = deploymentNode "Aurora PostgreSQL (writer + 2 readers, 3 AZs)" "Global Database primary. 5 clusters: Transfer, Beneficiary & Limits, Onboarding, Profile, Interbank." "Amazon Aurora" {
                        transferDb1 = containerInstance bp.transferDb primary
                        containerInstance bp.beneficiaryDb primary
                        containerInstance bp.onboardingDb primary
                        containerInstance bp.profileDb primary
                        containerInstance bp.interbankDb primary
                    }
                    dynamo1 = deploymentNode "DynamoDB" "Global tables: Movements read model, Device, Notification log, Audit hot index." "Amazon DynamoDB" {
                        containerInstance bp.deviceDb primary
                        movementsDb1 = containerInstance bp.movementsDb primary
                        containerInstance bp.notificationDb primary
                        containerInstance bp.auditIndex primary
                    }
                    redis1 = deploymentNode "ElastiCache cluster (3 shards, replicas in other AZs)" "Global Datastore primary." "Amazon ElastiCache (Valkey)" {
                        cache1 = containerInstance bp.cache primary
                    }
                    msk1 = deploymentNode "MSK cluster (3 AZs, RF 3)" "" "Amazon MSK" {
                        broker1 = containerInstance bp.broker primary
                    }
                    s3a = deploymentNode "Log archive account" "S3 Object Lock, compliance mode." "Amazon S3" {
                        archive1 = containerInstance bp.auditArchive primary
                    }
                    obs1 = infrastructureNode "Observability" "ADOT collectors (DaemonSet) receive OTLP from every pod: metrics to Amazon Managed Prometheus, traces to X-Ray / Application Signals, logs to CloudWatch Logs (PII redacted, tail sampling). Amazon Managed Grafana for SLO dashboards and burn-rate alerts to PagerDuty; CloudWatch Synthetics canaries plus external probes from Ecuador; security findings to Security Lake and the bank SIEM (ADR-019)." "ADOT, Amazon Managed Prometheus, Managed Grafana, CloudWatch, X-Ray"
                }

                use2 = deploymentNode "us-east-2 (warm standby)" "DR region: data replicated, T1 compute at ~25-30%." "AWS Region" "Standby" {
                    nlb2 = infrastructureNode "Network Load Balancer" "Ready for failover." "Elastic Load Balancing" "Standby"
                    eks2 = deploymentNode "EKS cluster (scaled down)" "Same namespaces and services as the primary via GitOps, T1 at ~25-30% capacity; scaled up by the Region switch plan." "Amazon EKS (Graviton)" "Standby" {
                        platform = deploymentNode "platform namespace" "" "Kubernetes" "Standby" {
                            gateway2 = containerInstance bp.gateway standby
                            containerInstance bp.cdc standby
                        }
                        deploymentNode "channels namespace" "" "Kubernetes" "Standby" {
                            containerInstance bp.webBff standby
                            containerInstance bp.mobileBff standby
                        }
                        payments = deploymentNode "payments namespace" "" "Kubernetes" "Standby" {
                            containerInstance bp.transfer standby
                            containerInstance bp.beneficiary standby
                            containerInstance bp.risk standby
                            containerInstance bp.interbank standby
                            coreAdapter2 = containerInstance bp.coreAdapter standby
                        }
                        deploymentNode "customer namespace" "" "Kubernetes" "Standby" {
                            containerInstance bp.accounts standby
                            containerInstance bp.movements standby
                            containerInstance bp.profile standby
                            containerInstance bp.device standby
                            containerInstance bp.onboarding standby
                            containerInstance bp.customerInfoAdapter standby
                        }
                        deploymentNode "support namespace" "" "Kubernetes" "Standby" {
                            containerInstance bp.notification standby
                            containerInstance bp.audit standby
                            containerInstance bp.aml standby
                        }
                    }
                    aurora2 = deploymentNode "Aurora PostgreSQL (secondary, read-only)" "Global Database secondary of the 5 clusters." "Amazon Aurora" "Standby" {
                        transferDb2 = containerInstance bp.transferDb standby
                        containerInstance bp.beneficiaryDb standby
                        containerInstance bp.onboardingDb standby
                        containerInstance bp.profileDb standby
                        containerInstance bp.interbankDb standby
                    }
                    dynamo2 = deploymentNode "DynamoDB" "Global tables replicas of the 4 tables." "Amazon DynamoDB" "Standby" {
                        containerInstance bp.deviceDb standby
                        movementsDb2 = containerInstance bp.movementsDb standby
                        containerInstance bp.notificationDb standby
                        containerInstance bp.auditIndex standby
                    }
                    redis2 = deploymentNode "ElastiCache (Global Datastore secondary)" "" "Amazon ElastiCache (Valkey)" "Standby" {
                        cache2 = containerInstance bp.cache standby
                    }
                    msk2 = deploymentNode "MSK cluster" "Topics replicated by MSK Replicator." "Amazon MSK" "Standby" {
                        broker2 = containerInstance bp.broker standby
                    }
                    s3b = deploymentNode "Log archive replica" "Cross-Region Replication with Object Lock." "Amazon S3" "Standby" {
                        archive2 = containerInstance bp.auditArchive standby
                    }
                    obs2 = infrastructureNode "Observability (standby)" "Same ADOT, Prometheus, Grafana and CloudWatch stack, already running so the DR region is monitored before and during a failover; dashboards and alerts deployed by GitOps." "ADOT, Amazon Managed Prometheus, Managed Grafana, CloudWatch, X-Ray" "Standby"
                }

                replication = infrastructureNode "Cross-region replication" "Managed, asynchronous replication us-east-1 to us-east-2 (RPO < 1 min)." "AWS managed replication"
                dx = infrastructureNode "Direct Connect gateway" "2 Direct Connect links (different providers and locations) + Site-to-Site VPN backup; reaches both regions." "AWS Direct Connect"
            }

            onprem = deploymentNode "BP data centres (Ecuador)" "On-premises, with the bank's own DR site." "On-premises" {
                coreInst = softwareSystemInstance core primary,standby
                customerInfoInst = softwareSystemInstance customerInfo primary,standby
                identityInst = softwareSystemInstance identity primary,standby
            }

            // Replication and connectivity (between leaf elements so autolayout works)
            aws.use1.aurora1.transferDb1 -> aws.replication "Replicates all Aurora clusters through" "Aurora Global Database (< 1 s)" "Infra"
            aws.use1.dynamo1.movementsDb1 -> aws.replication "Replicates all tables through" "DynamoDB global tables" "Infra"
            aws.use1.redis1.cache1 -> aws.replication "Replicates critical keys through" "ElastiCache Global Datastore" "Infra"
            aws.use1.msk1.broker1 -> aws.replication "Replicates topics through" "MSK Replicator" "Infra"
            aws.use1.s3a.archive1 -> aws.replication "Replicates through" "S3 Cross-Region Replication" "Infra"
            aws.replication -> aws.use2.aurora2.transferDb2 "Updates" "Aurora Global Database" "Infra"
            aws.replication -> aws.use2.dynamo2.movementsDb2 "Updates" "DynamoDB global tables" "Infra"
            aws.replication -> aws.use2.redis2.cache2 "Updates" "Global Datastore" "Infra"
            aws.replication -> aws.use2.msk2.broker2 "Updates" "MSK Replicator" "Infra"
            aws.replication -> aws.use2.s3b.archive2 "Updates" "S3 CRR" "Infra"
            aws.global.edgeInst -> aws.use1.nlb1 "Forwards API traffic to (active)" "HTTPS" "Infra"
            aws.global.edgeInst -> aws.use2.nlb2 "Forwards API traffic to on failover" "HTTPS" "Infra"
            aws.use1.nlb1 -> aws.use1.eks1.platform.gateway1 "Forwards to" "TLS" "Infra"
            aws.use2.nlb2 -> aws.use2.eks2.platform.gateway2 "Forwards to" "TLS" "Infra"
            aws.global.route53 -> aws.use1.nlb1 "Routes traffic to (active)" "DNS / ARC routing control" "Infra"
            aws.global.route53 -> aws.use2.nlb2 "Routes traffic to on failover" "DNS / ARC routing control" "Infra"
            aws.use1.eks1.payments.coreAdapter1 -> aws.dx "Reaches the Core through" "REST / SOAP" "Infra"
            aws.use2.eks2.payments.coreAdapter2 -> aws.dx "Reaches the Core through" "REST / SOAP" "Infra"
            aws.dx -> onprem.coreInst "Connects to" "Direct Connect (MACsec / IPsec)" "Infra"
            aws.use1.eks1.platform.gateway1 -> aws.use1.obs1 "All pods send metrics, traces and logs to" "OTLP" "Infra"
            aws.use2.eks2.platform.gateway2 -> aws.use2.obs2 "All pods send metrics, traces and logs to" "OTLP" "Infra"
        }
    }

    views {
        // ---------- Level 1 ----------
        systemContext bp "01-Context" "System context: who uses BP Internet Banking and which systems it depends on. For business and non-technical stakeholders." {
            include *
            exclude "smsA -> bp"
            exclude "smsB -> bp"
            exclude "push -> bp"
            exclude "identity -> bp"
            autolayout lr 300 200
        }

        // ---------- Level 2 ----------
        container bp "02-Containers" "All containers of BP Internet Banking. Reference view; the focused views below are easier to read." {
            include *
            autolayout lr 300 150
        }

        container bp "02a-Containers-Channels" "Channels, edge, API Gateway and BFFs: how the web and mobile apps reach the platform, and where tokens are handled." {
            include customer prospect compliance bp.spa bp.mobile bp.backoffice bp.edge bp.gateway bp.webBff bp.mobileBff identity biometrics push bp.cache
            autolayout lr 300 150
        }

        container bp "02b-Containers-Payments" "Transfers and payments: Saga orchestration, decisions before money moves, Core and interbank integration." {
            include bp.webBff bp.mobileBff bp.transfer bp.beneficiary bp.risk bp.coreAdapter bp.interbank bp.transferDb bp.beneficiaryDb bp.interbankDb bp.broker bp.cache core interbankNet
            autolayout lr 300 150
        }

        container bp "02c-Containers-Data" "Data access and frequent-client persistence: cache-aside, CQRS read model fed by Core CDC, adapters to on-premises systems." {
            include bp.mobileBff bp.webBff bp.accounts bp.movements bp.profile bp.cdc bp.broker bp.cache bp.movementsDb bp.profileDb bp.coreAdapter bp.customerInfoAdapter core customerInfo
            autolayout lr 300 150
        }

        container bp "02d-Containers-Onboarding" "Onboarding with facial recognition: eKYC vendor, Registro Civil, AML screening, account opening, user creation, device binding." {
            include prospect compliance bp.mobile bp.backoffice bp.gateway bp.mobileBff bp.onboarding bp.onboardingDb bp.device bp.deviceDb bp.aml bp.coreAdapter bp.broker biometrics registroCivil identity core
            autolayout lr 300 150
        }

        container bp "02e-Containers-Notifications-Audit" "Event-driven support services: notifications over 2 channels with provider failover, and the immutable audit trail." {
            include customer compliance bp.backoffice bp.gateway bp.broker bp.notification bp.notificationDb bp.profile bp.audit bp.auditIndex bp.auditArchive bp.aml smsA smsB email push
            autolayout lr 300 150
        }

        // ---------- Level 3 ----------
        component bp.gateway "03-Components-Gateway" "API Gateway (Kong) plugin chain: token, DPoP and acr checks before routing (Step 6, ADR-009)." {
            include *
            exclude "bp.gateway -> bp.broker"
            exclude "bp.gateway -> identity"
            exclude "identity -> bp.broker"
            exclude "bp.aml -> bp.broker"
            exclude "bp.risk -> bp.broker"
            exclude "bp.beneficiary -> bp.broker"
            exclude "bp.interbank -> bp.broker"
            exclude "bp.interbank -> bp.coreAdapter"
            exclude "bp.webBff -> bp.beneficiary"
            exclude "bp.mobileBff -> bp.beneficiary"
            exclude "bp.risk -> bp.cache"
            exclude "bp.movements -> bp.broker"
            exclude "bp.movements -> bp.coreAdapter"
            exclude "bp.movements -> bp.movementsDb"
            exclude "bp.profile -> bp.broker"
            exclude "bp.profile -> bp.coreAdapter"
            exclude "bp.profile -> bp.cache"
            exclude "bp.profile -> bp.profileDb"
            exclude "bp.profile -> bp.customerInfoAdapter"
            exclude "bp.webBff -> bp.cache"
            exclude "bp.gateway -> bp.cache"
            exclude "bp.mobileBff -> bp.movements"
            exclude "bp.webBff -> bp.movements"
            exclude "bp.mobileBff -> bp.profile"
            exclude "bp.webBff -> bp.profile"
            exclude "bp.audit -> bp.broker"
            exclude "bp.notification -> bp.broker"
            autolayout lr 250 150
        }

        component bp.transfer "03-Components-Transfer" "Transfer Service: idempotency, step-up, orchestrated Saga, circuit-broken Core calls, transactional outbox and inbox (Step 8)." {
            include *
            exclude "bp.gateway -> bp.broker"
            exclude "bp.gateway -> identity"
            exclude "identity -> bp.broker"
            exclude "bp.aml -> bp.broker"
            exclude "bp.risk -> bp.broker"
            exclude "bp.beneficiary -> bp.broker"
            exclude "bp.interbank -> bp.broker"
            exclude "bp.interbank -> bp.coreAdapter"
            exclude "bp.webBff -> bp.beneficiary"
            exclude "bp.mobileBff -> bp.beneficiary"
            exclude "bp.risk -> bp.cache"
            exclude "bp.movements -> bp.broker"
            exclude "bp.movements -> bp.coreAdapter"
            exclude "bp.movements -> bp.movementsDb"
            exclude "bp.profile -> bp.broker"
            exclude "bp.profile -> bp.coreAdapter"
            exclude "bp.profile -> bp.cache"
            exclude "bp.profile -> bp.profileDb"
            exclude "bp.profile -> bp.customerInfoAdapter"
            exclude "bp.webBff -> bp.cache"
            exclude "bp.gateway -> bp.cache"
            exclude "bp.mobileBff -> bp.movements"
            exclude "bp.webBff -> bp.movements"
            exclude "bp.mobileBff -> bp.profile"
            exclude "bp.webBff -> bp.profile"
            exclude "bp.audit -> bp.broker"
            exclude "bp.notification -> bp.broker"
            autolayout lr 250 150
        }

        component bp.onboarding "03-Components-Onboarding" "Onboarding Service: device attestation, signed vendor webhook, state machine, decision engine, four-eyes manual review, adapters and IdP provisioning (Step 7, ADR-008)." {
            include *
            exclude "bp.gateway -> bp.broker"
            exclude "bp.gateway -> identity"
            exclude "identity -> bp.broker"
            exclude "bp.aml -> bp.broker"
            exclude "bp.risk -> bp.broker"
            exclude "bp.beneficiary -> bp.broker"
            exclude "bp.interbank -> bp.broker"
            exclude "bp.interbank -> bp.coreAdapter"
            exclude "bp.webBff -> bp.beneficiary"
            exclude "bp.mobileBff -> bp.beneficiary"
            exclude "bp.risk -> bp.cache"
            exclude "bp.movements -> bp.broker"
            exclude "bp.movements -> bp.coreAdapter"
            exclude "bp.movements -> bp.movementsDb"
            exclude "bp.profile -> bp.broker"
            exclude "bp.profile -> bp.coreAdapter"
            exclude "bp.profile -> bp.cache"
            exclude "bp.profile -> bp.profileDb"
            exclude "bp.profile -> bp.customerInfoAdapter"
            exclude "bp.webBff -> bp.cache"
            exclude "bp.gateway -> bp.cache"
            exclude "bp.mobileBff -> bp.movements"
            exclude "bp.webBff -> bp.movements"
            exclude "bp.mobileBff -> bp.profile"
            exclude "bp.webBff -> bp.profile"
            exclude "bp.audit -> bp.broker"
            exclude "bp.notification -> bp.broker"
            autolayout lr 250 150
        }

        component bp.accounts "03-Components-Accounts" "Accounts Service: frequent-client persistence with cache-aside, refresh-ahead and event-driven invalidation (Step 9, ADR-013)." {
            include *
            exclude "bp.gateway -> bp.broker"
            exclude "bp.gateway -> identity"
            exclude "identity -> bp.broker"
            exclude "bp.aml -> bp.broker"
            exclude "bp.risk -> bp.broker"
            exclude "bp.beneficiary -> bp.broker"
            exclude "bp.interbank -> bp.broker"
            exclude "bp.interbank -> bp.coreAdapter"
            exclude "bp.webBff -> bp.beneficiary"
            exclude "bp.mobileBff -> bp.beneficiary"
            exclude "bp.risk -> bp.cache"
            exclude "bp.movements -> bp.broker"
            exclude "bp.movements -> bp.coreAdapter"
            exclude "bp.movements -> bp.movementsDb"
            exclude "bp.profile -> bp.broker"
            exclude "bp.profile -> bp.coreAdapter"
            exclude "bp.profile -> bp.cache"
            exclude "bp.profile -> bp.profileDb"
            exclude "bp.profile -> bp.customerInfoAdapter"
            exclude "bp.webBff -> bp.cache"
            exclude "bp.gateway -> bp.cache"
            exclude "bp.mobileBff -> bp.movements"
            exclude "bp.webBff -> bp.movements"
            exclude "bp.mobileBff -> bp.profile"
            exclude "bp.webBff -> bp.profile"
            exclude "bp.audit -> bp.broker"
            exclude "bp.notification -> bp.broker"
            autolayout lr 250 150
        }

        component bp.notification "03-Components-Notification" "Notification Service: policy, templates, priority lanes, SMS failover and delivery tracking (Step 11, ADR-016)." {
            include *
            exclude "bp.gateway -> bp.broker"
            exclude "bp.gateway -> identity"
            exclude "identity -> bp.broker"
            exclude "bp.aml -> bp.broker"
            exclude "bp.risk -> bp.broker"
            exclude "bp.beneficiary -> bp.broker"
            exclude "bp.interbank -> bp.broker"
            exclude "bp.interbank -> bp.coreAdapter"
            exclude "bp.webBff -> bp.beneficiary"
            exclude "bp.mobileBff -> bp.beneficiary"
            exclude "bp.risk -> bp.cache"
            exclude "bp.movements -> bp.broker"
            exclude "bp.movements -> bp.coreAdapter"
            exclude "bp.movements -> bp.movementsDb"
            exclude "bp.profile -> bp.broker"
            exclude "bp.profile -> bp.coreAdapter"
            exclude "bp.profile -> bp.cache"
            exclude "bp.profile -> bp.profileDb"
            exclude "bp.profile -> bp.customerInfoAdapter"
            exclude "bp.webBff -> bp.cache"
            exclude "bp.gateway -> bp.cache"
            exclude "bp.mobileBff -> bp.movements"
            exclude "bp.webBff -> bp.movements"
            exclude "bp.mobileBff -> bp.profile"
            exclude "bp.webBff -> bp.profile"
            exclude "bp.audit -> bp.broker"
            exclude "bp.notification -> bp.broker"
            autolayout lr 250 150
        }

        component bp.audit "03-Components-Audit" "Audit Service: idempotent consumer, normalization, hash chain and signed digests, WORM archive and hot index (Step 10, ADR-015)." {
            include *
            exclude "bp.gateway -> bp.broker"
            exclude "bp.gateway -> identity"
            exclude "identity -> bp.broker"
            exclude "bp.aml -> bp.broker"
            exclude "bp.risk -> bp.broker"
            exclude "bp.beneficiary -> bp.broker"
            exclude "bp.interbank -> bp.broker"
            exclude "bp.interbank -> bp.coreAdapter"
            exclude "bp.webBff -> bp.beneficiary"
            exclude "bp.mobileBff -> bp.beneficiary"
            exclude "bp.risk -> bp.cache"
            exclude "bp.movements -> bp.broker"
            exclude "bp.movements -> bp.coreAdapter"
            exclude "bp.movements -> bp.movementsDb"
            exclude "bp.profile -> bp.broker"
            exclude "bp.profile -> bp.coreAdapter"
            exclude "bp.profile -> bp.cache"
            exclude "bp.profile -> bp.profileDb"
            exclude "bp.profile -> bp.customerInfoAdapter"
            exclude "bp.webBff -> bp.cache"
            exclude "bp.gateway -> bp.cache"
            exclude "bp.mobileBff -> bp.movements"
            exclude "bp.webBff -> bp.movements"
            exclude "bp.mobileBff -> bp.profile"
            exclude "bp.webBff -> bp.profile"
            exclude "bp.audit -> bp.broker"
            exclude "bp.notification -> bp.broker"
            autolayout lr 250 150
        }

        // ---------- Dynamic views ----------
        dynamic bp "05-Dynamic-Login-Web" "Web login: Authorization Code + PKCE + PAR through the Web BFF (token handler). Tokens never reach the browser (Step 6)." {
            customer -> bp.spa "Clicks Log in"
            bp.spa -> bp.edge "GET /bff/web/login"
            bp.edge -> bp.gateway "Forwards"
            bp.gateway -> bp.webBff "Routes"
            bp.webBff -> identity "Pushes authorization request (PAR, PKCE challenge, acr:2)"
            customer -> identity "Enters username, password and OTP (in-app preferred, SMS fallback)"
            bp.webBff -> identity "Exchanges code + PKCE verifier for tokens (private_key_jwt)"
            bp.webBff -> bp.cache "Stores tokens in encrypted session; returns HttpOnly cookie"
            identity -> bp.broker "Publishes LoginSucceeded"
            bp.notification -> bp.broker "Consumes LoginSucceeded"
            bp.notification -> smsA "Sends login notice by SMS"
            bp.notification -> email "Sends login notice by email"
            autolayout lr
        }

        dynamic bp "05-Dynamic-Login-Biometric" "Mobile biometric login: biometrics unlock a device-bound key that signs the DPoP proof; the dashboard is served from a pre-built snapshot (Steps 6 and 9)." {
            customer -> bp.mobile "Unlocks device key with Face ID / fingerprint"
            bp.mobile -> identity "Refresh token grant + DPoP proof signed by device key"
            identity -> bp.broker "Publishes LoginSucceeded"
            bp.accounts -> bp.broker "Consumes LoginSucceeded (refresh-ahead) and pre-builds dashboard"
            bp.mobile -> bp.edge "GET dashboard + DPoP proof"
            bp.edge -> bp.gateway "Forwards"
            bp.gateway -> bp.mobileBff "Routes after JWT, DPoP and acr checks"
            bp.mobileBff -> bp.device "Is this device bound and not blocked?"
            bp.mobileBff -> bp.accounts "Gets dashboard"
            bp.accounts -> bp.cache "Reads dashboard snapshot (cache hit)"
            autolayout lr
        }

        dynamic bp "05-Dynamic-Onboarding" "Onboarding Saga with facial recognition (Step 7)." {
            prospect -> bp.mobile "Starts onboarding, gives consent, verifies phone and email"
            bp.mobile -> bp.edge "Creates case (app attestation)"
            bp.edge -> bp.gateway "Forwards"
            bp.gateway -> bp.mobileBff "Routes"
            bp.mobileBff -> bp.onboarding "Creates onboarding case"
            bp.mobile -> biometrics "Captures cédula, selfie and liveness (vendor SDK)"
            bp.onboarding -> biometrics "Fetches document, liveness and face-match result"
            bp.onboarding -> registroCivil "Validates ID number, fingerprint code and face"
            bp.onboarding -> bp.aml "Screens PEP, sanctions and UAFE lists"
            bp.onboarding -> bp.coreAdapter "Creates customer and account (idempotent on case ID)"
            bp.coreAdapter -> core "Opens account"
            bp.onboarding -> identity "Creates user"
            bp.mobileBff -> bp.device "Binds device key (DPoP key in Secure Enclave / StrongBox)"
            bp.onboarding -> bp.broker "Publishes OnboardingCompleted (outbox)"
            bp.notification -> bp.broker "Consumes OnboardingCompleted"
            bp.notification -> smsA "Sends welcome SMS"
            bp.notification -> email "Sends welcome email"
            autolayout lr
        }

        dynamic bp "05-Dynamic-Transfer-Interbank" "Interbank real-time transfer: orchestrated Saga, debit before pacs.008 (BCE art. 7), asynchronous settlement and notifications (Step 8)." {
            customer -> bp.mobile "Confirms transfer (biometric)"
            bp.mobile -> bp.edge "POST /v1/transfers (Idempotency-Key, DPoP)"
            bp.edge -> bp.gateway "Forwards"
            bp.gateway -> bp.mobileBff "Routes after token, DPoP and acr checks"
            bp.mobileBff -> bp.transfer "Submits transfer"
            bp.transfer -> bp.transferDb "Saves RECEIVED + idempotency key"
            bp.transfer -> bp.beneficiary "Checks beneficiary and limits"
            bp.transfer -> bp.risk "Gets risk decision (allow)"
            bp.transfer -> bp.coreAdapter "Debits customer, credits clearing account"
            bp.coreAdapter -> core "Posts"
            bp.transfer -> bp.broker "Publishes TransferDebited + SendPayment (outbox); returns 202 PENDING"
            bp.interbank -> bp.broker "Consumes SendPayment"
            bp.interbank -> interbankNet "Sends pacs.008"
            interbankNet -> bp.interbank "Returns pacs.002 (accepted, irrevocable)"
            bp.interbank -> bp.broker "Publishes PaymentAccepted"
            bp.transfer -> bp.broker "Consumes PaymentAccepted; publishes TransferCompleted"
            bp.notification -> bp.broker "Consumes TransferCompleted"
            bp.notification -> smsA "Sends SMS notice"
            bp.notification -> email "Sends email notice (in parallel)"
            bp.audit -> bp.broker "Records every step"
            autolayout lr
        }

        dynamic bp "05-Dynamic-StepUp-Transfer" "Step-up with dynamic linking: a transfer to a new beneficiary over the threshold needs a fresh acr:3 confirmation bound to amount and beneficiary (RFC 9470 + RFC 9396). A stolen acr:2 token can't move this money (Step 6, ADR-007)." {
            customer -> bp.mobile "Requests transfer to a new beneficiary above the threshold"
            bp.mobile -> bp.edge "POST /v1/transfers (Idempotency-Key, DPoP, acr:2 token)"
            bp.edge -> bp.gateway "Forwards"
            bp.gateway -> bp.mobileBff "Routes after JWT and DPoP checks (route allows acr:2)"
            bp.mobileBff -> bp.transfer "Submits transfer"
            bp.transfer -> bp.beneficiary "New beneficiary, amount above threshold"
            bp.transfer -> bp.risk "Gets risk decision (step-up)"
            bp.transfer -> bp.mobileBff "Rejects: insufficient_user_authentication, acr_values=3 (RFC 9470)"
            bp.edge -> bp.mobile "Returns 401 with the step-up challenge"
            bp.mobile -> identity "Re-authorizes: PAR with authorization_details (amount, beneficiary; RFC 9396), acr:3"
            customer -> bp.mobile "Reviews amount and beneficiary; approves with biometrics (device key signs)"
            identity -> bp.mobile "Issues 2-minute, single-use, DPoP-bound token for this transaction only"
            bp.mobile -> bp.edge "Retries POST with the new token (same Idempotency-Key)"
            bp.edge -> bp.gateway "Forwards"
            bp.gateway -> bp.mobileBff "Routes after acr:3 check"
            bp.mobileBff -> bp.transfer "Submits transfer"
            bp.transfer -> bp.beneficiary "Registers beneficiary; cooling-period limit applies"
            bp.transfer -> bp.coreAdapter "Debits within the cooling-period limit"
            bp.coreAdapter -> core "Posts"
            bp.transfer -> bp.broker "Publishes TransferDebited (outbox)"
            bp.notification -> bp.broker "Consumes TransferDebited and BeneficiaryAdded"
            bp.notification -> smsA "Sends SMS notice"
            bp.notification -> email "Sends email notice (in parallel)"
            autolayout lr
        }

        // ---------- Deployment ----------
        deployment bp prod "04-Deployment-Production" "Production on AWS: us-east-1 primary (3 AZs), us-east-2 warm standby, hybrid link to the on-premises Core (Steps 3 and 13). One representative element per platform service; node descriptions list everything deployed there. Service-to-service calls are in the container views." {
            include prod.device.phone.mobileInst prod.device.browser.spaInst
            include prod.aws.global.edgeInst prod.aws.global.route53
            include prod.aws.use1.nlb1 prod.aws.use1.eks1.platform.gateway1 prod.aws.use1.eks1.payments.coreAdapter1
            include prod.aws.use1.aurora1.transferDb1 prod.aws.use1.dynamo1.movementsDb1 prod.aws.use1.redis1.cache1 prod.aws.use1.msk1.broker1 prod.aws.use1.s3a.archive1
            include prod.aws.use2.nlb2 prod.aws.use2.eks2.platform.gateway2 prod.aws.use2.eks2.payments.coreAdapter2
            include prod.aws.use2.aurora2.transferDb2 prod.aws.use2.dynamo2.movementsDb2 prod.aws.use2.redis2.cache2 prod.aws.use2.msk2.broker2 prod.aws.use2.s3b.archive2
            include prod.aws.replication prod.aws.dx prod.onprem.coreInst prod.onprem.customerInfoInst prod.onprem.identityInst
            include prod.aws.use1.obs1 prod.aws.use2.obs2
            exclude "relationship.tag==Relationship"
            include "relationship.tag==Infra"
            autolayout lr 200 100
        }

        styles {
            element "Element" {
                fontSize 30
                shape roundedbox
            }
            element "Person" {
                shape person
                background #08427b
                color #ffffff
            }
            element "Staff" {
                background #3b5b7a
            }
            element "Software System" {
                background #1168bd
                color #ffffff
            }
            element "InScope" {
                background #1168bd
                color #ffffff
            }
            element "Internal" {
                background #5a7d9a
                color #ffffff
            }
            element "Existing" {
                stroke #2f4f6f
                strokeWidth 4
            }
            element "External" {
                background #999999
                color #ffffff
            }
            element "Container" {
                background #438dd5
                color #ffffff
            }
            element "Component" {
                background #85bbf0
                color #000000
            }
            element "Infrastructure" {
                background #6c757d
                color #ffffff
                shape hexagon
            }
            element "Gateway" {
                background #2f6fae
                color #ffffff
                shape hexagon
            }
            element "WebApp" {
                shape webbrowser
            }
            element "MobileApp" {
                shape mobiledeviceportrait
            }
            element "Database" {
                shape cylinder
                background #2e7d5b
                color #ffffff
            }
            element "Cache" {
                shape cylinder
                background #b5651d
                color #ffffff
            }
            element "Queue" {
                shape pipe
                background #6a4c93
                color #ffffff
            }
            element "Deployment Node" {
                background #ffffff
                color #000000
            }
            element "Infrastructure Node" {
                background #ffffff
                color #000000
                shape roundedbox
            }
            element "Standby" {
                stroke #c0392b
                border dashed
            }
            relationship "Relationship" {
                thickness 3
                fontSize 28
                width 300
            }
            relationship "Async" {
                style dashed
            }
        }
    }

}
