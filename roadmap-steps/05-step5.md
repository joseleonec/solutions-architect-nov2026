# Step 5: Front-end and mobile architecture

**Inputs:** Step 0 (C-01 two front-ends, FR-01/02/03/15, A-14 90% mobile / 10% web, QAS-06/10), Step 2 (authorized devices only, anti-tampering, biometric data rules, non-biometric alternative), Step 3 (CloudFront edge), Step 4 (Web BFF, Mobile BFF, API Gateway).

---

## 1. Front-end container design

```text
 Browser                                        Mobile device
 ┌─────────────────────┐                         ┌──────────────────────────────┐
 │ Web App (SPA)       │                         │ Mobile App (Flutter)         │
 │ Angular             │                         │ RASP · attestation · pinning │
 │ no tokens in JS     │                         │ keys in Secure Enclave /     │
 └─────────┬───────────┘                         │ StrongBox                    │
           │ HTTPS, HttpOnly session cookie      └──────────────┬───────────────┘
           ▼                                                    │ HTTPS + pinning,
 ┌─────────────────────────────────────────────────┐            │ sender-constrained token
 │ CloudFront + AWS WAF + Shield                   │◄───────────┘
 │  /            → S3 (static SPA, Origin Access)  │
 │  /bff/web/*   → Web BFF                         │
 │  /bff/mobile/*→ Mobile BFF                      │
 └─────────┬───────────────────────┬───────────────┘
           ▼                       ▼
     Web BFF (confidential      Mobile BFF (screen-shaped APIs,
     OAuth client, token        device context, app version checks)
     handler)                          │
           └──────────┬────────────────┘
                      ▼
                 API Gateway → domain services (Step 4)
```

| Container | Technology | Responsibility | Tier |
| --- | --- | --- | --- |
| **Web App (SPA)** | Angular, TypeScript, served from S3 via CloudFront | Customer web banking UI. Holds **no tokens**: calls only its own BFF with a session cookie. | T1 |
| **Mobile App** | Flutter (iOS + Android) | Mobile banking UI, onboarding with the biometric vendor SDK, biometric login, device binding. | T1 |
| **Web BFF** | Container service (stack chosen in Step 8) | **Token handler**: runs the OAuth code flow as a confidential client, keeps tokens server-side, issues an HttpOnly cookie, aggregates calls for web screens. | T1 |
| **Mobile BFF** | Container service | Screen-shaped responses, device and app-version context, minimum-version enforcement, feature flags. | T1 |
| **Static hosting** | S3 (private, Origin Access Control) + CloudFront + WAF | Serves the SPA bundle close to users; TLS terminated at the edge (Step 3). | T1 |

**One BFF per channel** was already chosen in Step 4. The reason is that the two channels have different security models. The web BFF must keep tokens away from the browser. The mobile app is a native public client that holds its own sender-constrained token. A shared BFF would mix both models and couple release cycles (Sam Newman's original BFF argument: one experience, one backend).

---

## 2. ADR-005: SPA framework

**Status:** Proposed

**Context.** The SPA serves ~10% of digital traffic (A-14) but is required by the statement. It's forms-heavy (transfers, beneficiaries, limits, onboarding fallbacks), must be secure by default against XSS, and will be maintained for years by bank teams.

### Options compared

| Criterion | Weight | Angular | React | Vue |
| --- | --- | --- | --- | --- |
| Built-in structure for large, forms-heavy apps (router, forms, HTTP, DI) | 25% | 5 | 3 | 4 |
| Security defaults (auto-escaping, sanitization, Trusted Types, CSP) | 20% | 5 | 4 | 4 |
| Long-term support and predictable upgrades | 15% | 5 | 4 | 4 |
| Talent availability | 15% | 4 | 5 | 3 |
| Ecosystem and libraries | 10% | 4 | 5 | 4 |
| Bundle size and runtime performance | 10% | 4 | 4 | 5 |
| Accessibility tooling | 5% | 5 | 4 | 4 |
| **Weighted total** | 100% | **4.65** | **4.00** | **3.95** |

**Decision:** **Angular.**

### Justifications

1. **Opinionated, complete framework.** Routing, reactive forms with validation, HTTP interceptors and dependency injection are built in. Every team builds features the same way, which matters for a bank with several squads and long maintenance horizons. React would need a set of third-party choices (router, forms, state, data fetching) that each team could make differently.
2. **Secure by default.** Angular treats all values as untrusted and sanitizes them before they reach the DOM, and it supports a strict **Content Security Policy** and **Trusted Types**. XSS is the main threat to a banking SPA, so defaults that are hard to bypass reduce risk.
3. **Predictable release cadence.** A major version every ~6 months, with **18 months of support** per major (6 active + 12 LTS). Upgrades can be planned, and `ng update` automates most migrations.

**Trade-offs.** React has a larger talent pool and ecosystem. If the bank's existing web teams are React-based, React with a fixed reference stack (React Router, React Hook Form, TanStack Query) is a valid alternative. Choosing Flutter for mobile (ADR-006) removes the "share code with React Native" argument for React.

---

## 3. ADR-006: Mobile multiplatform framework

**Status:** Proposed

**Context.** The mobile app is the main channel (~90% of digital traffic, 5.2 M users). It needs facial-recognition onboarding with a vendor SDK, biometric login, device binding, strong anti-tampering (Step 2), and a responsive UI on low-end Android devices common in Ecuador. The statement requires comparing **two** multiplatform frameworks.

### Options compared

| Criterion | Weight | Flutter | React Native |
| --- | --- | --- | --- |
| Security: tamper resistance and RASP / attestation support | 20% | 5 | 4 |
| Biometrics and secure hardware (Keychain / Keystore, Secure Enclave / StrongBox) | 15% | 4 | 4 |
| Performance and UI consistency (including low-end Android) | 15% | 5 | 4 |
| Banking and fintech adoption | 15% | 4 | 4 |
| Talent and team skills in Ecuador | 15% | 3 | 4 |
| KYC / biometric vendor SDK availability | 10% | 4 | 4 |
| Ecosystem maturity and long-term backing | 10% | 4 | 4 |
| **Weighted total** | 100% | **4.20** | **4.00** |

Notes on the scores:

- **Tamper resistance.** Flutter release builds compile Dart **ahead of time to native ARM code**, and support `--obfuscate`. React Native ships a JavaScript bundle; Hermes compiles it to bytecode, which is harder to read than plain JS but still easier to decompile than native code. Both have commercial RASP SDKs (Talsec, Promon, Guardsquare) and can call Play Integrity / App Attest.
- **Performance.** Flutter draws every pixel with its own engine (Impeller), so the UI looks and behaves the same on every device. React Native's New Architecture (the only runtime since 0.82) and Hermes V1 as default (0.84, Feb 2026) closed much of the gap, but it still renders through native views, so UI differs by platform.
- **Adoption.** Nubank, the largest digital bank in Latin America, publicly moved to Flutter to scale mobile development. React Native is also used by large fintechs (e.g., Coinbase). Treat market-share figures from vendor blogs with caution.
- **Talent.** JavaScript/TypeScript developers are easier to find, so React Native scores higher. Flutter's learning curve for Dart is short, and the bank can train its teams.

**Decision:** **Flutter.**

### Justifications

1. **Stronger default protection of the app binary.** Native AOT code plus obfuscation raises the cost of reverse engineering and tampering. That's a direct requirement in Step 2 (anti-malware and anti-tampering on channels) and in OWASP MASVS-RESILIENCE.
2. **Consistent, fast UI on every device.** One rendering engine means one visual behaviour to design, test and make accessible on both iOS and Android, including the low-end Android phones many customers use. Fewer platform-specific UI bugs means fewer incidents, which matters after the 2025 app outages.
3. **Proven in Latin American banking at scale.** Nubank's case shows Flutter can carry a bank-scale app with many squads working on the same codebase.

**Trade-offs.** Smaller hiring pool than React Native. Vendor SDKs (biometrics, RASP) are often native-first, so some need a thin Flutter plugin (platform channel). Budget for that in the onboarding work.

---

## 4. Token handling in the browser (SPA)

Follows the IETF *OAuth 2.0 for Browser-Based Applications* Best Current Practice, which ranks the **Backend for Frontend (BFF)** pattern as the most secure architecture for browser apps. The details of the OAuth flow are in Step 6.

| Rule | Implementation |
| --- | --- |
| No access or refresh tokens in the browser | The Web BFF is a **confidential client**. It runs Authorization Code + PKCE and keeps tokens server-side (encrypted cache). |
| Session cookie | `__Host-` prefix, `HttpOnly`, `Secure`, `SameSite=Strict`, short idle timeout (e.g. 5 min) and an absolute timeout. |
| CSRF | `SameSite=Strict`, plus a custom request header checked by the BFF on every state-changing call. |
| XSS | Angular sanitization, strict **CSP** (no inline scripts, nonces), **Trusted Types**, Subresource Integrity on any external script (ideally none). |
| Security headers | HSTS (preload), `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, `frame-ancestors 'none'` (anti-clickjacking). Set as a CloudFront response-headers policy. |
| Step-up for sensitive actions | The BFF triggers re-authentication with a higher assurance level (OTP or passkey) for transfers to new beneficiaries and limit changes (FR-15). |

---

## 5. Mobile security architecture

Target: **OWASP MASVS v2** verified with the **MAS-L2 + R** testing profile (sensitive data and money movement, plus resilience against reverse engineering).

| Control | MASVS area | Implementation |
| --- | --- | --- |
| **Secure storage** | STORAGE, CRYPTO | Secrets only in **iOS Keychain / Android Keystore**, with keys generated in **Secure Enclave / StrongBox**. No tokens or personal data in plain files or logs. |
| **Device binding** (Step 2: authorized devices only) | AUTH | At onboarding or first login on a new device, the app generates a **non-exportable key pair** in secure hardware and registers the public key with the Device service. Sensitive requests are signed with it. Details in Step 6. |
| **Biometric login** (FR-03) | AUTH | Native biometrics (Face ID / fingerprint) **unlock the device key**; biometric data never leaves the device. Username + password + OTP is always available as the non-biometric alternative (LOPDP biometric rule). |
| **App and device attestation** | RESILIENCE | **Play Integrity API** (Android) and **App Attest** (iOS). The verdict is checked **server-side** by the Mobile BFF / Device service, never trusted only on the device. |
| **RASP** | RESILIENCE | Commercial RASP SDK: root/jailbreak, hooking (Frida), debugger, emulator, repackaging, overlay and screen-recording detection. Signals are sent to **Risk Scoring** (Step 4), which decides: allow, step-up or block. |
| **Obfuscation** | RESILIENCE | `flutter build --obfuscate --split-debug-info`, plus the RASP vendor's native hardening. |
| **Network** | NETWORK | TLS 1.2+ (prefer 1.3), **public-key pinning** with a backup pin and remote pin update, no cleartext traffic. |
| **Sensitive screens** | PLATFORM | Block screenshots and screen recording, hide content in the app switcher, disable clipboard on account numbers and OTP fields. |
| **Code and supply chain** | CODE | Dependency scanning, signed builds, minimum OS version, **forced update** when the Mobile BFF reports a version below the minimum. |
| **Independent testing** | — | Annual penetration test (Step 2) plus MASVS verification before major releases. |

> **Why commercial RASP rather than only free SDKs:** free tools such as freeRASP are a good start, but a bank needs support SLAs, regular updates for new rooting/hooking tools, and evidence for the SB. Detection must feed **server-side** decisions: client-side checks alone can be bypassed.

---

## 6. Onboarding with facial recognition (front-end view)

Full flow in Step 7. Front-end responsibilities only:

1. The app embeds the **vendor's native biometric SDK** (document capture, selfie, liveness) through a Flutter plugin.
2. The SDK sends the capture **directly to the vendor** (or through the Onboarding service), never storing raw images on the device.
3. The app shows the **consent screen** required by the LOPDP biometric rule before any capture, and offers **assisted / branch onboarding** as the alternative.
4. On success, the app performs **device binding** (section 5) and enrolls biometric login.

---

## 7. Micro-frontends: not adopted

| Question | Answer |
| --- | --- |
| How many teams work on the web channel? | Few. The web is ~10% of traffic and mostly mirrors mobile journeys. |
| Do parts of the UI need independent deployment? | No strong need in the first release. |
| Cost of micro-frontends | Several builds and runtimes, duplicated dependencies, harder shared security headers and session handling, more complex testing. |

**Decision:** one **modular SPA** with lazy-loaded feature areas (accounts, movements, transfers, beneficiaries, profile) in an **Nx monorepo** with enforced module boundaries. The same feature split is used in the Flutter app (feature packages). **Revisit** if more than ~3 independent teams start delivering web features in parallel.

---

## 8. Other front-end decisions

| Topic | Decision | Requirement |
| --- | --- | --- |
| **Fast dashboard for frequent clients** | The Mobile BFF returns one aggregated dashboard payload served from cache (Step 9). The app keeps the last dashboard **encrypted** on the device and shows it immediately, marked "as of hh:mm", while refreshing. | FR-11, QAS-06, QAS-03 |
| **Idempotency** | The app generates an **idempotency key** per transfer attempt and reuses it on retries. | QAS-05 |
| **Async transfer status** | Push notification (FCM / APNs) plus a status screen that polls the BFF. Push supplements the regulatory SMS + email channels; it does not replace them. | FR-09, FR-13 |
| **Accessibility** | WCAG 2.2 AA on web; Flutter Semantics on mobile. Banco Pichincha has already worked with visually impaired customers on its app, so this is an existing commitment. | Inclusion |
| **Observability** | Real-user monitoring and crash reporting in both apps, with the same **correlation ID** sent to the BFF so a customer-reported error can be traced end to end (Step 14). No personal data in client logs. | QAS-13 |
| **Feature flags and kill switch** | Served by the Mobile BFF, so a failing feature can be disabled without a store release. | Operational excellence |
| **Release** | CI/CD with automated tests, signing and staged rollouts (Play staged rollout, App Store phased release). | NFR-06 |

---

## 9. Structurizr model changes (applied in Step 17)

```text
spa       = container "Web App (SPA)"  "Customer web banking UI. Holds no tokens." "Angular / TypeScript" "WebApp"
mobile    = container "Mobile App"     "Mobile banking, onboarding and biometric login." "Flutter" "MobileApp"
webBff    = container "Web BFF"        "Token handler and API aggregation for the SPA." "<Step 8>"
mobileBff = container "Mobile BFF"     "Screen-shaped APIs, device context, version checks." "<Step 8>"

customer -> spa      "Uses" "HTTPS"
customer -> mobile   "Uses"
spa      -> webBff   "Calls" "HTTPS / session cookie"
mobile   -> mobileBff "Calls" "HTTPS / pinned TLS, sender-constrained token"
mobile   -> biometrics "Captures document, selfie and liveness with" "Vendor SDK / HTTPS"
```

---

## 10. Sources

- [IETF: OAuth 2.0 for Browser-Based Applications (draft-26, Dec 2025, BCP; BFF in section 6.1)](https://www.ietf.org/archive/id/draft-ietf-oauth-browser-based-apps-26.html). Datatracker shows it as published as an RFC; check the final number before citing it.
- [Angular: security guide](https://angular.dev/best-practices/security)
- [Angular: release and support policy](https://angular.dev/reference/releases)
- [OWASP MAS: MASVS and MASTG](https://mas.owasp.org/)
- [Promon: MASVS-RESILIENCE and MAS profiles](https://promon.io/owasp-masvs-resilience)
- [Nubank: why we think Flutter will help us scale mobile development](https://building.nubank.com/why-we-think-flutter-will-help-us-scale-mobile-development-at-nubank/)
- [Very Good Ventures: why mobile-first fintechs bet on Flutter](https://verygood.ventures/blog/why-mobile-first-fintech-companies-are-betting-on-flutter/)
- [React Native 0.84: Hermes V1 by default (Feb 2026)](https://reactnative.dev/blog/2026/02/11/react-native-0.84)
- [Flutter: obfuscating Dart code](https://docs.flutter.dev/deployment/obfuscate)
- [Talsec freeRASP for Flutter](https://github.com/talsec/Free-RASP-Flutter)
- [Android: Play Integrity API](https://developer.android.com/google/play/integrity)
- [Apple: App Attest (DeviceCheck)](https://developer.apple.com/documentation/devicecheck)
- [Primicias: Banco Pichincha adapts its app for visually impaired customers](https://primicias.ec/noticias/economia/banco-pichincha-aplicacion-discapacidad-visual)

---

## Step 5 checklist

- [x] SPA framework compared and chosen (ADR-005: Angular)
- [x] Two mobile frameworks compared and chosen (ADR-006: Flutter vs React Native → Flutter)
- [x] SPA hosting and token handling (BFF token handler, no tokens in the browser)
- [x] One BFF per channel confirmed
- [x] Mobile security mapped to OWASP MASVS (L2 + R), RASP, attestation, pinning
- [x] Micro-frontends evaluated and rejected, with a revisit trigger
- [x] Front-end container design ready for the Step 17 diagram
- [ ] **Your review:** if you know the bank's existing web or mobile stack (job postings often show it), adjust the talent scores
- [ ] **Your review:** confirm the RFC number for the browser-based apps BCP
