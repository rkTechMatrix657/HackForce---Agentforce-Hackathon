/**
 * Agentforce Apex Action: CreateCase_HF_Saathi
 *
 * Creates a new support Case in Salesforce for the verified HF Finance customer.
 *
 * Sets:
 *   - ContactId = verified Contact ID
 *   - AccountId = Family ID
 *   - Subject, Description = provided by agent/customer
 *   - Status = 'New'
 *   - Origin = 'Chat' (HF Saathi conversation)
 *
 * Embeds the MessagingSession ID in the Description so the service representative
 * can review the full conversation context, fulfilling the requirement to store
 * the conversation against the case.
 *
 * Returns the Case Number (not internal Case ID) for display to the customer.
 */
public with sharing class CreateCase_HF_Saathi {

    @InvocableMethod(
        label='Create Support Case'
        description='Creates a new HF Finance support case for the identified customer, linked to their Contact, Family Account, and the active chat session for full conversation context.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(createCase(req));
        }
        return results;
    }

    private static Result createCase(Request req) {
        Result res = new Result();

        if (String.isBlank(req.contactId) || String.isBlank(req.caseSubject)) {
            res.outcomeMessage = 'Unable to create the case — please provide a subject for the issue and try again.';
            return res;
        }

        try {
            Case newCase = new Case();
            newCase.ContactId = req.contactId;
            if (String.isNotBlank(req.familyId)) newCase.AccountId = req.familyId;
            newCase.Subject   = req.caseSubject.trim();
            newCase.Status    = 'New';
            newCase.Origin    = 'Chat';
            newCase.Priority  = 'Medium';

            // Build description including session context
            List<String> descParts = new List<String>();
            if (String.isNotBlank(req.caseDescription)) {
                descParts.add(req.caseDescription.trim());
            }
            if (String.isNotBlank(req.messagingSessionId)) {
                descParts.add('[HF Saathi Session: ' + req.messagingSessionId + ']');
            }
            newCase.Description = String.join(descParts, '\n\n');

            insert newCase;

            // Fetch case number (auto-assigned after insert)
            Case inserted = [SELECT CaseNumber FROM Case WHERE Id = :newCase.Id LIMIT 1];

            res.caseNumber    = inserted.CaseNumber;
            res.outcomeMessage =
                'Your support case has been raised successfully!\n' +
                'Case Number: ' + inserted.CaseNumber + '\n\n' +
                'An HF Finance service representative will review your case and get back to you within 2 business days. ' +
                'You can reference this case number in any future communication. Is there anything else I can help you with?';

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('CreateCase_HF_Saathi', 'createCase', ex, req.contactId);
            res.outcomeMessage = 'I encountered an error while creating your case. Please try again or contact HF Finance support directly.';
        }

        return res;
    }

    public class Request {
        @InvocableVariable(label='Contact ID' description='Salesforce Contact ID of the verified customer.' required=true)
        public String contactId;

        @InvocableVariable(label='Family ID' description='Salesforce Account (Family) ID.' required=false)
        public String familyId;

        @InvocableVariable(label='Messaging Session ID' description='Active MessagingSession ID — embedded in case description for full conversation context.' required=false)
        public String messagingSessionId;

        @InvocableVariable(label='Case Subject' description='Brief subject for the case (under 7 words).' required=true)
        public String caseSubject;

        @InvocableVariable(label='Case Description' description='2-3 sentence description of the customer\'s issue.' required=false)
        public String caseDescription;
    }

    public class Result {
        @InvocableVariable(label='Case Number' description='The Case Number assigned by Salesforce (displayed to customer).')
        public String caseNumber;

        @InvocableVariable(label='Outcome Message' description='Confirmation message for the customer including the case number.')
        public String outcomeMessage;
    }
}