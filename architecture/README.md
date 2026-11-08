# C4 model: BP Internet Banking

The whole model lives in one Structurizr DSL file, [workspace.dsl](workspace.dsl). Every view below is generated from it, so diagrams can't contradict each other (ADR-001). Rendered images are in [.structurizr/1/images/](.structurizr/1/images/) as high-resolution PNG, SVG and a separate legend (`<view>-key.png`).

## Views

| View key | C4 type | Audience | What it shows |
| --- | --- | --- | --- |
| `01-Context` | System context (level 1) | Business, product owners | Customers, staff, the system, BP internal systems and external services. No technology. |
| `02-Containers` | Containers (level 2) | Technical leads | Reference view with every container (large; use the focused views) |
| `02a-Containers-Channels` | Containers | Technical leads | Web, mobile and back-office apps, edge, API Gateway, BFFs, identity |
| `02b-Containers-Payments` | Containers | Technical leads | Transfers, limits, risk, Core and interbank integration |
| `02c-Containers-Data` | Containers | Technical leads | Frequent-client persistence, CQRS read model, Core CDC, adapters |
| `02d-Containers-Onboarding` | Containers | Technical leads | eKYC vendor, Registro Civil, AML screening, account opening, device binding, back-office review |
| `02e-Containers-Notifications-Audit` | Containers | Technical leads | Notifications with provider failover; immutable audit; back-office queries |
| `03-Components-Gateway` | Components (level 3) | Engineers, security | Kong plugin chain: rate limit → JWT → DPoP → route policy → revocation → router → access log |
| `03-Components-Transfer` | Components | Engineers | Layers: API (authorization, step-up, idempotency, operations API) → business (Saga, compensation, reconciliation) → integration and data (outbox, clients) |
| `03-Components-Onboarding` | Components | Engineers, compliance | Layers: API (attestation, signed webhook, four-eyes review) → business (state machine, decision engine) → integration (vendor, registry, screening, account, IdP provisioning) |
| `03-Components-Accounts` | Components | Engineers | Frequent-client persistence: cache-aside, refresh-ahead, event-driven invalidation and classification |
| `03-Components-Notification` | Components | Engineers | Policy, templates, priority lanes, SMS failover, delivery tracking |
| `03-Components-Audit` | Components | Engineers, compliance | Ingestion (validate, tokenize, hash-chain) → storage (WORM archive, hot index) → query and integrity |
| `04-Deployment-Production` | Deployment | Architects, operations, security | us-east-1 primary (3 AZs), us-east-2 warm standby, replication, Direct Connect, on-premises systems |
| `05-Dynamic-Login-Web` | Dynamic | Everyone | Web login: Code + PKCE + PAR through the Web BFF |
| `05-Dynamic-Login-Biometric` | Dynamic | Everyone | Mobile biometric login with a device-bound DPoP key; pre-built dashboard |
| `05-Dynamic-Onboarding` | Dynamic | Everyone | Onboarding Saga with facial recognition |
| `05-Dynamic-Transfer-Interbank` | Dynamic | Everyone | Interbank transfer: debit, pacs.008, pacs.002, notifications, audit |

The code level (C4 level 4) is not drawn: the exercise asks for components. A system landscape view isn't needed because the design covers one system.

## C4 practices applied

- **One level per diagram.** Container views hold no regions, zones or clusters; those live only in the deployment view.
- **Infrastructure is not modelled as containers, with two justified exceptions.** The **API Gateway** is a container because the statement mandates an integration layer with a gateway, and its policies are part of the design in every environment. The **Edge (CDN + WAF)** is shown because it serves the SPA and is the first security boundary.
- **One container per component view.** Components are grouped in **layers** (API → business → integration and data), and each view excludes unrelated container-to-container arrows so only that container's interactions remain.
- **Focused container views.** The full container view is kept as a reference; five focused views of the same model are used in the PDF.
- **Dynamic views** show runtime order with numbered interactions instead of guessing it from static diagrams.
- **Every element** has a name, a type, a technology where relevant and a one-sentence description; **every arrow** has a purpose and, where relevant, a protocol. Each view has a title, a description of who it is for, and a legend.
- **No technology in the context view.**
- **Deployment view:** one representative element per platform service; node descriptions list everything deployed there. Service-to-service calls are shown in the container views.

## Colour and line conventions

| Element | Colour / shape |
| --- | --- |
| People | Dark blue person |
| Staff | Slate blue person |
| System in scope | Blue |
| BP internal systems (existing) | Grey-blue with thick border |
| External systems | Grey |
| Containers | Mid blue; apps as browser / phone shapes |
| API Gateway, Edge | Hexagons |
| Databases | Green cylinders; cache: orange cylinder; event broker: purple pipe |
| Components | Light blue |
| Standby (DR) deployment nodes | Red dashed border |
| Synchronous call | Solid line |
| Asynchronous event | Dashed line (tag `Async`) |

## Render and export

```bash
# Git Bash, from the repo root
MSYS_NO_PATHCONV=1 docker run -it --rm -p 8080:8080 -v "$(pwd -W)/architecture:/usr/local/structurizr" structurizr/structurizr local
# validate only
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W)/architecture:/usr/local/structurizr" structurizr/structurizr validate -workspace /usr/local/structurizr/workspace.dsl
```

Open <http://localhost:8080>, choose a view and export PNG / SVG (with the legend).
