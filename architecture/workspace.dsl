/*
 * BP Internet Banking: C4 model (Structurizr DSL)
 *
 * Run locally (from the repo root):
 *   Git Bash:   MSYS_NO_PATHCONV=1 docker run -it --rm -p 8080:8080 -v "$(pwd -W)/architecture:/usr/local/structurizr" structurizr/structurizr local
 *   PowerShell: docker run -it --rm -p 8080:8080 -v "${PWD}/architecture:/usr/local/structurizr" structurizr/structurizr local
 * Then open http://localhost:8080
 *
 * Status: skeleton. Only the elements fixed by the statement are modelled.
 * Containers and components are filled in during Steps 4-17.
 */
workspace "BP Internet Banking" "Online and mobile banking platform for Banco Pichincha (BP)." {

    !identifiers hierarchical

    model {
        // ---------- People ----------
        customer = person "Customer" "Retail banking client. Checks movements, makes transfers and payments." "Customer"
        prospect = person "New customer" "Person opening an account through mobile onboarding." "Customer"

        // ---------- The system being designed ----------
        bp = softwareSystem "BP Internet Banking" "Lets customers see their movement history and make own-account and interbank transfers and payments." "InScope" {
            // TODO (Step 4+): containers, e.g.
            // spa       = container "Web App (SPA)"    "..." "<framework>" "WebApp"
            // mobile    = container "Mobile App"       "..." "<framework>" "MobileApp"
            // gateway   = container "API Gateway"      "..." "<product>"   "Gateway"
            // ...
        }

        // ---------- Internal systems (owned by BP, not in scope) ----------
        core = softwareSystem "Core Banking" "System of record: basic customer data, products and movements." "Internal,Existing"
        customerInfo = softwareSystem "Complementary Customer System" "Provides detailed customer information when required." "Internal,Existing"
        identity = softwareSystem "Identity Provider (OAuth 2.0)" "BP's existing OAuth 2.0 / OIDC product. Authenticates users and issues tokens." "Internal,Existing"
        audit = softwareSystem "Audit Store" "Records every customer action for regulatory audit." "Internal"

        // ---------- External systems ----------
        biometrics = softwareSystem "Biometric / KYC Provider" "Facial recognition and liveness detection during onboarding." "External"
        interbank = softwareSystem "Interbank Payment Network" "National network that settles transfers to other banks." "External"
        notifyA = softwareSystem "Notification Provider A" "First notification channel (e.g. push)." "External"
        notifyB = softwareSystem "Notification Provider B" "Second notification channel (e.g. SMS / email)." "External"

        // ---------- Relationships (context level) ----------
        // Convention: "<verb phrase>" "<protocol>"
        customer -> bp "Checks movements, makes transfers and payments using" "HTTPS"
        prospect -> bp "Opens an account with facial recognition using" "HTTPS"

        bp -> identity "Authenticates users and validates tokens with" "OIDC / OAuth 2.0"
        bp -> core "Reads customer data and movements; posts transfers to" "TBD"
        bp -> customerInfo "Reads detailed customer data from" "TBD"
        bp -> biometrics "Verifies identity and liveness with" "HTTPS"
        bp -> interbank "Sends interbank transfers to" "TBD"
        bp -> notifyA "Sends movement notifications through" "HTTPS"
        bp -> notifyB "Sends movement notifications through" "HTTPS"
        bp -> audit "Records customer actions in" "TBD"

        notifyA -> customer "Notifies"
        notifyB -> customer "Notifies"
    }

    views {
        systemContext bp "01-Context" "System context: for non-technical stakeholders." {
            include *
            autolayout lr
        }

        // TODO (Step 17):
        // container bp "02-Containers" { include * autolayout lr }
        // component bp.<container> "03-Components-<name>" { include * autolayout lr }
        // dynamic ... (authentication, onboarding, transfer sequences)
        // deployment ... (cloud infrastructure)

        styles {
            element "Element" {
                fontSize 22
                shape roundedbox
            }
            element "Person" {
                shape person
                background #08427b
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
            element "WebApp" {
                shape webbrowser
            }
            element "MobileApp" {
                shape mobiledeviceportrait
            }
            element "Database" {
                shape cylinder
            }
            element "Queue" {
                shape pipe
            }
            relationship "Relationship" {
                thickness 2
                fontSize 20
            }
            relationship "Async" {
                style dashed
            }
        }
    }

}
