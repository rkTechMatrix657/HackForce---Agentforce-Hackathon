/**
 * Agentforce Apex Action: GetClaimDetails_HF_Saathi
 *
 * Returns claim-related Cases for the verified customer from CRM.
 * Claims are stored as Cases with Type = 'Claim', created via CreateClaim_HF_Saathi.
 * No Data Cloud / ConnectApi queries used.
 */
public without sharing class GetClaimDetails_HF_Saathi {

    @InvocableMethod(
        label='Get Claim Details'
        description='Returns claim records for the identified customer from CRM Case object (Type = Claim). Optionally filtered by policy number in the case description.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(fetchClaims(req.customerId, req.policyNumber));
        }
        return results;
    }

    private static Result fetchClaims(String customerId, String policyNumber) {
        Result res = new Result();
        try {
            // Look up Contact by Customer_ID__c to get ContactId
            List<Contact> contacts = [
                SELECT Id FROM Contact WHERE Customer_ID__c = :customerId LIMIT 1
            ];

            List<Case> claims;
            if (!contacts.isEmpty()) {
                String contactId = contacts[0].Id;
                claims = [
                    SELECT Id, CaseNumber, Subject, Status, Description,
                           Priority, CreatedDate, ClosedDate
                    FROM Case
                    WHERE ContactId = :contactId
                      AND Type = 'Claim'
                    ORDER BY CreatedDate DESC
                    LIMIT 10
                ];
            } else {
                claims = new List<Case>();
            }

            // Optional filter by policy number in description
            List<Case> filtered = new List<Case>();
            if (String.isNotBlank(policyNumber)) {
                for (Case c : claims) {
                    if (c.Description != null && c.Description.containsIgnoreCase(policyNumber)) {
                        filtered.add(c);
                    }
                }
                if (!filtered.isEmpty()) claims = filtered;
            }

            if (claims.isEmpty()) {
                res.claimSummary  = String.isNotBlank(policyNumber)
                    ? 'No claims found for policy ' + policyNumber + '.'
                    : 'You have no claim records on file with HF Finance.';
                res.openClaimCount = '0';
                return res;
            }

            String[] months = new String[]{
                'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
            };
            List<String> lines = new List<String>{'Your HF Finance Claims:\n'};
            Integer openCount  = 0;

            for (Case c : claims) {
                Boolean isOpen = (c.Status != 'Closed' && c.Status != 'Resolved');
                if (isOpen) openCount++;
                Date cd = c.CreatedDate.date();
                String dateStr = cd.day() + ' ' + months[cd.month()-1] + ' ' + cd.year();

                lines.add('• Case No: ' + c.CaseNumber
                    + ' | ' + (String.isNotBlank(c.Subject) ? c.Subject : 'Claim Request')
                    + ' | Status: ' + (isOpen ? 'Open — ' : '') + c.Status
                    + ' | Filed: ' + dateStr);
            }

            if (openCount > 0) {
                lines.add('\nYou have ' + openCount + ' open claim(s). Would you like to raise a support case for follow-up?');
            }

            res.claimSummary   = String.join(lines, '\n');
            res.openClaimCount = String.valueOf(openCount);

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('GetClaimDetails_HF_Saathi', 'fetchClaims', ex, customerId);
            res.claimSummary   = 'Unable to retrieve your claim records at this time. Please try again.';
            res.openClaimCount = '0';
        }
        return res;
    }

    public class Request {
        @InvocableVariable(label='Customer ID' description='HF Finance Customer_ID__c.' required=true)
        public String customerId;

        @InvocableVariable(label='Policy Number' description='Optional: filter claims for a specific policy number.' required=false)
        public String policyNumber;
    }

    public class Result {
        @InvocableVariable(label='Claim Summary' description='Formatted list of claims for the customer.')
        public String claimSummary;

        @InvocableVariable(label='Open Claim Count' description='Number of currently open/in-progress claims.')
        public String openClaimCount;
    }
}