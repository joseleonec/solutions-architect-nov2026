# Step 2: Regulatory and compliance baseline

**Scope:** Banco Pichincha, a private bank in **Ecuador**, supervised by the **Superintendencia de Bancos (SB)**. **No card processing** is involved, so PCI DSS is out of scope (see section 4).

> **Verify before quoting article numbers.** The SB electronic-channel and cloud requirements below were read from **Resolution SB-2021-2126**, the operational-risk norm (Libro I, Título IX, Capítulo V of the SB Codification). That chapter was **fully replaced in September 2023** and **reformed in 2024 (SB-2024-02855)**. The requirements are very likely still there, but article numbers may have changed. In the PDF, cite the *norm* ("Norma de control para la gestión del riesgo operativo, SB") rather than specific article numbers, unless you've checked the current codified text on [superbancos.gob.ec](https://www.superbancos.gob.ec).

---

## 1. Applicable regulations

| # | Norm | Authority | Why it applies to this system |
| --- | --- | --- | --- |
| R1 | **Norma de control para la gestión del riesgo operativo** (SB-2021-2126, replaced 2023, reformed 2024) | Superintendencia de Bancos | The core norm. Electronic channel security, e-banking and mobile banking controls, cloud and outsourcing, business continuity, incident reporting. |
| R2 | **Código Orgánico Monetario y Financiero (COMF)** | Asamblea Nacional / JPRF | Framework law for the financial system. Banking secrecy (*sigilo bancario*), record keeping, powers of the JPRF and SB. |
| R3 | **Ley Orgánica de Protección de Datos Personales (LOPDP)**, 2021, plus its regulation and SPDP resolutions | Superintendencia de Protección de Datos Personales (SPDP) | All customer personal data, **biometric data** from onboarding, breach notification, transfers to cloud providers. |
| R4 | **SPDP-SPD-2026-0039-R**: general rule on biometric data (Sep 2026) | SPDP | Facial recognition during onboarding and biometric login. |
| R5 | **SPDP-SPD-2026-0040-R**: technical rule on breach notification (Sep 2026) | SPDP | Incident response deadlines. |
| R6 | **SPDP norm on national and international data transfers** (2026) | SPDP | Hosting or processing data outside Ecuador (cloud regions). |
| R7 | **Ley Orgánica de Prevención, Detección y Combate del Delito de Lavado de Activos y de la Financiación de Otros Delitos** (RO 610, Jul 2024; in force Jul 2025) and its **2026 regulation** (Decree 298) | UAFE | KYC during onboarding, transaction monitoring, record retention. |
| R8 | **BCE payment system rules**: Sistema de Pagos Interbancarios (SPI) technical norm v2 (Mar 2026) and the **real-time payments messaging standard** (Res. BCE-GG-007-2026) | Banco Central del Ecuador | Interbank transfers. |
| R9 | **Ley de Comercio Electrónico, Firmas Electrónicas y Mensajes de Datos** | Asamblea Nacional | Legal validity of electronic transactions, data messages and electronic consent. |
| R10 | **Financial consumer protection norms** (e.g., SB-2023-2208, financial users) | SB | Customer rights, complaints, transparency. Verify the current text. |

---

## 2. Key requirements and their impact on the architecture

### 2.1 Electronic channels, e-banking and mobile banking (R1)

| Requirement (from the SB norm) | Architecture response | Step |
| --- | --- | --- |
| **Online notification of every monetary transaction**, sent by **mobile messaging and email *simultaneously*** | This is the legal basis for "at least 2 notification systems": **SMS (or push) + email**, sent in parallel by an event-driven notification service. | 11 |
| **Notify the customer of every e-banking login** | Login event → notification service. | 6, 11 |
| **Strong authentication with 2 of 3 factors** (know / have / are) for **login**, for **transfers to unregistered accounts** and for credit operations. One factor must be dynamic: an OTP, biometrics, etc. | Authorization Code + PKCE with MFA at login. **Step-up** (OTP or biometric) for transfers to new beneficiaries. | 6 |
| **Mobile banking: transactions only from authorized devices** | **Device binding** / device registration at onboarding. The device key is stored in the secure enclave. | 6, 7 |
| Customers can **register favourite accounts** and **set maximum amounts** per transaction | Beneficiaries service + limits service (FR-14). | 4, 8 |
| Changing mobile number or email requires **strong authentication** and **notification to both the old and new contacts** | Step-up flow + dual notification. | 6, 11 |
| **Block the channel after 3 failed login attempts** or unusual events, with **online notification** and secure reactivation | Identity provider lockout policy + notification. | 6 |
| **Real-time transaction risk profiling**: allow or reject monetary transactions online and notify the customer | **Fraud / risk-scoring** step in the transfer flow before posting to the Core. | 8 |
| **Session inactivity timeout**; show **date and time of the last login** at the start of each session | Short-lived tokens and an idle timeout in the BFF. "Last login" stored in the profile. | 5, 6 |
| Username **different from the national ID number**; credentials **alphanumeric, minimum 6 characters**; passwords **masked**; e-banking passwords **renewed at least once a year** and different from other channels | Identity provider password policy. | 6 |
| **Encryption** of communications and confidential data per international standards. Account numbers **masked** when sent by email or the internet. | TLS 1.2+ (1.3 preferred), mTLS internally, encryption at rest with KMS/HSM, masking in notifications. | 8, 12 |
| **Purpose-specific technology to generate and validate passwords**, always encrypted | HSM / managed KMS for keys and OTP seeds. | 12 |
| **Anti-malware and anti-tampering** on channels, with alarms to block the channel | Mobile **RASP**, root/jailbreak detection, app integrity checks. | 5, 12 |
| Detect **cloned websites**, altered links, spoofed certificates and **DNS tampering** | Brand and anti-phishing monitoring, DNSSEC, CAA records, certificate transparency monitoring. | 12 |
| **Independent penetration test at least once a year** and after significant changes, with an action plan | DevSecOps pipeline + annual third-party pentest. | 12, 15 |
| **Online monitoring and alarms** on channel status, to detect unusual or fraudulent events | Observability stack + SIEM. | 14 |
| **Synchronized clocks** on all systems | NTP / cloud time sync. Essential for audit correlation. | 10, 14 |
| **Transaction history kept at least 12 months** with: date, time, amount, origin and destination accounts and banks, transaction number, phone and email notified, OTPs used, **IP address** | Defines the **minimum audit record schema**. Longer retention if a claim exists, or if it counts as accounting support. | 10 |
| **Staff access to customer data**: log who, system, IP, date, time and data viewed; keep **12 months**. **Mask production data** in dev/test environments. | Audit service also logs back-office access. Data masking in non-production. | 10, 12 |
| 24/7 channel for **reporting emergencies and blocking** channels | Integration point (call center → identity / channel block API). | 4 |

### 2.2 Cloud and outsourcing (R1, third-party services section)

| Requirement | Architecture response | Step |
| --- | --- | --- |
| **Inform the SB** of cloud services supporting critical processes: service type, architecture, real-time elasticity, and a risk analysis (operational, legal, technological, security, continuity) with controls | The PDF's architecture and risk sections are effectively that dossier. | 3, 18 |
| Cloud data centres (primary and alternate) built to **TIA-942** and certified **Tier III** or equivalent | Hyperscaler regions meet this. Cite the provider's attestations. | 3 |
| Cloud provider certified **ISO 27001**, with **ISO 27017** (cloud security) and **ISO 27018** (personal data in the cloud) controls | AWS and Azure both hold these. Cite them in the cloud ADR. | 3 |
| **Independent annual security audit** of the cloud service | SOC 2 Type II / ISO audit reports from the provider (AWS Artifact / Microsoft Service Trust Portal). | 3 |
| Contract clauses: data used **only for the contracted purpose**, delivery of reports and certifications, **secure deletion** of data | Provider contract terms + the bank's own key management (BYOK) so deletion can be guaranteed. | 3, 12 |
| **Alternate providers** for critical services, or a tested annual continuity plan for single providers | Supports **2 notification providers**, multi-AZ and multi-region, and avoiding lock-in where it matters. | 8, 11, 13 |
| Running critical processes **abroad**: notify the SB, with an annual independent audit | As far as I know, Ecuador has no AWS or Azure region (confirm in Step 3), so hosting abroad is very likely unavoidable. Plan for this notification. | 3 |
| Primary and alternate processing sites **not exposed to the same risks** | DR in a **different region**, not just a different availability zone. | 13 |
| Isolated **development, test and production** environments | Separate accounts or subscriptions per environment. | 15 |

### 2.3 Business continuity and incidents (R1, R5)

| Requirement | Architecture response | Step |
| --- | --- | --- |
| A business continuity management system with **RTO and RPO defined per critical process**, a continuity plan, **annual tests**, and a remote recovery site | Your A-07 / A-08 targets + the DR strategy + DR drills (and chaos testing). | 13 |
| **Notify the SB of any incident affecting critical services**. Formal report within **5 days**, **root-cause report within 10 days** (SB-2024-02855). | Observability + incident management runbooks. Audit and traces must support root-cause analysis. | 14, 15 |
| **Personal data breach**: processor → controller within **2 days**; controller → SPDP within **5 days**; notify affected data subjects. Not notifying is a **serious infringement**. (SPDP-SPD-2026-0040-R) | Breach detection (SIEM), data classification so impact can be assessed fast, and a contract clause with every provider. | 12, 14 |
| Reference standards adopted by the norm: **ISO 27000 series, ISO 22301, COBIT 2019** | Name them in the PDF as the security, continuity and governance frameworks. | 12, 13 |

### 2.4 Personal and biometric data (R3, R4, R6)

| Requirement | Architecture response | Step |
| --- | --- | --- |
| Biometric data that can uniquely identify someone is **sensitive data** | Separate, encrypted store. Minimal access. | 7, 9 |
| A **DPIA** (data protection impact assessment) before deploying biometrics, **updated every 12 months** | Mention it as a governance prerequisite of the onboarding design. | 7 |
| **Explicit consent** when consent is the legal basis | A consent screen in onboarding, with the consent record kept in the audit trail. | 7, 10 |
| Offer an **equivalent non-biometric alternative** (unless the DPIA shows none exists) | Username + password + OTP login always available, plus assisted or branch onboarding as an alternative to facial recognition. | 6, 7 |
| **Prefer biometric templates over raw images**; privacy by design and default; no secondary use | Store templates or vendor references, not selfies. Delete raw images after verification. | 7 |
| **No decisions with legal effects based solely on automated biometric identification** | Manual review queue for rejected or borderline onboarding cases. | 7 |
| **Biometric identification of minors is prohibited** except narrow cases; ages 15–17 can consent themselves | Age check during onboarding. | 7 |
| Existing biometric systems must adapt within **12 months** of the rule's publication | Mention it in the regulatory section. | 2 |
| A cloud provider acting as a **processor (encargado)** is **not an international transfer**, even outside Ecuador (SPDP clarification). A **data processing contract** is still required. | Hosting in a foreign cloud region is allowed, with a processing contract. | 3 |
| True transfers to third parties abroad need an **adequate-level country** or **guarantees** (standard contractual clauses, binding corporate rules, certifications) | Relevant if the biometric or KYC vendor processes data as an independent controller. Check the vendor's role. | 7 |
| Data protection officer (DPO) and records of processing | Governance. Mention it. | 2 |

### 2.5 Anti-money laundering and KYC (R7)

> **AML** = Anti-Money Laundering (*Prevención de Lavado de Activos*): the laws and controls that stop illegal money from entering the financial system. **KYC** = Know Your Customer (*Conozca a su Cliente*): verifying a customer's identity before and during the relationship. **UAFE** = Unidad de Análisis Financiero y Económico, the Ecuadorian AML authority.

| Requirement | Architecture response | Step |
| --- | --- | --- |
| **Customer due diligence (KYC)** before opening an account | The onboarding flow: ID document + face match + liveness + check against the civil registry. | 7 |
| **Transaction monitoring** and **suspicious transaction reporting** to the UAFE | Transfer events published to a monitoring and AML consumer. | 8 |
| **Record retention**, reported as **≥ 10 years** for due-diligence and transaction records (*verify in the official text*) | Audit and KYC archive retention of 10 years in WORM storage. | 10 |

### 2.6 Interbank payments (R8)

| Requirement | Architecture response | Step |
| --- | --- | --- |
| Interbank transfers go through the **BCE's SPI**. Technical norm v2 (Mar 2026) adds originator data fields. | The transfer service has a **SPI adapter** (anti-corruption layer). | 8 |
| A **real-time payments** scheme with its own **messaging standard** (BCE-GG-007-2026), initially capped at **one basic salary** per payment | Two paths: **instant** (small amounts, synchronous status) and **batch/deferred SPI** (larger amounts, asynchronous status). Supports FR-13 (status tracking). | 8 |

---

## 3. International standards and frameworks to reference

| Standard | Use in the proposal |
| --- | --- |
| **ISO/IEC 27001 / 27002** | Information security management (required by the SB norm). |
| **ISO/IEC 27017 / 27018** | Cloud security and personal data in the cloud (required of the cloud provider). |
| **ISO 22301** | Business continuity management. |
| **COBIT 2019** | IT governance. |
| **NIST Cybersecurity Framework 2.0** | Structure for the security section (Govern, Identify, Protect, Detect, Respond, Recover). |
| **OWASP ASVS, API Security Top 10, MASVS** | Web, API and mobile security requirements. |
| **OpenID FAPI 2.0** | Financial-grade OAuth profile for authentication and API security. |
| **FIDO2 / WebAuthn (passkeys)** | Phishing-resistant biometric login. |
| **ISO/IEC 30107-3** | Liveness / presentation attack detection for facial recognition. |
| **ISO 20022** | Payment messaging (check if the BCE real-time standard is based on it). |
| **SOC 2 Type II, CSA STAR** | Provider assurance reports. |
| **TIA-942 / Uptime Tier III** | Data-centre requirements in the SB norm. |

---

## 4. Explicitly out of scope

- **PCI DSS**: no card data is stored, processed or transmitted. If cards are added later, isolate them in a separate PCI scope (tokenization).
- **Card-specific SB rules**: chip cards, enabling or disabling card networks, ATM and POS rules.
- **Fintech law** (Ley Orgánica para el Desarrollo, Regulación y Control de los Servicios Financieros Tecnológicos, 2022): relevant only if BP exposes open-finance APIs to third parties. Mention it as a future extension (DEUNA, A-15).

---

## 5. Changes this step makes to Step 0

| Item | Update |
| --- | --- |
| FR-09 | Notifications must go by **mobile messaging and email simultaneously**. That's the legal basis for the 2 channels. Also notify on **every e-banking login**. |
| FR-14 | Beneficiaries ("favourite accounts") and **customer-defined maximum amounts** are **regulatory requirements**, not just features. |
| FR-15 | Step-up with **2 of 3 factors** is required for transfers to **unregistered accounts**. |
| New FR | **Device binding**: mobile transactions only from authorized devices. |
| New FR | **Real-time transaction risk scoring** (allow or reject + notify). |
| A-09 | Audit retention: **12 months online minimum** (SB), **10 years archive** (AML, to verify). |
| A-13 | Interbank transfers: **BCE SPI** (deferred) + **real-time payments** (instant, capped). |
| C-08 | Cloud hosting abroad is permitted: inform the SB, with an annual independent audit, ISO 27001/27017/27018 and Tier III providers, and a data processing contract under the LOPDP. |

---

## 6. Sources

### Official texts

- [Resolution SB-2021-2126: Norma de control para la gestión del riesgo operativo](https://alertas-v3.directoriolegislativo.org/wp-content/uploads/2021/12/resol-SB-2021-2126-1.pdf) (read for this step; superseded in 2023, so verify against the current version)
- [Resolution SB-2024-02855: reform of the operational-risk norm (incident reporting)](https://asobanca.org.ec/wp-content/uploads/2024/10/Res.-No.-SB-2024-02855-Reforma-la-Norma-de-control-para-la-gestion-del-riesgo-operativo.pdf)
- [Compliance schedule for SB-2021-2126 (Asobanca)](https://asobanca.org.ec/wp-content/uploads/2022/05/Cronograma-plazos-cumplimiento-Norma-Riesgo-Operativo-Res.-Nro.-SB-2021-2126.pdf)
- [Circular SB-INRE-2022-0021-C: security of electronic channels](https://asobanca.org.ec/wp-content/uploads/2022/10/Circular-SB-INRE-2022-0021.-Revision-y-analisis-de-la-seguirad-de-la-informacion-para-las-actividades-financieras-en-canales-electronicos.pdf)
- [Resolution SB-2023-2208: financial users](https://asobanca.org.ec/wp-content/uploads/2023/11/Resolucion-SB-2023-2208-usuarios-financieros.pdf)
- [Código Orgánico Monetario y Financiero](https://www.cosede.gob.ec/wp-content/uploads/2018/08/COMF.pdf)
- [Anti-money-laundering law (2024)](https://ec.andersen.com/wp-content/uploads/2024/09/LEY-ORGANICA-DE-PREVENCION-DETECCION-Y-COMBATE-DEL-DELITO-DE-LAVADO-DE-ACTIVOS-Y-DE-LA-FINANCIACION-DE-OTROS-DELITOS-2.pdf)
- [BCE circular: SPI technical norm v2 (Mar 2026)](https://asobanca.org.ec/wp-content/uploads/2026/03/Circular-BCE-GMPSN-2026-008-C-Cambio-SPI-LAFT.pdf)
- [Res. BCE-GG-007-2026: real-time payment messaging standard](https://asobanca.org.ec/wp-content/uploads/2026/03/RO-Res.-BCE-GG-007-2026-Estandar-mensajeria-transferencias-electronicas-pago-tiempo-real.pdf)
- [Banco Pichincha personal data protection policy](https://www.pichincha.com/sites/default/files/documents/2026-07/politica-general-proteccion-datos-personales-banco-pichincha.pdf)

### Secondary sources (law firms and press)

- [Meythaler & Zambrano: four new SPDP resolutions (biometrics, breaches, AI)](https://www.meythalerzambranoabogados.com/post/nuevas-reglas-de-protecci%C3%B3n-de-datos-en-ecuador-ia-biometr%C3%ADa-denuncias-y-brechas-de-seguridad)
- [NMS Law: SPDP norm on national and international transfers](https://nmslaw.com.ec/?p=16044)
- [NMS Law: a processor outside Ecuador is not a transfer](https://nmslaw.com.ec/?p=16373)
- [LexLatin: Ecuador regulates personal data transfers](https://lexlatin.com/entrevistas/ecuador-regula-transferencias-datos-personales-riesgo-fuga-datos)
- [Primicias: AML law in force](https://www.primicias.ec/politica/ley-lavado-activos-vigencia-asamblea-nacional-ecuador-101796/)
- [Vistazo: new AML regulation 2026](https://www.vistazo.com/2026-01-31-ecuador-lavado-de-activos-nuevo-reglamento-plan-uafe-MB10662619)
- [Ecuador AML compliance guide (10-year retention claim)](https://cuencalawyer.pages.dev/my-blog/blog/corporate-business-law/ecuador-aml-compliance-a-step-by-step-guide-for-financial-real-estate-businesses)
- [Primicias: interbank transfers must be immediate](https://primicias.ec/economia/transferencias-bancarias-ecuador-resolucion-junta-monetaria-banco-central-87660)
- [Bloomberg Línea: immediate transfers 7 days a week](https://www.bloomberglinea.com/latinoamerica/ecuador/transferencias-bancarias-en-ecuador-seran-inmediatas-los-7-dias-de-la-semana-desde-cuando/)

---

## Step 2 checklist

- [x] Applicable norms identified (SB, COMF, LOPDP + SPDP, UAFE, BCE)
- [x] Requirements mapped to architecture responses and roadmap steps
- [x] Cloud hosting abroad confirmed as possible, with conditions
- [x] International standards listed
- [x] PCI DSS excluded with justification
- [ ] **Your review:** check the current SB codified text (post-2023) for article numbers
- [ ] **Your review:** confirm AML record retention (10 years) in the official law text
- [x] Apply the section 5 updates to [00-step0.md](00-step0.md)

---

## Update (8 Nov 2026): additions after cross-review

| Ref | Norm | What it adds | Design response |
| --- | --- | --- | --- |
| R11 | **Ley Orgánica para el Fortalecimiento de la Ciberseguridad** (Registro Oficial No. 290, Fifth Supplement, 22 May 2026) | Cybersecurity frameworks, incident response and reporting; enables controlled ethical hacking for critical digital infrastructure; reforms LOPDP art. 43 (breach notification adds a third recipient); national minimum cybersecurity standards and an incident regulation to follow | Incident runbooks with regulator notification, SIEM / SOC, annual pentest and red-team exercises (Step 12) |
| R12 | **JPRF codification** (Junta de Política y Regulación Financiera y Monetaria): technology and third-party risk provisions — *exact articles to confirm* | Supplier due diligence, audit rights, exit plan, third-party risk register | Vendor due diligence (SOC 2, ISO 27001), audit clauses, **exit plan and portable design** (Kubernetes, Kafka, OpenTelemetry, Terraform), third-party risk register |
| — | LOPDP governance | **Data Protection Officer (DPO)** and records of processing | DPO named in the governance section; processing register covers cloud, eKYC, SMS and email processors |

**International data transfer (position).** The SPDP's 2026 norm on national and international transfers treats a cloud provider acting as **processor** as *not* an international transfer (row 88 above). An earlier analysis treated foreign hosting as an international transfer requiring consent, contract clauses and registration. **Position taken:** follow the 2026 norm, but apply the stricter safeguards anyway — a data processing agreement with standard-contract-style clauses, bank-managed encryption keys (KMS / CloudHSM), entry in the processing register, and a privacy notice that discloses hosting abroad. **Fallback** if Legal requires it: a hybrid option keeping the most sensitive data (biometric evidence, KYC documents) in Ecuador. Owner: Legal / DPO.

Sources: [El Diario: law in force (22 May 2026)](https://www.eldiario.ec/ecuador/en-vigencia-la-ley-organica-para-el-fortalecimiento-de-la-ciberseguridad-22052026/), [NMS Law: cybersecurity law in force](https://nmslaw.com.ec/blog/2026/06/01/ecuador-ley-organica-fortalecimiento-ciberseguridad/), [LEXIS: Registro Oficial](https://www.lexis.com.ec/noticias/registro-oficial-del-dia-ley-organica-para-el-fortalecimiento-de-la-ciberseguridad).
