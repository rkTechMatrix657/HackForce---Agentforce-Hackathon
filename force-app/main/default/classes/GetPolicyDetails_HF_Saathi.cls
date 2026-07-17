/**
 * Agentforce Apex Action: GetPolicyDetails_HF_Saathi
 *
 * Returns detailed information for a specific Opportunity (Policy) identified by
 * Policy_Number__c, scoped to the verified Contact to prevent cross-customer data leakage.
 *
 * Includes: sum assured, policy term, premium details, key dates, underwriting status,
 * and the next best action from Data Cloud (Next_Best_Action__c).
 */
public with sharing class GetPolicyDetails_HF_Saathi {

    @InvocableMethod(
        label='Get Policy Details'
        description='Returns full details of a specific HF Finance insurance policy by policy number, verified against the customer\'s Contact ID.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(fetchDetails(req.contactId, req.policyNumber));
        }
        return results;
    }

    private static Result fetchDetails(String contactId, String policyNumber) {
        Result res = new Result();

        if (String.isBlank(policyNumber)) {
            res.policyDetails = 'Please provide your policy number so I can look it up for you.';
            return res;
        }

        List<Opportunity> policies = [
            SELECT Id, Name, Policy_Number__c, Insurance__c, Premium_Type__c,
                   Premium__c, Premium_Amount__c, Premium_Frequency__c,
                   Sum_Assured__c, Policy_Term__c, StageName,
                   Activation_Date__c, Application_Date__c, Quote_Sent_Date__c,
                   CloseDate, Amount, Underwriting_Status__c, Opportunity_Type__c,
                   Next_Best_Action__c, Propensity_Score__c,
                   Policy_Holder__r.FirstName, Policy_Holder__r.LastName,
                   AccountId, Account.Name
            FROM Opportunity
            WHERE Policy_Number__c = :policyNumber.trim()
              AND Policy_Holder__c = :contactId
            LIMIT 1
        ];

        if (policies.isEmpty()) {
            res.policyDetails = 'I could not find a policy with number ' + policyNumber + ' linked to your account. Please check the number and try again.';
            return res;
        }

        Opportunity p = policies[0];
        res.opportunityId = p.Id;

        List<String> lines = new List<String>();
        lines.add('Policy Details for ' + safeStr(p.Insurance__c) + ':');
        lines.add('');
        lines.add('• Policy Number: ' + safeStr(p.Policy_Number__c));
        lines.add('• Insurance Type: ' + safeStr(p.Insurance__c));
        lines.add('• Status: ' + mapStageToLabel(p.StageName));
        lines.add('• Sum Assured: ' + formatCurrency(p.Sum_Assured__c));
        lines.add('• Policy Term: ' + (p.Policy_Term__c != null ? String.valueOf(Integer.valueOf(p.Policy_Term__c)) + ' years' : '—'));
        lines.add('• Premium Amount: ' + formatCurrency(p.Premium_Amount__c) + (String.isNotBlank(p.Premium_Frequency__c) ? ' / ' + p.Premium_Frequency__c : ''));
        lines.add('• Premium Type: ' + safeStr(p.Premium_Type__c));

        if (p.Activation_Date__c != null) {
            lines.add('• Policy Start Date: ' + formatDate(p.Activation_Date__c));
        }
        if (p.CloseDate != null && p.StageName != 'Activated') {
            lines.add('• Expected Activation Date: ' + formatDate(p.CloseDate));
        }
        if (String.isNotBlank(p.Underwriting_Status__c) && p.Underwriting_Status__c != 'Accepted') {
            lines.add('• Underwriting Status: ' + safeStr(p.Underwriting_Status__c));
        }

        res.policyDetails = String.join(lines, '\n');
        return res;
    }

    private static String mapStageToLabel(String stage) {
        if (stage == 'Activated') return 'Active ✓';
        if (stage == 'Payment Pending') return 'Payment Due';
        if (stage == 'Underwriting') return 'Under Review';
        if (stage == 'Application Submitted') return 'Application Submitted';
        if (stage == 'Not Interested') return 'Closed';
        return stage != null ? stage : 'Unknown';
    }

    private static String formatCurrency(Decimal amount) {
        if (amount == null) return '—';
        return '₹' + String.valueOf(amount.setScale(0)).replaceAll('(\\d)(?=(\\d{2})+(?!\\d))', '$1,');
    }

    private static String formatDate(Date d) {
        if (d == null) return '—';
        String[] months = new String[]{'January','February','March','April','May','June',
                                        'July','August','September','October','November','December'};
        return String.valueOf(d.day()) + ' ' + months[d.month() - 1] + ' ' + String.valueOf(d.year());
    }

    private static String safeStr(String val) {
        return val != null ? val : '—';
    }

    public class Request {
        @InvocableVariable(
            label='Contact ID'
            description='The Salesforce Contact ID of the verified customer.'
            required=true
        )
        public String contactId;

        @InvocableVariable(
            label='Policy Number'
            description='The policy number provided by the customer (stored in Opportunity.Policy_Number__c).'
            required=true
        )
        public String policyNumber;
    }

    public class Result {
        @InvocableVariable(label='Policy Details' description='Formatted details of the requested policy.')
        public String policyDetails;

        @InvocableVariable(label='Opportunity ID' description='Internal Salesforce Opportunity ID (not shown to customer).')
        public String opportunityId;
    }
}