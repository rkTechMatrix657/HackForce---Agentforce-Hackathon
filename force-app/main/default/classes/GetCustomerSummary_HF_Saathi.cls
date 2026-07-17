public without sharing class GetCustomerSummary_HF_Saathi {

    @InvocableMethod(
        label='Get Customer Summary'
        description='Returns a brief customer profile — KYC status, active policy count, open case count, and family segment — from Contact and Account.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(getSummary(req.contactId, req.familyId));
        }
        return results;
    }

    private static Result getSummary(String contactId, String familyId) {
        Result res = new Result();
        try {
            // ── Contact ───────────────────────────────────────────────────────────
            List<Contact> contacts = [
                SELECT Id, FirstName, LastName, Customer_ID__c,
                       KYC_Status__c, Life_Stage__c, Birthdate, Email, MobilePhone
                FROM Contact WHERE Id = :contactId LIMIT 1
            ];

            // ── Account (Family) ──────────────────────────────────────────────────
            Account family = null;
            if (String.isNotBlank(familyId)) {
                List<Account> accounts = [
                    SELECT Id, Name, Family_Segment__c, Number_of_Members__c,
                           Customer_Since__c
                    FROM Account WHERE Id = :familyId LIMIT 1
                ];
                if (!accounts.isEmpty()) family = accounts[0];
            }

            // ── Active policies (Opportunity) ─────────────────────────────────────
            Integer activePolicies = [
                SELECT COUNT() FROM Opportunity
                WHERE Policy_Holder__c = :contactId
                  AND StageName NOT IN ('Not Interested', 'Closed Lost')
            ];

            // ── Open cases ────────────────────────────────────────────────────────
            Integer openCases = [
                SELECT COUNT() FROM Case
                WHERE ContactId = :contactId
                  AND Status NOT IN ('Closed', 'Resolved')
            ];

            // ── Build summary ─────────────────────────────────────────────────────
            List<String> lines = new List<String>();

            if (!contacts.isEmpty()) {
                Contact c = contacts[0];
                String name = (String.isNotBlank(c.FirstName) ? c.FirstName : '')
                            + (String.isNotBlank(c.LastName)  ? ' ' + c.LastName : '');
                lines.add('Name: ' + name.trim());
                if (String.isNotBlank(c.Customer_ID__c)) lines.add('Customer ID: ' + c.Customer_ID__c);
                if (c.Birthdate != null) {
                    Integer age = c.Birthdate.daysBetween(Date.today()) / 365;
                    lines.add('Age: ' + age);
                }
                lines.add('KYC Status: ' + (String.isNotBlank(c.KYC_Status__c) ? c.KYC_Status__c : 'Not Available'));
                if (String.isNotBlank(c.Life_Stage__c)) lines.add('Life Stage: ' + c.Life_Stage__c);
            }

            lines.add('Active Policies: ' + activePolicies);
            lines.add('Open Cases: ' + openCases);

            if (family != null) {
                lines.add('Family: ' + family.Name);
                if (String.isNotBlank(family.Family_Segment__c)) lines.add('Segment: ' + family.Family_Segment__c);
                if (family.Number_of_Members__c != null) lines.add('Family Members: ' + family.Number_of_Members__c.intValue());
                if (family.Customer_Since__c != null) lines.add('Customer Since: ' + family.Customer_Since__c.year());
            }

            res.summary = String.join(lines, '\n');

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('GetCustomerSummary_HF_Saathi', 'getSummary', ex, contactId);
            res.summary = 'Unable to retrieve your profile at this time. Please try again.';
        }
        return res;
    }

    public class Request {
        @InvocableVariable(label='Contact ID' description='Salesforce Contact ID from the Messaging Session.' required=true)
        public String contactId;

        @InvocableVariable(label='Family ID' description='Salesforce Account (Family) ID from the Messaging Session.' required=false)
        public String familyId;
    }

    public class Result {
        @InvocableVariable(label='Summary' description='Brief profile summary including KYC status, active policies, open cases, and family details.')
        public String summary;
    }
}