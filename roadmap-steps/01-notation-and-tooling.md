# Step 1: Notation and tooling

## ADR-001: Use Structurizr DSL for the C4 diagrams

**Status:** Accepted

**Context.** The assessment requires C4 diagrams at the context, container and component levels, plus infrastructure and sequence diagrams. They must be correct, detailed and consistent with each other, and they'll be revised many times over 72 hours.

**Options considered**

| Option                    | Pros                                                                                                                                                                                                     | Cons                                                                                  |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| **Structurizr DSL** | One model generates every view, so the diagrams can't contradict each other. Text-based, so it can be versioned in Git. Created by Simon Brown, the author of C4. Supports deployment and dynamic views. | Less control over layout. Learning curve. PNG export is manual from the browser.      |
| draw.io                   | Full visual control. Fast to start. C4 shape library.                                                                                                                                                    | Each diagram is drawn separately, so they drift apart. Hard to review changes in Git. |
| PlantUML + C4-PlantUML    | Text-based. Renders from the CLI.                                                                                                                                                                        | Still one file per diagram, with no shared model. Layout is harder to control.        |
| IcePanel                  | Model-based and collaborative. Polished output.                                                                                                                                                          | SaaS, the free tier is limited, and the source can't live in the GitHub repo.         |

**Decision.** Use **Structurizr DSL**, rendered locally with the `structurizr/structurizr` Docker image (`local` mode). Structurizr Lite was discontinued in favour of this image.

**Justifications**

1. **Model-based consistency (C4 principle).** The C4 model separates the *model* from the *views*. With Structurizr each element is defined once and every view is generated from it, so a renamed service or new relationship shows up in all diagrams. This targets grading criterion 2 (quality and consistency of the diagrams).
2. **Diagrams as code (docs-as-code).** The DSL is plain text, so it lives in the same public GitHub repo as the PDF, changes can be reviewed with `git diff`, and the evaluator can inspect the source. This also shows operational excellence practices.
3. **Coverage of every required diagram in one tool.** Besides C4 levels 1–3, Structurizr has `deployment` views (infrastructure: regions, availability zones, nodes) and `dynamic` views (authentication, onboarding and transfer flows). One notation for the whole document.

**Consequences**

- Automatic layout won't always be pretty. Fix it by dragging elements in the browser (it saves the layout to `workspace.json`) or by changing `autolayout` direction.
- PNG/SVG export is done manually from the browser UI for the PDF.
- If a single diagram needs free-form drawing (for example, a cost or regulatory overview), use draw.io for that one only.

---

## Setup

### Run Structurizr locally (Docker)

> `structurizr/lite` is **discontinued**: it only prints a migration notice and exits. Use the consolidated image `structurizr/structurizr` with the `local` command ([docs](https://docs.structurizr.com/local)).

Start Docker Desktop first, then from the repo root:

**Git Bash**. `MSYS_NO_PATHCONV=1` stops Git Bash from rewriting `/usr/local/...` into a Windows path, and `pwd -W` gives a Windows path Docker understands:

```bash
MSYS_NO_PATHCONV=1 docker run -it --rm -p 8080:8080 -v "$(pwd -W)/architecture:/usr/local/structurizr" structurizr/structurizr local
```

**PowerShell**:

```powershell
docker run -it --rm -p 8080:8080 -v "${PWD}/architecture:/usr/local/structurizr" structurizr/structurizr local
```

Open [http://localhost:8080](http://localhost:8080). It reloads `architecture/workspace.dsl` whenever you refresh the page. Stop it with `Ctrl+C`.

### Validate from the command line (optional)

No output and exit code 0 means the DSL is valid. Errors print the line number.

```bash
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W)/architecture:/usr/local/structurizr" structurizr/structurizr validate -workspace /usr/local/structurizr/workspace.dsl
```

### Editor support

Install a Structurizr DSL extension for VS Code for syntax highlighting (search "Structurizr" in the Extensions panel).

### Export for the PDF

In the browser, open a view and use the export option to save **PNG** (for the PDF) or **SVG** (for zooming). Save them in `architecture/exports/` with the view key as the file name, for example `01-Context.png`.

---

## Repository layout

```text
architecture/
  workspace.dsl      # the single C4 model (source of truth)
  workspace.json     # created by Structurizr; stores manual layout. Commit it.
  exports/           # PNG/SVG images used in the PDF
  .structurizr/      # Structurizr's internal data and logs. Ignored by Git.
```

---

## Diagram style guide

| Rule                      | Convention                                                                                                                                                                                    |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| View keys                 | Numbered by level: `01-Context`, `02-Containers`, `03-Components-<container>`, `04-Deployment-<env>`, `05-Dynamic-<flow>`                                                           |
| Element names             | Business names in context views ("Core Banking"). Technical names from the container level down ("Transfer Service").                                                                         |
| Element descriptions      | One sentence: what it does, not how.                                                                                                                                                          |
| Technology                | Always set on containers and components (`"Java / Spring Boot"`, `"Redis"`).                                                                                                              |
| Relationship labels       | Verb phrase from the source's point of view + protocol: `"Sends transfer to" "HTTPS / REST"`.                                                                                               |
| Async relationships       | Tag `Async` (dashed line), and name the broker or topic in the technology.                                                                                                                  |
| Security on relationships | Show it in the technology when relevant: `"HTTPS / mTLS"`, `"OIDC + PKCE"`.                                                                                                               |
| Colours (tags)            | `InScope` dark blue = what we design. `Internal` grey-blue = BP systems we integrate with. `External` grey = third parties. `Existing` = thick border for systems that already exist. |
| Shapes                    | `WebApp` browser, `MobileApp` phone, `Database` cylinder, `Queue` pipe.                                                                                                               |
| Legend                    | Structurizr adds one automatically. Keep it in every export.                                                                                                                                  |
| Every view                | Has a title and a description that says who the diagram is for.                                                                                                                               |

---

## What's already in the model

[architecture/workspace.dsl](../architecture/workspace.dsl) contains only what the statement fixes:

- **People:** Customer, New customer.
- **System in scope:** BP Internet Banking, with no containers yet.
- **BP internal systems:** Core Banking, Complementary Customer System, Identity Provider (OAuth 2.0), Audit Store.
- **External systems:** Biometric/KYC provider, Interbank payment network, Notification providers A and B.
- **One view:** `01-Context`.

Protocols marked `TBD` are decided in later steps (8 for integration, 9 for data, 10 for audit). Containers and components are added in Steps 4–17.

---

## Step 1 checklist

- [X] Tool chosen and justified (ADR-001)
- [X] Style guide defined
- [X] Workspace skeleton created
- [X] Start Structurizr and confirm the context view renders
- [X] Commit `architecture/` to the repo
