# HF Saathi — Agentforce Insurance Service Agent

**HF Saathi** is a Salesforce Agentforce service agent for a B2C life-insurance business. It lets customers self-serve on policies, premiums, claims, and support cases through natural conversation, backed by a Sales Cloud + Data Cloud data model and an Experience Cloud self-service portal.

| | |
|---|---|
| **Platform** | Salesforce (Sales Cloud + Data Cloud + Agentforce + Experience Cloud) |
| **Agent developer name** | `HF_Saathi` |
| **Agent template** | `SvcCopilotTmpl__AgentforceServiceAgent` |
| **Domain** | Life insurance — retention, cross-sell, claims & policy servicing |

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

Payment and installment history is sourced from **Data Cloud DMOs** rather than new CRM objects.

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

## Additional resources

- [Agentforce / AgentScript developer guide](https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/einstein-overview.html)
- [Best practices for secure Agentforce implementations](https://www.salesforce.com/blog/best-practices-for-secure-agentforce-implementation/)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
