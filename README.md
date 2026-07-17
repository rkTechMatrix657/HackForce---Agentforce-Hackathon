# HF Saathi — Agentforce Insurance Service Agent

**HF Saathi** is a Salesforce Agentforce service agent for **HF Finance**, a digital insurance provider. It lets authenticated customers self-serve on policies, premiums, claims, and support cases through natural conversation, backed by a Sales Cloud + Data Cloud Customer 360 and an Experience Cloud self-service portal.

| | |
|---|---|
| **Platform** | Salesforce (Sales Cloud + Data Cloud + Agentforce + Experience Cloud) |
| **Agent developer name** | `HF_Saathi` |
| **Agent template** | `SvcCopilotTmpl__AgentforceServiceAgent` |
| **Domain** | Life insurance — retention, cross-sell, claims & policy servicing |

---

## Business use case

**Use Case 2 — Customer 360: Personalized Recommendation Bot.** Deliver personalized insurance product recommendations based on customer profile, behavior, and policy history, and increase cross-sell/upsell using AI-driven insights.

### About HF Finance

HF Finance helps individuals and families secure their financial future through four insurance product lines, each offered across multiple premium amounts and policy terms:

| Product | What it does |
|---|---|
| **Term Life Insurance** | Financial protection to the family in case of the policyholder's demise |
| **Health Insurance** | Covers hospitalization and medical expenses for individuals and families |
| **Child Education Insurance** | Builds a dedicated fund for children's higher education and future expenses |
| **Retirement / Pension Plan** | Long-term retirement savings and regular post-retirement income |

### Business process

1. Customer selects an insurance product and premium plan.
2. HF Finance generates a unique Policy Number.
3. Customer pays fixed monthly premium installments through the policy term.
4. Premium payment history is retained for servicing and analytics.

The system of record for this (**HF Finance PAS**, a separate external Salesforce org) holds the product catalog, customer information, policies, premiums, installments, payments, and claims.

### Business challenges this solves

- No unified 360° customer profile — profile, policies, and payment history live in separate systems.
- Cross-sell/upsell opportunities are identified manually and inconsistently.
- Recommendations aren't personalized; missed premium payments aren't proactively flagged.
- Customer engagement is reactive, and feedback isn't used to improve future interactions.

### Business objectives

Build a unified Customer 360 profile · deliver personalized recommendations · grow cross-sell/upsell · improve retention · provide intelligent, self-service support via Agentforce · learn continuously from customer feedback.

---

## Solution architecture

```
HF Finance PAS (external Salesforce org)
  Product Catalog · Premium Catalog · Policies · Claims · Premium Installments · Premium Payments
        │  data synchronized into
        ▼
Salesforce Data Cloud  ──▶  Agentforce  ──▶  Experience Cloud Portal  ──▶  Authenticated Customers
```

**Data Cloud** is the centralized customer data platform: it ingests the policy catalog from HF Finance PAS, builds the unified Customer 360 profile, models customer/family relationships, and supports AI-powered recommendations.

**Why Experience Cloud login is required:** customers must authenticate before talking to HF Saathi. The authenticated Messaging User lets the agent automatically identify the customer — no manual identity verification during the conversation — and pull their Customer 360 profile, active policies, family info, case history, and messaging history to personalize every response.

**Why the Agentforce Data Library (not direct DMO queries):** Agentforce currently has execution limitations querying Data Cloud DMOs directly from Apex/agent runtime. To work around this: (1) catalog data is synced from Data Cloud into Salesforce custom objects (`Insurance_Product__c`, `Premium_Plan__c`) via the `HFSync*` Apex classes so Agentforce actions can query it normally, and (2) narrative product documentation is indexed into the **Agentforce Data Library** and retrieved via semantic search, keeping responses grounded in approved product documentation and minimizing hallucination.

### Data Cloud data model (DMOs)

| Entity | DMO | Key relationships | Purpose |
|---|---|---|---|
| Product | `Product2_ExternalOrgSF__dlm` | — | All insurance products from HF Finance PAS |
| Premium | `Premium__dlm` | Product Code | Premium variants per product |
| Policy | `Policy_External__dlm` | Product Code, Premium Unique Tag, Customer Id | Purchased customer policies |
| Claim | `Claim_c_ExternalOrgSF__dlm` | Policy Number, Customer Id | Policy claim details |
| Premium Installment | `Premium_Installment__dlm` | Policy Number | Monthly installment schedules |
| Premium Payment | `Premium_Payment_c_ExternalOrgSF__dlm` | Premium Installment, Policy Number | Premium payment history |
| Customer | `UnifiedssotIndividualR1__dlm`, `Contact`, `Account` (Family) | Family Number | Customer 360 and family relationships |

Data Cloud capabilities used: Data Streams, Data Lake Objects (DLO), Data Model Objects (DMO), Identity Resolution, Unified Individual, Search Index, Retriever, Data Graph, Customer 360 Profile.

### Agent capabilities

- **Customer profile** — display customer profile, family information, active policies.
- **Insurance recommendation** — recommend plans based on customer age, existing policy holdings, coverage gaps, and the unified profile; premium options are filtered to the customer's eligible age band.
- **Policy information** — retrieve full policy details via the Data Library (see rationale above).
- **Customer support** — raise a case, check case status, view latest case comments, retrieve policy info.
- **Feedback learning** — after each conversation, capture a rating and optional comments into a custom object; this feedback acts as a guardrail that shapes future recommendations.

### Personalization logic

Recommendations are shaped by: customer age, existing policies, the Customer 360 profile, family information, prior conversation history, customer feedback, and policy ownership — enabling contextual cross-sell/upsell.

### Customer journey

Customer Login → Experience Cloud → Authenticated Messaging User → Agentforce → Customer 360 Retrieval → Policy Recommendation → Policy Details (Data Library) → Customer Interest → Opportunity Creation → Insurance Advisor Follow-up

### Expected business benefits

Complete Customer 360 view · personalized recommendations · higher cross-sell/upsell · improved retention · faster support · reduced manual effort · AI-powered self-service · better satisfaction · continuous improvement from feedback.

---

## What the agent does

HF Saathi routes each conversation to a specialized subagent based on intent and verification state:

| Subagent | Handles |
|---|---|
| **Service Customer Verification** | Authenticates the customer (email/username + emailed code) before any sensitive data is shared |
| **Case Management** | Case lookup, comments, and creation |
| **Account Management** | Contact info updates, password reset |
| **General FAQ** | Knowledge-grounded Q&A on policies and procedures |
| **Escalation** | Hands off to a live human agent on request |
| **Off Topic / Ambiguous Question** | Politely redirects out-of-scope or unclear requests |

The full conversation design — routing logic, guardrails, and action bindings — is defined in [`agentforce/HF_Saathi_AgentScript.yaml`](agentforce/HF_Saathi_AgentScript.yaml).

---

## Data model

Built around the **household as the unit of retention**: a prospect (`Lead`) converts into a family (`Account`) of members (`Contact`), each holding one or more policies (`Opportunity`). Full field-level spec, conversion rules, and the relationship map are documented in [`Insurance_CRM_Data_Model.md`](Insurance_CRM_Data_Model.md).

| Object | Business meaning |
|---|---|
| `Lead` | Prospect |
| `Account` | Family / household |
| `Contact` | Family member / policy holder |
| `Opportunity` | Policy (Interest → Activation) |
| `Insurance_Product__c` | Insurance product catalog (Data Cloud-synced) |
| `Premium_Plan__c` | Premium plan catalog (Data Cloud-synced) |
| `Feedback__c` | CSAT / NPS / complaints |
| `Exception_Log__c` | Centralized error logging for Apex actions |
| `HF_RecommendationScore__mdt` | Custom metadata backing product recommendations |

## Apex actions

All Agentforce-invoked Apex classes carry the `_HF_Saathi` suffix. They group into:

- **Identity & session** — `GetCurrentUserContact`, `LinkContactToSession`, `UpdateSessionEmail`, `UpdateUserMEU`, `CreateLeadFromSession`
- **Customer 360** — `GetCustomerProfile`, `GetCustomerSummary`
- **Policies & premiums** — `GetCustomerPolicies`, `GetPolicyDetails`, `GetPremiumsForContact`, `GetPremiumInstallments`, `GetPaymentHistory`, `CreatePolicyInquiry`
- **Claims** — `CreateClaim`, `GetClaimDetails`
- **Cases & feedback** — `CreateCase`, `GetCaseComments`, `GetCustomerCases`, `CaptureFeedback`, `GetFeedbackGuardrails`, `ExceptionLogger`
- **Recommendations & catalog** — `GetInsuranceRecommendation`, `GetProductsForAge`

Data Cloud sync of the product/premium catalog runs through `HFSyncUpsertInsuranceProduct`, `HFSyncUpsertPremiumPlan`, `HFSyncDeleteInsuranceProduct`, and `HFSyncDeletePremiumPlan`.

The customer-facing self-service experience (`HF_Finance` Experience Cloud site) is powered by `HFCustomerAccountController`, `HFInsuranceCatalogController`, `HFCaseCommentController`, `HFNotificationController`, and `HFSelfRegistrationController`.

---

## Project structure

```
force-app/main/default/   Salesforce metadata (classes, objects, flows, LWC, sites, etc.)
agentforce/               HF Saathi AgentScript definition
config/                   Scratch org definitions
scripts/                  Apex / SOQL utility scripts
manifest/, destructiveChanges/   Deployment manifests
Insurance_CRM_Data_Model.md      Data model & field specification
sfdx-project.json         SFDX project manifest
```

---

## Environments

| Org | Role | Experience Site |
|---|---|---|
| HF Finance | Agentforce + Data Cloud | https://orgfarm-b3f5cab911-ded.develop.my.site.com/HFFinance/s |
| HF Finance PAS | External policy admin system | — |

Login credentials are intentionally not published here — see your team's credential store.

## Sample agent testing scenarios

| Scenario | Sample query | Expected behavior |
|---|---|---|
| Greeting | "Hi" | Welcome the customer and identify them automatically |
| New policy | "Looking for a new policy" | Recommend eligible plans based on age and profile |
| Product selection | "The first/second/third one looks good" | Retrieve product details and create an Opportunity on positive buying intent |
| Customer profile | "Tell me about my profile" | Display customer profile information |
| Family information | "Tell me about my family" | Display linked family members |
| Case status | "What is the status of my case?" | Retrieve current case status |
| Case comments | "What is the latest comment on my case?" | Display the most recent case comment |
| Raise case | "I want to raise a case" | Create a new support case |
| Active policies | "What are my active policies?" | Display all active insurance policies |
| Product details | "Tell me more about HF Nivesh Jeevan" | Retrieve product details from the Data Library — benefits, eligibility, coverage |

---

## Prerequisites

- **Salesforce CLI** — [Install guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm)
- **VS Code + Salesforce Extension Pack** — [Install guide](https://developer.salesforce.com/docs/platform/sfvscode-extensions/guide/install.html)
- **A Salesforce org** with Data Cloud and Agentforce enabled
- **Dev Hub** enabled if you plan to use scratch orgs

## Getting started

```bash
# Authorize your org
sf org login web -a HF-Saathi

# Deploy metadata
sf project deploy start -o HF-Saathi

# Retrieve metadata after org changes
sf project retrieve start -o HF-Saathi
```

Other useful commands: `sf org create scratch`, `sf apex run` / `sf apex log`, `sf data query`.

## Testing & linting

```bash
npm install
npm run lint          # ESLint over Aura/LWC
npm run test:unit      # LWC Jest tests
npm run prettier       # format all supported file types
```

---

## Team

| Member | Role |
|---|---|
| Navdeep | Documentation management, BRD creation, team representation |
| Himanshu | Team leadership, Experience Cloud & Sales Cloud development, QA |
| Sparsh | Data Cloud development, data management, QA |
| Ram | Agentforce setup & configuration, data model design, solution architecture |

## Additional resources

- [Agentforce / AgentScript developer guide](https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/einstein-overview.html)
- [Best practices for secure Agentforce implementations](https://www.salesforce.com/blog/best-practices-for-secure-agentforce-implementation/)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
