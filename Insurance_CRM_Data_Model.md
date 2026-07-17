# Insurance CRM — Data Model & Field Specification

**Platform:** Salesforce (Sales Cloud + Data Cloud + Agentforce)
**Purpose:** Customer onboarding, retention, and cross-sell / upsell
**Document type:** Object & field specification with business context
**Version:** 1.0

---

## 1. Overview

This data model powers a B2C life-insurance CRM focused on **retention and household growth**. A prospect shows interest, becomes a family with members, and each policy interest is tracked from *Interest* to *Activation*. After activation, Data Cloud insights and Agentforce agents drive retention and cross-sell.

| Standard / Custom Object | Business Label | Represents |
|---|---|---|
| `Lead` | Prospect | A person who has shown interest in buying insurance |
| `Account` | Family | The household — the unit of relationship and cross-sell |
| `Contact` | Family Member / Policy Holder | An individual within the family |
| `Opportunity` | Policy | One member's interest in one insurance policy (Interest → Activation) |
| `Feedback__c` | Feedback | CSAT / NPS / complaints — the retention sensor |

### Relationship map

```
Lead (Prospect)
   │  converts to ▼
Account (Family) ──1:N──> Contact (Family Member)
   │                          │
   │ 1:N                      │ 1:N (Policy_Holder__c)
   ▼                          ▼
Opportunity (Policy) ◄── looks up to BOTH Account (Family) and Contact (Member)
   ▲
   │ about
Feedback__c ──> looks up to Family, Family Member, and the Policy
```

- A **Policy** (`Opportunity`) belongs to a **Family** (`AccountId`) and a specific **Member** (`Policy_Holder__c`). This dual link is what enables household-level cross-sell.
- **Feedback** references the family, the member, and optionally the policy it concerns, so sentiment can be rolled up to either level.
- The **Insurance / Premium Type / Premium** picklists on the Policy are thin references; their rich detail is sourced from **Data Cloud** (ingested from the PAS catalog).

---

## 2. Lead — Prospect

**Business context:** The entry point. A prospect expresses interest through a web form, call, WhatsApp, or campaign. The Lead qualifies the person and captures *what* they are interested in, so that on conversion the interest carries straight onto a Policy opportunity.
**Conversion note:** On Lead conversion, `Company` maps to the **Family** account name (convention: "<Surname> Family"), the person becomes a **Contact (Member)**, and an **Opportunity (Policy)** is created carrying the interested product.

| Field Label | API Name | Type | Business Description | Example |
|---|---|---|---|---|
| First Name | `FirstName` (std) | Text | Prospect's given name | Rajesh |
| Last Name | `LastName` (std) | Text | Prospect's surname | Kumar |
| Family Name | `Company` (std) | Text | Becomes the Family account on convert | Kumar Family |
| Email | `Email` (std) | Email | Primary contact | rajesh@example.com |
| Phone | `Phone` (std) | Phone | Primary contact | +91 98290 00000 |
| Lead Status | `Status` (std) | Picklist | Funnel stage: New, Contacted, Qualified, Nurturing, Converted, Disqualified | Qualified |
| Lead Source | `LeadSource` (std) | Picklist | Where the interest came from | Website |
| Date of Birth | `Date_of_Birth__c` | Date | Drives age, eligibility, product fit | 1990-06-15 |
| Annual Income | `Annual_Income__c` | Currency | Affordability & cover sizing | 1,500,000 |
| Interested Insurance | `Interested_Insurance__c` | Picklist | Product the prospect wants (Data Cloud-backed) | Term Insurance |
| Interested Premium Type | `Interested_Premium_Type__c` | Picklist | Preferred pay style | Regular Premium |
| Family Size | `Family_Size__c` | Number(2,0) | Cross-sell potential of the household | 4 |
| Existing Customer | `Existing_Customer__c` | Checkbox | Belongs to a family we already serve | false |
| Preferred Channel | `Preferred_Contact_Channel__c` | Picklist | WhatsApp / Email / Phone | WhatsApp |
| Lead Score | `Lead_Score__c` | Number | Conversion propensity (Einstein / Data Cloud) | 78 |
| Marketing Consent | `Consent_Marketing__c` | Checkbox | DPDP / regulatory consent to contact | true |
| Disqualification Reason | `Disqualification_Reason__c` | Picklist | Why a lead was dropped | — |

---

## 3. Account — Family

**Business context:** The household is the unit of retention and growth. Treating the family (not the individual) as the Account lets you see total coverage, total premium, and household-level risk — the foundation for cross-sell ("the family has term cover but no child plan"). Several Data Cloud scores are written back here at the household level.

| Field Label | API Name | Type | Business Description | Example |
|---|---|---|---|---|
| Family Name | `Name` (std) | Text | Household display name | Kumar Family |
| Phone | `Phone` (std) | Phone | Household contact | +91 98290 00000 |
| Billing Address | `BillingAddress` (std) | Address | Household address | Jodhpur, Rajasthan |
| Head of Family | `Head_of_Family__c` | Lookup(Contact) | Primary decision-maker | Rajesh Kumar |
| Number of Members | `Number_of_Members__c` | Roll-Up / Number | Size of the household | 4 |
| Active Policies | `Number_of_Active_Policies__c` | Roll-Up / Number | Policies currently in force | 2 |
| Household Premium Value | `Total_Premium_Value__c` | Currency / Roll-Up | Sum of active premiums | 66,000 |
| Household Income | `Household_Income__c` | Currency | Combined income; affordability | 2,500,000 |
| Customer Since | `Customer_Since__c` | Date | First activation date; tenure | 2024-04-01 |
| Family Segment | `Family_Segment__c` | Picklist | High Value / Growth / At-Risk (Data Cloud) | Growth |
| Churn Risk Score | `Churn_Risk_Score__c` | Number | Household churn likelihood (Data Cloud) | 32 |
| Customer Lifetime Value | `CLV__c` | Currency | Projected household value (Data Cloud) | 1,800,000 |
| Preferred Language | `Preferred_Language__c` | Picklist | Communication language | Hindi |

---

## 4. Contact — Family Member / Policy Holder

**Business context:** Each person in the family. The same person can be a policy holder on one policy and a nominee on another. Life-stage and member-level scores make individual cross-sell precise (e.g., a member who just had a child is a prime child-plan target).

| Field Label | API Name | Type | Business Description | Example |
|---|---|---|---|---|
| First Name | `FirstName` (std) | Text | Given name | Rajesh |
| Last Name | `LastName` (std) | Text | Surname | Kumar |
| Family | `AccountId` (std) | Lookup(Account) | The household this member belongs to | Kumar Family |
| Date of Birth | `Birthdate` (std) | Date | Age, eligibility, rating | 1990-06-15 |
| Email | `Email` (std) | Email | Communication | rajesh@example.com |
| Phone | `Phone` (std) | Phone | Communication | +91 98290 00000 |
| Role in Family | `Role_in_Family__c` | Picklist | Head / Spouse / Child / Parent / Dependent | Head |
| Gender | `Gender__c` | Picklist | Male / Female / Other | Male |
| Marital Status | `Marital_Status__c` | Picklist | Single / Married / etc. | Married |
| Occupation | `Occupation__c` | Picklist | Risk & affordability | Salaried — IT |
| Annual Income | `Annual_Income__c` | Currency | Cover eligibility | 1,500,000 |
| PAN | `PAN__c` | Text(10), Unique | KYC identifier | ABCPK1234D |
| KYC Status | `KYC_Status__c` | Picklist | Pending / Verified | Verified |
| Is Policy Holder | `Is_Policy_Holder__c` | Checkbox | Holds at least one policy | true |
| Is Nominee | `Is_Nominee__c` | Checkbox | Named as nominee on a policy | false |
| Life Stage | `Life_Stage__c` | Picklist | Student / Working / Married / Parent / Retired — cross-sell trigger | Parent |
| Member Churn Risk | `Member_Churn_Risk__c` | Number | Individual churn score (Data Cloud) | 28 |
| Next Best Product | `Next_Best_Product__c` | Picklist | Recommended product (Data Cloud) | Child Plan |
| Marketing Consent | `Consent_Marketing__c` | Checkbox | Consent to contact | true |

---

## 5. Opportunity — Policy

**Business context:** One member's interest in one insurance policy, tracked from first interest to activation. Because it looks up to **both** the Family and the Member, you can report at household or individual level. The three reference picklists (Insurance, Premium Type, Premium) capture the chosen plan; their full detail is surfaced from Data Cloud. After activation, this record links to the issued policy in the PAS.

| Field Label | API Name | Type | Business Description | Example |
|---|---|---|---|---|
| Policy Name | `Name` (std) | Text | Display label | Rajesh Kumar — Term Insurance |
| Family | `AccountId` (std) | Lookup(Account) | The household | Kumar Family |
| Policy Holder | `Policy_Holder__c` | Lookup(Contact) | The member this policy is for | Rajesh Kumar |
| Stage | `StageName` (std) | Picklist | Interest → Activation lifecycle (see §6) | Quote Provided |
| Close / Expected Date | `CloseDate` (std) | Date | Expected activation date | 2026-05-15 |
| Amount | `Amount` (std) | Currency | Expected annualized premium | 14,160 |
| Opportunity Type | `Opportunity_Type__c` | Picklist | New Business / Cross-sell / Upsell / Renewal | New Business |
| Insurance | `Insurance__c` | Picklist | Insurance product (detail from Data Cloud) | Term Insurance |
| Premium Type | `Premium_Type__c` | Picklist | Pay style (detail from Data Cloud) | Regular Premium |
| Premium | `Premium__c` | Picklist | Premium plan / amount (detail from Data Cloud) | ₹12,000 / year |
| Sum Assured | `Sum_Assured__c` | Currency | Coverage proposed | 10,000,000 |
| Policy Term (Yrs) | `Policy_Term__c` | Number(3,0) | Duration of cover | 30 |
| Premium Amount | `Premium_Amount__c` | Currency | Per-installment premium | 12,000 |
| Premium Frequency | `Premium_Frequency__c` | Picklist | Annual / Monthly / etc. | Annual |
| Source Lead | `Source_Lead__c` | Lookup(Lead) | Lead this originated from | LEAD-00045 |
| Quote Sent Date | `Quote_Sent_Date__c` | Date | When quote was shared | 2026-04-20 |
| Application Date | `Application_Date__c` | Date | When application submitted | 2026-04-28 |
| Underwriting Status | `Underwriting_Status__c` | Picklist | Pending / Accepted / Loaded / Declined | Pending |
| Activation Date | `Activation_Date__c` | Date | Date policy went in force | — |
| Policy Number | `Policy_Number__c` | Text(20), External ID | Issued policy ref in PAS | — |
| Propensity Score | `Propensity_Score__c` | Number | Likelihood to convert/buy (Data Cloud) | 71 |
| Next Best Action | `Next_Best_Action__c` | Text | Recommended action (Agentforce) | Send WhatsApp reminder |

---

## 6. Opportunity Stage Lifecycle (Interest → Activation)

| Stage | Meaning | Typical owner / agent |
|---|---|---|
| Interest Shown | Prospect/member expressed interest | Onboarding Agent |
| Needs Assessment | Requirement & affordability captured | Onboarding Agent / Rep |
| Quote Provided | Premium quote shared | Onboarding Agent |
| Application Submitted | Proposal form & KYC submitted | Rep |
| Underwriting | Risk assessment in progress | Underwriting |
| Payment Pending | Awaiting first premium | Onboarding Agent |
| **Activated** *(Closed Won)* | First premium received; **policy in force** | System → hand-off to Retention |
| Not Interested *(Closed Lost)* | Dropped at any stage | — |

On **Activated**, the policy becomes live and the household passes to the Retention and Cross-sell agents.

---

## 7. Feedback (`Feedback__c`) — Custom Object

**Business context:** The retention sensor. Every survey response, complaint, or claim-experience rating is logged here. Feedback streams into Data Cloud as sentiment, lifts or lowers churn scores, and can proactively trigger the Retention Agent. Positive feedback combined with a coverage gap can trigger cross-sell instead.

| Field Label | API Name | Type | Business Description | Example |
|---|---|---|---|---|
| Feedback Number | `Name` | Auto Number `FB-{00000}` | Unique identifier | FB-00231 |
| Family | `Family__c` | Lookup(Account) | Household giving feedback | Kumar Family |
| Family Member | `Family_Member__c` | Lookup(Contact) | Individual giving feedback | Rajesh Kumar |
| Related Policy | `Related_Policy__c` | Lookup(Opportunity) | Policy the feedback is about | Rajesh — Term Insurance |
| Feedback Type | `Feedback_Type__c` | Picklist | CSAT / NPS / Complaint / Compliment / Suggestion / Claim Experience | NPS |
| Channel | `Channel__c` | Picklist | Web / App / WhatsApp / Call / Email / Survey | WhatsApp |
| Rating | `Rating__c` | Number(1) | CSAT score 1–5 | 4 |
| NPS Score | `NPS_Score__c` | Number(2,0) | 0–10 recommendation score | 8 |
| Sentiment | `Sentiment__c` | Picklist | Positive / Neutral / Negative (Data Cloud / Einstein) | Positive |
| Comments | `Comments__c` | Long Text Area | Free-text feedback | Smooth onboarding, quick response. |
| Feedback Date | `Feedback_Date__c` | Date/Time | When submitted | 2026-05-02 |
| Status | `Status__c` | Picklist | New / In Review / Actioned / Closed | New |
| Resolution | `Resolution__c` | Long Text Area | How it was addressed | — |
| Triggered Retention Action | `Triggered_Retention_Action__c` | Checkbox | Whether it kicked off a save action | false |
| Related Case | `Related_Case__c` | Lookup(Case) | If escalated to a case | — |
| Agent Followed Up | `Agent_Followed_Up__c` | Checkbox | Agentforce acted on it | false |

---

## 8. Data Cloud–Enriched Fields

These fields are not maintained by hand — they are calculated in Data Cloud and written back to the CRM (or surfaced from the unified profile), then used by Agentforce.

| Object | Field(s) | Source insight |
|---|---|---|
| Account (Family) | `Family_Segment__c`, `Churn_Risk_Score__c`, `CLV__c` | Household segmentation, churn model, lifetime value |
| Contact (Member) | `Member_Churn_Risk__c`, `Next_Best_Product__c` | Individual churn, next-best-product propensity |
| Opportunity (Policy) | `Propensity_Score__c`, `Next_Best_Action__c` | Conversion propensity, recommended action |
| Feedback | `Sentiment__c` | NLP sentiment classification |
| Opportunity picklists | `Insurance__c`, `Premium_Type__c`, `Premium__c` (detail) | PAS catalog detail (coverage, features, amounts) surfaced from Data Cloud |

---

## 9. Implementation Notes

1. **Dual lookup on Policy:** Use the standard `AccountId` for Family and a custom `Policy_Holder__c` lookup for the Member. (Standard Opportunity Contact Roles can supplement, but the direct lookup keeps household + member reporting simple.)
2. **Lead conversion mapping:** Map `Interested_Insurance__c` → `Opportunity.Insurance__c`, `Date_of_Birth__c` → `Contact.Birthdate`, and set `Company` = Family name so conversion creates the right Family account. Configure custom conversion field mapping in Setup.
3. **Roll-ups on Family:** `Number_of_Active_Policies__c` and `Total_Premium_Value__c` should roll up from activated Opportunities (via Roll-Up Summary if Opportunity is made a detail, or via Flow/Apex given the lookup relationship).
4. **Picklist detail from Data Cloud:** Keep the three picklists' *values* governed in CRM, but surface coverage/feature/amount *detail* via a Data Cloud-related component or a Flow that queries the unified catalog — avoid duplicating the PAS catalog into CRM fields.
5. **Feedback → retention trigger:** A record-triggered Flow on `Feedback__c` (negative sentiment or low rating) updates churn signals and invokes the Agentforce Retention Agent action.
6. **Stage automation:** On `Opportunity.StageName = Activated`, stamp `Activation_Date__c`, set `Account.Customer_Since__c` if first policy, and route the household to retention.

---

*End of document.*
