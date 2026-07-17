/**
 * Agentforce Apex Action: CreateClaim_HF_Saathi
 *
 * Creates a claim-related Case record in Salesforce CRM and stores the
 * claim initiation request. Since Claim_c_ExternalOrgSF__dlm is a Data Cloud
 * read-only DMO (source: external PAS), new claim requests are created as
 * Cases in CRM (Origin = 'Claim') for the HF Finance operations team to
 * process in the PAS. The MessagingSession ID is embedded for full context.
 *
 * Case fields used:
 *   Subject   : "Claim Request - <Insurance Type> - <Policy Number>"
 *   Type      : "Claim"
 *   Origin    : "Chat"
 *   Description: claim details + policy number + reason
 */
public with sharing class CreateClaim_HF_Saathi {

    @InvocableMethod(
        label='Create Claim Request'
        description='Initiates a new insurance claim by creating a Claim-type Case in Salesforce linked to the customer\'s Contact, Account, and active chat session. The operations team processes the claim in the PAS from this case.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(createClaim(req));
        }
        return results;
    }

    private static Result createClaim(Request req) {
        Result res = new Result();

        if (String.isBlank(req.contactId) || String.isBlank(req.policyNumber)) {
            res.outcomeMessage = 'Please provide the policy number for which you want to raise a claim.';
            return res;
        }

        try {
            String subject = 'Claim Request -- ' +
                (String.isNotBlank(req.insuranceType) ? req.insuranceType + ' -- ' : '') +
                req.policyNumber.trim();

            List<String> descParts = new List<String>();
            descParts.add('Policy Number: ' + req.policyNumber.trim());
            if (String.isNotBlank(req.claimType)) descParts.add('Claim Type: ' + req.claimType);
            if (String.isNotBlank(req.claimReason)) descParts.add('Reason: ' + req.claimReason);
            if (req.claimAmount != null && req.claimAmount > 0) {
                descParts.add('Estimated Claim Amount: Rs.' + String.valueOf(req.claimAmount.setScale(0)));
            }
            if (String.isNotBlank(req.incidentDate)) descParts.add('Incident Date: ' + req.incidentDate);
            if (String.isNotBlank(req.messagingSessionId)) {
                descParts.add('[HF Saathi Session: ' + req.messagingSessionId + ']');
            }

            Case newCase = new Case();
            newCase.ContactId   = req.contactId;
            if (String.isNotBlank(req.familyId)) newCase.AccountId = req.familyId;
            newCase.Subject     = subject;
            newCase.Type        = 'Claim';
            newCase.Origin      = 'Chat';
            newCase.Priority    = 'High';
            newCase.Status      = 'New';
            newCase.Description = String.join(descParts, '\n');
            insert newCase;

            Case inserted = [SELECT CaseNumber FROM Case WHERE Id = :newCase.Id LIMIT 1];
            res.caseNumber    = inserted.CaseNumber;
            res.outcomeMessage = 'Your claim request has been registered successfully!\n'
                + 'Case Number: ' + inserted.CaseNumber + '\n\n'
                + 'An HF Finance claims specialist will contact you within 1-2 business days to guide you through the next steps. '
                + 'Please keep your policy document and relevant medical/incident records handy.';

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('CreateClaim_HF_Saathi', 'createClaim', ex, req.contactId);
            res.outcomeMessage = 'I encountered an issue registering your claim. Please try again or call our claims helpline.';
        }

        return res;
    }

    public class Request {
        @InvocableVariable(label='Contact ID' required=true)
        public String contactId;
        @InvocableVariable(label='Family ID' required=false)
        public String familyId;
        @InvocableVariable(label='Policy Number' description='Policy number against which the claim is being raised.' required=true)
        public String policyNumber;
        @InvocableVariable(label='Insurance Type' description='Type of insurance (Term Life, Health, etc.)' required=false)
        public String insuranceType;
        @InvocableVariable(label='Claim Type' description='Type of claim: Death, Maturity, Health, Accident, etc.' required=false)
        public String claimType;
        @InvocableVariable(label='Claim Reason' description='Brief description of the claim reason from the customer.' required=false)
        public String claimReason;
        @InvocableVariable(label='Claim Amount' description='Estimated claim amount provided by the customer.' required=false)
        public Decimal claimAmount;
        @InvocableVariable(label='Incident Date' description='Date of the incident (death, accident, diagnosis, etc.)' required=false)
        public String incidentDate;
        @InvocableVariable(label='Messaging Session ID' description='Active MessagingSession ID for conversation context.' required=false)
        public String messagingSessionId;
    }

    public class Result {
        @InvocableVariable(label='Case Number' description='Case Number of the created claim case (displayed to customer).')
        public String caseNumber;
        @InvocableVariable(label='Outcome Message' description='Confirmation or error message for the customer.')
        public String outcomeMessage;
    }
}