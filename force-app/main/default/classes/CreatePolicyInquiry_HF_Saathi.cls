/**
 * Agentforce Apex Action: CreatePolicyInquiry_HF_Saathi
 *
 * Registers a customer's interest in a selected HF Finance premium plan by creating a
 * lightweight Opportunity at stage "New". This action intentionally does NOT set
 * Insurance__c or Premium__c — it only captures interest. Those fields are populated
 * later in the underwriting/application flow, by a separate process.
 *
 * Sets:
 *   - Name           = "<Contact Name> - <Interested Policy Name>"
 *   - Description    = free-text note that the interest was raised via HF Saathi
 *   - StageName      = "New"
 *   - AccountId      = Family Account ID
 *   - Policy_Holder__c (Contact) = verified Contact ID
 *   - Application_Number__c = auto-generated 10-char reference
 *
 * Also updates the Feedback__c recommendation log (Agent_Followed_Up__c = true)
 * if the customer acted on a prior recommendation.
 */
public with sharing class CreatePolicyInquiry_HF_Saathi {

    @InvocableMethod(
        label='Create Policy Inquiry'
        description='Registers a customer\'s interest in a selected premium plan by creating an Opportunity at the New stage, linked to the customer\'s Contact and Family Account. Does not set Insurance or Premium fields.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(createInquiry(req));
        }
        return results;
    }

    private static Result createInquiry(Request req) {
        Result res = new Result();

        if (String.isBlank(req.contactId) || String.isBlank(req.premiumPlan)) {
            res.outcomeMessage = 'Unable to register your interest — missing required details. Please try again.';
            return res;
        }

        try {
            // Determine New Business vs Cross-sell based on any already-activated policy
            // (kept deliberately simple — no Insurance__c filtering, since that field is not set here)
            List<Opportunity> anyActive = [
                SELECT Id FROM Opportunity
                WHERE Policy_Holder__c = :req.contactId
                  AND StageName = 'Activated'
                LIMIT 1
            ];
            String oppType = anyActive.isEmpty() ? 'New Business' : 'Cross-sell';

            // Retrieve contact name for the Opportunity Name
            List<Contact> contacts = [SELECT FirstName, LastName FROM Contact WHERE Id = :req.contactId LIMIT 1];
            String contactName = contacts.isEmpty() ? 'Customer' : contacts[0].FirstName + ' ' + contacts[0].LastName;

            // Extract the human-readable plan name for naming/description/email purposes only.
            // Premium format: "HF Jeevan Suraksha (HFLTR001/25-35 A/500 INR/20 TY)" -> "HF Jeevan Suraksha"
            String productDisplayName = req.premiumPlan.contains('(')
                ? req.premiumPlan.substring(0, req.premiumPlan.indexOf('(')).trim()
                : req.premiumPlan;

            // Auto-generate unique Application Number: HF + 8 alphanumeric chars = 10 chars total
            String appNumber = generateApplicationNumber();

            Opportunity opp = new Opportunity();
            opp.Name                  = contactName + ' - ' + productDisplayName;
            opp.AccountId             = req.familyId;
            opp.Policy_Holder__c      = req.contactId;       // Contact
            opp.StageName             = 'New';
            opp.CloseDate             = Date.today().addDays(30);
            opp.Opportunity_Type__c   = oppType;
            opp.LeadSource            = 'Web';
            opp.Application_Number__c = appNumber;
            opp.Description           = 'Policy interest raised via HF Saathi for ' + productDisplayName + '.' +
                (String.isNotBlank(req.messagingSessionId)
                    ? ' Session: ' + req.messagingSessionId : '');
            // Insurance__c and Premium__c are intentionally left untouched here.

            insert opp;

            // Mark the recommendation feedback as followed-up (learning loop)
            if (String.isNotBlank(req.messagingSessionId)) {
                markFeedbackFollowedUp(req.contactId, productDisplayName);
            }

            // Send confirmation email to the customer
            EmailMessagingController.sendPolicyEmail(
                req.contactId, opp.Id, productDisplayName, req.premiumPlan
            );

            res.opportunityId     = opp.Id;
            res.applicationNumber = appNumber;
            res.outcomeMessage =
                'Your policy interest has been registered!\n\n'
                + '📋 Application Number: ' + appNumber + '\n'
                + '🛡️ Plan: ' + productDisplayName + '\n'
                + '📅 Status: New\n\n'
                + 'An HF Finance representative will reach out within 24 hours. '
                + 'Is there anything else I can help you with?';

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('CreatePolicyInquiry_HF_Saathi', 'createInquiry', ex, req.contactId);
            res.outcomeMessage = 'I encountered an issue registering your interest. Please try again or raise a support case for assistance.';
        }

        return res;
    }

    private static String generateApplicationNumber() {
        final String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        String applicationNumber = 'HF';
        
        while (applicationNumber.length() < 10) {
            Integer index = Math.mod(Math.abs(Crypto.getRandomInteger()), chars.length());
            applicationNumber += chars.substring(index, index + 1);
        }
        
        return applicationNumber;
    }

    private static void markFeedbackFollowedUp(String contactId, String product) {
        try {
            // Long Text Area (Comments__c) cannot be used in SOQL WHERE — fetch recent records and filter in Apex
            List<Feedback__c> recentLogs = [
                SELECT Id, Agent_Followed_Up__c, Sentiment__c, Status__c, Comments__c
                FROM Feedback__c
                WHERE Family_Member__c = :contactId
                  AND Feedback_Type__c = 'Suggestion'
                  AND Agent_Followed_Up__c = false
                ORDER BY Feedback_Date__c DESC
                LIMIT 10
            ];
            for (Feedback__c fb : recentLogs) {
                if (fb.Comments__c != null && fb.Comments__c.containsIgnoreCase(product)) {
                    fb.Agent_Followed_Up__c = true;
                    fb.Sentiment__c = 'Positive';
                    fb.Status__c = 'Actioned';
                    update fb;
                    break;
                }
            }
        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('CreatePolicyInquiry_HF_Saathi', 'markFeedbackFollowedUp', ex, contactId);
        }
    }

    public class Request {
        @InvocableVariable(label='Contact ID' description='Salesforce Contact ID — policy holder.' required=true)
        public String contactId;

        @InvocableVariable(label='Family ID' description='Salesforce Account (Family) ID.' required=false)
        public String familyId;

        @InvocableVariable(label='Premium Plan' description='Full selected premium plan label. Required — used to name and describe the Opportunity.' required=true)
        public String premiumPlan;

        @InvocableVariable(label='Messaging Session ID' description='Active MessagingSession ID for conversation context.' required=false)
        public String messagingSessionId;
    }

    public class Result {
        @InvocableVariable(label='Outcome Message' description='Confirmation message including Application Number and Plan name. Always display this to the customer.')
        public String outcomeMessage;

        @InvocableVariable(label='Opportunity ID' description='Internal Salesforce Opportunity ID.')
        public String opportunityId;

        @InvocableVariable(label='Application Number' description='Auto-generated 10-character application reference (HF + 8 chars). Share this with the customer.')
        public String applicationNumber;
    }
}