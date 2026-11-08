# BP Internet Banking – Solution Architecture

Solution Architect practical exercise: architecture for BP's (Banco Pichincha, Ecuador) internet and mobile banking platform, documented with the C4 model.

**Author:** José Luis León · joleonca@gmail.com

## Deliverable

- **[docs/BP-Banca-por-Internet-Arquitectura.pdf](docs/BP-Banca-por-Internet-Arquitectura.pdf)**: the main deliverable, in Spanish. Executive summary, scope and business processes, regulation, C4 diagrams (context, containers, components, deployment, dynamic), detailed designs, security, resilience, monitoring, operations, cost, delivery plan and decision log.
- **[docs/BP-Internet-Banking-Solution-Architecture.pdf](docs/BP-Internet-Banking-Solution-Architecture.pdf)**: the extended English version with every design in full detail.

## Repository contents

| Path | What it holds |
| --- | --- |
| [docs/](docs/) | The PDFs and their Markdown sources |
| [architecture/workspace.dsl](architecture/workspace.dsl) | The single C4 model (Structurizr DSL); every diagram is generated from it |
| [architecture/.structurizr/1/images/](architecture/.structurizr/1/images/) | Rendered diagrams: high-resolution PNG, SVG and a legend per view |
| [architecture/README.md](architecture/README.md) | Diagram list, audiences, C4 conventions and how to render |
| [roadmap-steps/](roadmap-steps/) | Working notes per step (00–19): research, comparisons, decision records (ADR-001 … ADR-022) and sources |
| [roadmap-steps/16b-cost-validation.md](roadmap-steps/16b-cost-validation.md) | Cost lines checked against the public AWS Price List, with how to reproduce them |
| [roadmap-steps/19-delivery-plan.md](roadmap-steps/19-delivery-plan.md) | Four-stage delivery plan, go/no-go gates and technical-debt register |
| [assessment-statement.md](assessment-statement.md) | The exercise statement |
| [architecture-roadmap.md](architecture-roadmap.md) | The method followed (Steps 0–18) |

## How to read it

Start with the PDF: it is self-contained. The step notes back every decision with the alternatives evaluated, the justifications and the sources, for anyone who wants to go deeper on one topic.

## Key decisions at a glance

AWS (us-east-1 primary, us-east-2 warm standby) · microservices by bounded context behind Kong · Angular SPA with a BFF token handler · Flutter app · OAuth 2.0 Authorization Code + PKCE + PAR (FAPI 2.0, DPoP, device-bound biometric login) · eKYC vendor + Registro Civil onboarding Saga · Kafka (MSK) events with transactional outbox · CQRS + cache-aside + refresh-ahead for frequent clients · immutable audit on S3 Object Lock with hash chain · SMS + email notifications with provider failover · OpenTelemetry observability · Terraform and GitOps · staged delivery with decision gates.
