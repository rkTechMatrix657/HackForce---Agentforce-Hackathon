/**
 * Agentforce Apex Action: GetFeedbackGuardrails_HF_Saathi
 *
 * Reads the customer's historical Feedback__c records and computes an aggregate
 * sentiment profile. HF Saathi uses this at the START of every conversation as
 * a guardrail — adjusting tone, skipping products the customer has previously
 * rejected, and prioritising recovery actions for dissatisfied customers.
 *
 * Aggregation logic:
 *   - avgRating     : mean of Rating__c (1-5) across last 90 days
 *   - avgNPS        : mean of NPS_Score__c (0-10) across last 12 months
 *   - hasComplaints : any Feedback_Type__c = 'Complaint' open in last 180 days
 *   - rejectedProducts: products from Suggestion-type feedback with Sentiment=Negative
 *   - overallSentiment: Positive (avg ≥ 4 and NPS ≥ 7) / Neutral / Negative
 *
 * Data source: Feedback__c (CRM) — linked via Family_Member__c = contactId
 */
public with sharing class GetFeedbackGuardrails_HF_Saathi {

    @InvocableMethod(
        label='Get Feedback Guardrails'
        description='Reads the customer\'s Feedback__c history to compute an aggregate sentiment profile used as conversation guardrails: overall sentiment, average rating, open complaints, and previously rejected insurance products.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(buildGuardrails(req.contactId, req.familyId));
        }
        return results;
    }

    private static Result buildGuardrails(String contactId, String familyId) {
        Result res = new Result();
        res.overallSentiment  = 'Neutral';
        res.avgRating         = '3.0';
        res.hasOpenComplaints = false;
        res.rejectedProducts  = '';
        res.guardrailSummary  = '';

        Date cutoff90d  = Date.today().addDays(-90);
        Date cutoff180d = Date.today().addDays(-180);
        Date cutoff365d = Date.today().addDays(-365);

        // Query recent feedback records for this contact (and optionally family)
        List<Feedback__c> feedbackList = [
            SELECT Id, Feedback_Type__c, Rating__c, NPS_Score__c,
                   Sentiment__c, Comments__c, Status__c, Feedback_Date__c,
                   Agent_Followed_Up__c
            FROM Feedback__c
            WHERE Family_Member__c = :contactId
              AND Feedback_Date__c >= :Datetime.newInstance(cutoff365d, Time.newInstance(0,0,0,0))
            ORDER BY Feedback_Date__c DESC
            LIMIT 50
        ];

        if (feedbackList.isEmpty()) {
            res.guardrailSummary = 'No prior feedback on record. Start fresh with a warm greeting.';
            return res;
        }

        // Aggregate
        Decimal ratingSum = 0; Integer ratingCount = 0;
        Decimal npsSum    = 0; Integer npsCount    = 0;
        Boolean hasComplaints = false;
        Set<String> rejected = new Set<String>();
        Integer positiveCount = 0, negativeCount = 0;

        for (Feedback__c fb : feedbackList) {
            if (fb.Rating__c != null) {
                ratingSum += fb.Rating__c; ratingCount++;
            }
            if (fb.NPS_Score__c != null) {
                npsSum += fb.NPS_Score__c; npsCount++;
            }
            if (fb.Feedback_Type__c == 'Complaint' && fb.Status__c != 'Closed'
                    && fb.Feedback_Date__c >= Datetime.newInstance(cutoff180d, Time.newInstance(0,0,0,0))) {
                hasComplaints = true;
            }
            if (fb.Feedback_Type__c == 'Suggestion' && fb.Sentiment__c == 'Negative'
                    && fb.Comments__c != null) {
                // Extract product name from comments (written by CaptureFeedback_HF_Saathi)
                String comment = fb.Comments__c.toLowerCase();
                for (String prod : new List<String>{
                        'Term Life Insurance','Health Insurance',
                        'Child Education Insurance','Retirement Plan Insurance'}) {
                    if (comment.contains(prod.toLowerCase())) rejected.add(prod);
                }
            }
            if (fb.Sentiment__c == 'Positive') positiveCount++;
            if (fb.Sentiment__c == 'Negative') negativeCount++;
        }

        Decimal avgRating = ratingCount > 0 ? (ratingSum / ratingCount).setScale(1) : 3.0;
        Decimal avgNPS    = npsCount    > 0 ? (npsSum    / npsCount).setScale(1)    : 5.0;

        String sentiment;
        if (avgRating >= 4.0 && avgNPS >= 7) {
            sentiment = 'Positive';
        } else if (avgRating < 3.0 || avgNPS < 5 || negativeCount > positiveCount) {
            sentiment = 'Negative';
        } else {
            sentiment = 'Neutral';
        }

        res.overallSentiment  = sentiment;
        res.avgRating         = String.valueOf(avgRating);
        res.hasOpenComplaints = hasComplaints;
        res.rejectedProducts  = String.join(new List<String>(rejected), ',');

        // Build guardrail instructions for the agent
        List<String> notes = new List<String>();
        if (sentiment == 'Negative' || hasComplaints) {
            notes.add('Customer has expressed dissatisfaction previously. Lead with empathy and ask if there are any unresolved issues before making recommendations.');
        }
        if (sentiment == 'Positive') {
            notes.add('Customer has a positive history (Avg Rating: ' + avgRating + '/5, NPS: ' + avgNPS + '/10). They are receptive — well-timed recommendations will land well.');
        }
        if (!rejected.isEmpty()) {
            notes.add('Previously rejected products (do NOT recommend again): ' + String.join(new List<String>(rejected), ', ') + '.');
        }
        if (hasComplaints) {
            notes.add('There are open complaints. Acknowledge and offer to check their case status first.');
        }
        res.guardrailSummary = notes.isEmpty()
            ? 'Customer history looks neutral. Proceed with standard warm conversation.'
            : String.join(notes, ' ');

        return res;
    }

    public class Request {
        @InvocableVariable(label='Contact ID' description='Salesforce Contact ID of the verified customer.' required=true)
        public String contactId;

        @InvocableVariable(label='Family ID' description='Salesforce Account (Family) ID.' required=false)
        public String familyId;
    }

    public class Result {
        @InvocableVariable(label='Overall Sentiment' description='Positive / Neutral / Negative based on aggregated feedback history.')
        public String overallSentiment;

        @InvocableVariable(label='Avg Rating' description='Average CSAT rating (1-5) from last 90 days.')
        public String avgRating;

        @InvocableVariable(label='Has Open Complaints' description='True if there are unresolved complaint records in the last 6 months.')
        public Boolean hasOpenComplaints;

        @InvocableVariable(label='Rejected Products' description='Comma-separated list of insurance products the customer previously declined. Do not recommend these.')
        public String rejectedProducts;

        @InvocableVariable(label='Guardrail Summary' description='Plain-language guardrail instructions for the agent to follow in this conversation.')
        public String guardrailSummary;
    }
}