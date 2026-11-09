# Step 18: Assemble and review the PDF

## 1. Deliverable

| File | What |
| --- | --- |
| [BP-Banca-por-Internet-Arquitectura.pdf](../BP-Banca-por-Internet-Arquitectura.pdf) | **Main deliverable, Spanish** (A4, 34 pages, condensed; vector diagrams) |
| [docs/BP-Internet-Banking-Solution-Architecture.pdf](../docs/BP-Internet-Banking-Solution-Architecture.pdf) | Extended English version (A4, 52 pages, every design in full) |
| [docs/BP-Internet-Banking-Solution-Architecture.md](../docs/BP-Internet-Banking-Solution-Architecture.md) | Source of the PDF |
| [architecture/workspace.dsl](../architecture/workspace.dsl) | C4 model (single source for all diagrams) |
| `architecture/.structurizr/1/images/` | Rendered diagrams: PNG (high resolution), SVG, legend per view |
| [roadmap-steps/](.) | Detailed notes per step, with sources |

Structure follows the roadmap: executive summary → requirements and assumptions → regulation → C4 diagrams → detailed designs (front-end, auth, onboarding, integration, data, audit, notifications) → non-functionals (security, HA/DR, monitoring, operations) → cost → delivery plan → ADR log (22 ADRs) → risks → traceability.

## 2. How the PDF is rebuilt

1. Start Structurizr locally (Step 1 command) and re-export the views (PNG + SVG) after any model change.
2. Render the markdown to PDF with headless Chrome (A4, landscape pages for wide diagrams, page numbers). The Spanish PDF goes to the repository root, the English one to `docs/`. The scripts used live outside the repo; any Markdown → PDF tool works if it keeps the SVG images.

## 3. Final review against the statement

| Checklist item (statement §6) | Status | PDF section |
| --- | --- | --- |
| C4 context diagram | ✅ | 4.2 |
| C4 container diagram | ✅ (full view in repo + 5 focused views) | 4.3 |
| C4 component diagram | ✅ (6 containers) | 4.4 |
| Infrastructure diagram (AWS) | ✅ | 4.5 |
| 2 mobile frameworks, choice justified | ✅ Flutter vs React Native | 5 |
| Recommended OAuth 2.0 flow, justified | ✅ Code + PKCE + PAR, FAPI 2.0, DPoP | 6 |
| Onboarding with facial recognition in authN/authZ, tools suggested | ✅ | 6, 7, Fig. 4.6c |
| Login methods after onboarding | ✅ password + OTP, biometric (device key), passkeys (web) | 6 |
| ≥ 2 notification channels / providers | ✅ SMS + email, 2 SMS providers | 11 |
| Core and complementary system integration | ✅ | 8, 9 |
| API Gateway + base services + additional services | ✅ | 4.1, 8 |
| Audit and frequent-client persistence based on patterns | ✅ | 9, 10 |
| Regulation | ✅ | 3 |
| HA, fault tolerance, DR, security, monitoring, operational excellence, auto-healing | ✅ | 12–15 |
| Low latency and cost management | ✅ | 4.5, 9, 16 |
| ≥ 2 justifications per decision with alternatives | ✅ 22 ADRs | 17 |
| PDF uploaded to CoderPad and public GitHub repo, URL in the comment | ✅ public repo (github.com/joseleonec/solutions-architect-nov2026); ⏳ **CoderPad upload and recruiter comment: your action** | — |

All 15 grading criteria are mapped in PDF section 19.

## 4. Consistency fixes made while assembling

- Hop order unified (Edge → Gateway → BFF → services) in Steps 4, 5 and the model (Step 17).
- Audit retention: the PDF uses **12 months online + 10 years archive** (Step 2 / Step 10). The Step 2 section 5 updates (A-09, A-13, FR-09, FR-14–17, C-08) are now applied to Step 0.

## 5. Your remaining actions

- [ ] Read the PDF end to end; adjust tone or depth where you'd present differently.
- [x] Language: Spanish main deliverable + extended English version.
- [x] Cost lines checked against the AWS Price List (Step 16b). Optional: add an AWS Pricing Calculator export link.
- [ ] Verify the flagged items. Done: eKYC vendors' iBeta letters (both Level 2, Step 7), browser-apps RFC (RFC 10017, Step 5), Azure latency (Step 3), push stated as an open question (Step 11). Still open, flagged "to confirm" in the PDF: SB article numbers, 10-year UAFE retention in the 2024 law (Step 2), Registro Civil SNIC integration method (Step 7).
- [x] **Re-stage the images** before committing: the staged copies in `architecture/.structurizr/1/images/` are older than the final export (`git add architecture/.structurizr/1/images`).
- [x] Commit and push to the **public** GitHub repo.
- [ ] Upload the PDF to CoderPad; put the repo URL in the comment to the recruiter.

## 6. Update (8 Nov 2026): cross-review with the earlier assessment repo

Brought over: business-oriented executive summary and process table; four-stage delivery plan with gates, minimum resilience line and debt register (Step 19, ADR-022); onboarding component view with signed webhook, attestation, four-eyes review and `kyc_level` provisioning; Back-office Portal and staff actor; transfer compensation, reconciliation and manual-case components; cybersecurity law, JPRF third-party risk, DPO and the hosting-abroad position (Step 2); in-app / TOTP second factor with SMS as fallback and the action → assurance table (Step 6); event-driven frequent-client classifier (Step 9); component views in layers with security boundaries and "how to read it" notes; cost lines checked against the AWS Price List (Step 16b); risk owners; root and diagram READMEs; Spanish condensed PDF.
