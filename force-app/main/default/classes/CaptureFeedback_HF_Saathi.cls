/**
 * Agentforce Apex Action: CaptureFeedback_HF_Saathi
 *
 * Logs customer feedback on insurance recommendations into Feedback__c.
 * This is the core of the "learn from feedback" loop.
 *
 * Uses existing Feedback__c fields:
 *   - Feedback_Type__c = 'Suggestion' (for recommendations) or 'CSAT' / 'Complaint'
 *   - Rating__c = customer's 1-5 rating
 *   - Comments__c = free-text response (includes recommended product name)
 *   - Sentiment__c = derived from wasActedOn + rating
 *   - Agent_Followed_Up__c = true when customer acted on the recommendation
 *   - Channel__c = 'App' (HF Saathi)
 *   - Family__c, Family_Member__c = linked lookups
 *
 * The GetInsuranceRecommendation_HF_Saathi action reads these records (last 90 days)
 * to suppress products the customer has previously declined and prioritise products
 * the customer has shown interest in.
 */
public with sharing class CaptureFeedback_HF_Saathi {

    @InvocableMethod(
        label='Capture Customer Feedback'
        description='Logs customer response to an HF Saathi recommendation into Feedback__c. Positive responses (acted on, high rating) reinforce the recommendation engine; negative responses suppress that product for 90 days.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(captureFeedback(req));
        }
        return results;
    }

    private static Result captureFeedback(Request req) {
        Result res = new Result();

        if (String.isBlank(req.contactId)) {
            return res;
        }

        try {
            Feedback__c fb = new Feedback__c();
            fb.Family_Member__c = req.contactId;
            if (String.isNotBlank(req.familyId)) fb.Family__c = req.familyId;

            // Map feedbackType to Feedback_Type__c picklist
            fb.Feedback_Type__c = mapFeedbackType(req.feedbackType);
            fb.Channel__c = 'App';
            fb.Feedback_Date__c = Datetime.now();
            fb.Status__c = 'New';

            // Rating
            if (String.isNotBlank(req.rating)) {
                try {
                    fb.Rating__c = Decimal.valueOf(req.rating.trim()).setScale(0);
                } catch (Exception e) { /* ignore invalid rating */ }
            }

            // Derive sentiment from whether the customer acted on it and rating
            Boolean acted = req.wasActedOn == true;
            Decimal ratingVal = fb.Rating__c;
            if (acted || (ratingVal != null && ratingVal >= 4)) {
                fb.Sentiment__c = 'Positive';
                fb.Agent_Followed_Up__c = true;
            } else if (ratingVal != null && ratingVal <= 2) {
                fb.Sentiment__c = 'Negative';
                fb.Agent_Followed_Up__c = false;
            } else {
                fb.Sentiment__c = 'Neutral';
                fb.Agent_Followed_Up__c = false;
            }

            // Compose comments — include product name so recommendation engine can parse it
            List<String> commentParts = new List<String>();
            if (String.isNotBlank(req.recommendedProduct)) {
                commentParts.add('Recommended product: ' + req.recommendedProduct + '.');
            }
            commentParts.add(acted ? 'Customer expressed interest.' : 'Customer was not interested.');
            if (String.isNotBlank(req.customerComment)) {
                commentParts.add('Customer comment: ' + req.customerComment);
            }
            fb.Comments__c = String.join(commentParts, ' ');

            insert fb;
            res.feedbackId = fb.Id;

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('CaptureFeedback_HF_Saathi', 'captureFeedback', ex, req.contactId);
        }

        return res;
    }

    private static String mapFeedbackType(String inputType) {
        if (inputType == null) return 'Suggestion';
        String t = inputType.toLowerCase().trim();
        if (t == 'recommendation' || t == 'suggestion') return 'Suggestion';
        if (t == 'csat') return 'CSAT';
        if (t == 'nps') return 'NPS';
        if (t == 'complaint') return 'Complaint';
        if (t == 'compliment') return 'Compliment';
        return 'Suggestion';
    }

    public class Request {
        @InvocableVariable(label='Contact ID' description='Salesforce Contact ID of the verified customer.' required=true)
        public String contactId;

        @InvocableVariable(label='Family ID' description='Salesforce Account (Family) ID.' required=false)
        public String familyId;

        @InvocableVariable(label='Feedback Type' description='Type: Recommendation, CSAT, Complaint, Compliment.' required=true)
        public String feedbackType;

        @InvocableVariable(label='Recommended Product' description='The product that was recommended (included in Comments for learning loop).' required=false)
        public String recommendedProduct;

        @InvocableVariable(label='Was Acted On' description='True if the customer expressed interest or proceeded.' required=false)
        public Boolean wasActedOn;

        @InvocableVariable(label='Rating' description='Customer rating 1–5 as a string.' required=false)
        public String rating;

        @InvocableVariable(label='Customer Comment' description='Free-text feedback from the customer.' required=false)
        public String customerComment;
    }

    public class Result {
        @InvocableVariable(label='Feedback ID' description='Salesforce ID of the created Feedback__c record.')
        public String feedbackId;
    }
}