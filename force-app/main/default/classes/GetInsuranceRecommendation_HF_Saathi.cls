/**
 * Agentforce Apex Action: GetInsuranceRecommendation_HF_Saathi
 *
 * Generates personalized insurance + premium recommendations using a 4-layer engine:
 *
 * LAYER 1 -- HF_RecommendationScore__mdt (Custom Metadata, business-configurable):
 *   Business team maintains static scoring rules (age, income, segment, life stage).
 *   Highest-scoring matching rules determine which products surface.
 *
 * LAYER 2 -- Coverage gap analysis:
 *   Checks which of the 4 HF Finance product types the customer does NOT yet hold.
 *   Missing products get a gap bonus added to their score.
 *
 * LAYER 3 -- Data Cloud product + premium catalog:
 *   Product2_ExternalOrgSF__dlm  (relationship: Product Code)
 *   Premium__dlm                 (relationship: Product Code)
 *   Fetches real products and premium plans matching the recommended type.
 *
 * LAYER 4 -- Feedback guardrails:
 *   Products in rejectedProducts list are suppressed entirely.
 *   High churn risk customers receive a retention-first message.
 *
 * Proactive trigger: called for BOTH explicit recommendation requests AND inline
 * during policy/case/claim conversations (Capability 9).
 *
 * Writes recommendation to Feedback__c (type=Suggestion) for learning loop.
 */
public with sharing class GetInsuranceRecommendation_HF_Saathi {

    private static final Map<String,String> PRODUCT_DISPLAY = new Map<String,String>{
        'Term Life Insurance'        => 'Term Life Insurance',
        'Health Insurance'           => 'Health Insurance',
        'Child Education Insurance'  => 'Child Education Insurance',
        'Retirement Plan Insurance'  => 'Retirement Plan Insurance'
    };

    @InvocableMethod(
        label='Get Insurance Recommendation'
        description='Generates personalized insurance and premium recommendations using HF_RecommendationScore__mdt static scores, coverage gap analysis, real Data Cloud product/premium catalog (Product2_ExternalOrgSF__dlm, Premium__dlm), and feedback guardrails.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(recommend(req));
        }
        return results;
    }

    private static Result recommend(Request req) {
        Result res = new Result();

        // ── Load CRM customer profile ─────────────────────────────────────────
        List<Contact> contacts = [
            SELECT Id, FirstName, Birthdate, Annual_Income__c, Occupation__c,
                   Life_Stage__c, Member_Churn_Risk__c, Next_Best_Product__c,
                   Title, Department, Marital_Status__c, Gender__c
            FROM Contact WHERE Id = :req.contactId LIMIT 1
        ];
        if (contacts.isEmpty()) {
            res.recommendationSummary = 'Unable to load customer profile for recommendation.';
            return res;
        }
        Contact cust = contacts[0];

        // ── Load family profile ───────────────────────────────────────────────
        Account family = null;
        if (String.isNotBlank(req.familyId)) {
            List<Account> families = [
                SELECT Id, Family_Segment__c, Churn_Risk_Score__c, CLV__c,
                       Household_Income__c, Number_of_Members__c, Number_of_Active_Policies__c
                FROM Account WHERE Id = :req.familyId LIMIT 1
            ];
            if (!families.isEmpty()) family = families[0];
        }

        // ── Compute age ───────────────────────────────────────────────────────
        Integer age = cust.Birthdate != null
            ? cust.Birthdate.daysBetween(Date.today()) / 365 : 35;

        // ── Parse held types from input ───────────────────────────────────────
        Set<String> heldTypes = new Set<String>();
        if (String.isNotBlank(req.heldInsuranceTypes)) {
            heldTypes.addAll(req.heldInsuranceTypes.split(','));
        }

        // ── Parse rejected products from guardrails ───────────────────────────
        Set<String> rejected = new Set<String>();
        if (String.isNotBlank(req.rejectedProducts)) {
            rejected.addAll(req.rejectedProducts.split(','));
        }

        // ── Read scoring rules from Custom Metadata ───────────────────────────
        List<HF_RecommendationScore__mdt> allRules = [
            SELECT Insurance_Type__c, Product_Code__c, Min_Age__c, Max_Age__c,
                   Min_Annual_Income__c, Family_Segment__c, Life_Stage__c,
                   Base_Score__c, Priority_Order__c, Recommendation_Reason__c
            FROM HF_RecommendationScore__mdt
            WHERE Is_Active__c = true
            ORDER BY Base_Score__c DESC, Priority_Order__c ASC
        ];

        String customerSegment  = family != null ? family.Family_Segment__c : '';
        String customerLifeStage = cust.Life_Stage__c != null ? cust.Life_Stage__c : '';
        Decimal customerIncome  = cust.Annual_Income__c != null ? cust.Annual_Income__c
                                  : (family != null ? family.Household_Income__c : 0);
        if (customerIncome == null) customerIncome = 0;

        // ── Score each product type ───────────────────────────────────────────
        Map<String, Decimal> typeScores = new Map<String, Decimal>();
        Map<String, String>  typeReasons = new Map<String, String>();

        for (HF_RecommendationScore__mdt rule : allRules) {
            String iType = rule.Insurance_Type__c;
            if (rejected.contains(iType)) continue;

            // Age check
            Decimal minAge = rule.Min_Age__c != null ? rule.Min_Age__c : 0;
            Decimal maxAge = rule.Max_Age__c != null ? rule.Max_Age__c : 999;
            if (age < minAge || age > maxAge) continue;

            // Income check
            Decimal minInc = rule.Min_Annual_Income__c != null ? rule.Min_Annual_Income__c : 0;
            if (customerIncome < minInc) continue;

            // Segment check
            String seg = rule.Family_Segment__c != null ? rule.Family_Segment__c : 'All';
            if (seg != 'All' && String.isNotBlank(customerSegment) && seg != customerSegment) continue;

            // Life stage check
            String ruleStages = rule.Life_Stage__c != null ? rule.Life_Stage__c : 'All';
            Boolean stageMatch = ruleStages == 'All';
            if (!stageMatch && String.isNotBlank(customerLifeStage)) {
                for (String s : ruleStages.split(',')) {
                    if (s.trim() == customerLifeStage.trim()) { stageMatch = true; break; }
                }
            }
            if (!stageMatch) continue;

            // Score: base + gap bonus
            Decimal score = rule.Base_Score__c != null ? rule.Base_Score__c : 50;
            if (!heldTypes.contains(iType)) score += 10; // coverage gap bonus

            if (!typeScores.containsKey(iType) || score > typeScores.get(iType)) {
                typeScores.put(iType, score);
                if (String.isNotBlank(rule.Recommendation_Reason__c)) {
                    String reason = rule.Recommendation_Reason__c
                        .replace('{customerName}', cust.FirstName != null ? cust.FirstName : 'you')
                        .replace('{age}', String.valueOf(age))
                        .replace('{lifeStage}', customerLifeStage != null ? customerLifeStage : '');
                    typeReasons.put(iType, reason);
                }
            }
        }

        if (typeScores.isEmpty()) {
            res.recommendationSummary = cust.FirstName + ' is already very well covered! '
                + 'Your current HF Finance portfolio addresses the key protection needs. '
                + 'If your life situation changes, do come back and I will find the perfect plan.';
            res.topRecommendedProduct = '';
            return res;
        }

        // ── Sort by score, pick top 2 ─────────────────────────────────────────
        List<String> sortedTypes = sortByScore(typeScores);
        Integer limit2 = Math.min(2, sortedTypes.size());

        // Product/premium catalog now served via data library (knowledge RAG).
        // Use picklist-based premium plans from GetPremiumsForContact_HF_Saathi for actual plans.
        Map<String, List<PremiumPlan>> productPlans = new Map<String, List<PremiumPlan>>();

        // ── Build recommendation message ──────────────────────────────────────
        Boolean isHighChurn = (family != null && family.Churn_Risk_Score__c != null
                               && family.Churn_Risk_Score__c >= 70)
                           || (cust.Member_Churn_Risk__c != null && cust.Member_Churn_Risk__c >= 70);

        List<String> lines = new List<String>();
        if (isHighChurn) {
            lines.add('I want to make sure you are completely satisfied with your HF Finance coverage first. '
                + 'That said, based on your profile, here is what I think could add real value:\n');
        } else if (req.inquiryType == 'Recommendation') {
            lines.add('Based on your profile, here is a personalised recommendation, '
                + cust.FirstName + ':\n');
        } else {
            lines.add('Here are the best insurance options for you right now:\n');
        }

        for (Integer i = 0; i < limit2; i++) {
            String iType  = sortedTypes[i];
            String reason = typeReasons.containsKey(iType) ? typeReasons.get(iType)
                : 'This product is specifically suited to your current situation.';

            lines.add((i + 1) + '. *' + iType + '*');
            lines.add('   ' + reason);

            // Add premium guidance from DC360 or fallback
            List<PremiumPlan> plans = productPlans.get(iType);
            if (plans != null && !plans.isEmpty()) {
                PremiumPlan cheapest = plans[0];
                PremiumPlan costlier = plans.size() > 1 ? plans[plans.size()-1] : cheapest;
                lines.add('   Premium from ' + fmtCcy(cheapest.premiumAmount)
                    + '/month | Cover: ' + fmtCcy(cheapest.sumAssured)
                    + ' -- ' + fmtCcy(costlier.sumAssured)
                    + ' | Term: ' + (String.isNotBlank(cheapest.policyTerm) ? cheapest.policyTerm + ' yrs' : 'flexible'));
            } else {
                lines.add('   ' + fallbackPremiumGuidance(iType, age));
            }
            lines.add('');
        }

        if (req.inquiryType == 'Recommendation') {
            lines.add('Does this sound relevant to your needs? I can get you a detailed quote or we can explore further.');
        } else {
            lines.add('Which of these interests you? I can provide a full premium breakdown and register your interest right away.');
        }

        res.recommendationSummary   = String.join(lines, '\n').trim();
        res.topRecommendedProduct   = sortedTypes[0];
        res.recommendationLogId     = logRecommendation(req.contactId, req.familyId, sortedTypes[0], req.inquiryType);
        return res;
    }

    // ── Sort map by value descending ──────────────────────────────────────────
    private static List<String> sortByScore(Map<String, Decimal> scores) {
        List<String> keys = new List<String>(scores.keySet());
        // Bubble sort (small list)
        for (Integer i = 0; i < keys.size(); i++) {
            for (Integer j = 0; j < keys.size() - i - 1; j++) {
                if (scores.get(keys[j]) < scores.get(keys[j+1])) {
                    String tmp = keys[j]; keys[j] = keys[j+1]; keys[j+1] = tmp;
                }
            }
        }
        return keys;
    }

    private static String logRecommendation(String contactId, String familyId, String product, String inquiryType) {
        try {
            Feedback__c fb = new Feedback__c();
            fb.Family_Member__c  = contactId;
            if (String.isNotBlank(familyId)) fb.Family__c = familyId;
            fb.Feedback_Type__c  = 'Suggestion';
            fb.Channel__c        = 'App';
            fb.Status__c         = 'New';
            fb.Feedback_Date__c  = Datetime.now();
            fb.Agent_Followed_Up__c = false;
            fb.Comments__c       = 'HF Saathi recommended: ' + product
                + '. Inquiry type: ' + (inquiryType != null ? inquiryType : 'Unknown')
                + '. Awaiting customer response.';
            insert fb;
            return fb.Id;
        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('GetInsuranceRecommendation_HF_Saathi', 'logRecommendation', ex, contactId);
            return null;
        }
    }

    private static String fallbackPremiumGuidance(String iType, Integer age) {
        if (iType == 'Term Life Insurance') {
            return age < 35 ? 'From approx Rs.800/month for Rs.50L cover.'
                : 'From approx Rs.1,500/month for Rs.50L cover.';
        } else if (iType == 'Health Insurance') {
            return 'From approx Rs.700/month for Rs.5L family floater cover.';
        } else if (iType == 'Child Education Insurance') {
            return 'Start from Rs.1,000/month. Corpus payable when child turns 18.';
        }
        return 'Flexible contributions from Rs.1,500/month.';
    }

    private static String str(List<Object> row, Integer i) {
        return (i < row.size() && row[i] != null) ? String.valueOf(row[i]) : '';
    }
    private static Decimal dec(List<Object> row, Integer i) {
        if (i >= row.size() || row[i] == null) return null;
        try { return Decimal.valueOf(String.valueOf(row[i])); } catch (Exception e) { return null; }
    }
    private static String fmtCcy(Decimal d) {
        return d != null ? 'Rs.' + String.valueOf(d.setScale(0)).replaceAll('(\\d)(?=(\\d{2})+(?!\\d))', '$1,') : '--';
    }

    private class PremiumPlan {
        public String productCode, policyTerm, ageBand, premiumFrequency;
        public Decimal premiumAmount, sumAssured;
    }

    public class Request {
        @InvocableVariable(label='Contact ID' required=true)
        public String contactId;
        @InvocableVariable(label='Family ID' required=false)
        public String familyId;
        @InvocableVariable(label='Customer ID' description='HF Finance Customer_ID__c.' required=false)
        public String customerId;
        @InvocableVariable(label='Inquiry Type' description='New / Recommendation / Upsell / CrossSell' required=false)
        public String inquiryType;
        @InvocableVariable(label='Customer Need' description='Customer\'s stated need from conversation.' required=false)
        public String customerNeed;
        @InvocableVariable(label='Held Insurance Types' description='Comma-separated types already held (from GetCustomerPolicies).' required=false)
        public String heldInsuranceTypes;
        @InvocableVariable(label='Rejected Products' description='Comma-separated products to suppress (from GetFeedbackGuardrails).' required=false)
        public String rejectedProducts;
    }

    public class Result {
        @InvocableVariable(label='Recommendation Summary' description='Personalised recommendation message for the customer.')
        public String recommendationSummary;
        @InvocableVariable(label='Top Recommended Product' description='Highest-scored recommended insurance product.')
        public String topRecommendedProduct;
        @InvocableVariable(label='Recommendation Log ID' description='Feedback__c ID created for the learning loop.')
        public String recommendationLogId;
    }
}