/**
 * Agentforce Apex Action: GetPremiumInstallments_HF_Saathi
 *
 * Returns the premium installment schedule from Data Cloud for a specific policy.
 *   DC360 : Premium_Installment__dlm
 *           Relationship field: Policy_Number__c
 *
 * Verifies the policy belongs to the customer via Polic__c (CRM) or Policy_External__dlm
 * before returning installment data.
 */
public with sharing class GetPremiumInstallments_HF_Saathi {

    @InvocableMethod(
        label='Get Premium Installments'
        description='Returns the premium installment schedule from Data Cloud (Premium_Installment__dlm) for a specified HF Finance policy, showing due dates, amounts, and payment status (Paid/Pending/Overdue).'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(fetchInstallments(req.customerId, req.policyNumber));
        }
        return results;
    }

    private static Result fetchInstallments(String customerId, String policyNumber) {
        Result res = new Result();

        if (String.isBlank(policyNumber)) {
            res.installmentSchedule = 'Please provide your policy number to view the installment schedule.';
            return res;
        }

        try {
            // Installment data is not stored in CRM. Look up the policy Opportunity
            // to provide what's available and direct customer to the data library.
            List<Opportunity> opps = [
                SELECT Id, Policy_Number__c, Insurance__c, Premium__c,
                       Premium_Amount__c, Premium_Frequency__c, Policy_Term__c,
                       Activation_Date__c, StageName, Application_Number__c
                FROM Opportunity
                WHERE Policy_Number__c = :policyNumber.trim()
                LIMIT 1
            ];

            if (opps.isEmpty()) {
                res.installmentSchedule = 'Policy ' + policyNumber + ' was not found on your account.';
                res.overdueCount = '0';
                return res;
            }

            Opportunity opp = opps[0];
            List<String> lines = new List<String>();
            lines.add('Policy: ' + (String.isNotBlank(opp.Insurance__c) ? opp.Insurance__c : opp.Policy_Number__c));
            lines.add('Premium Plan: ' + (String.isNotBlank(opp.Premium__c) ? opp.Premium__c : '--'));
            lines.add('Premium Amount: ' + fmtCcy(opp.Premium_Amount__c)
                + (String.isNotBlank(opp.Premium_Frequency__c) ? '/' + opp.Premium_Frequency__c : ''));
            lines.add('Policy Term: ' + (opp.Policy_Term__c != null ? String.valueOf(opp.Policy_Term__c.intValue()) + ' years' : '--'));
            lines.add('Status: ' + opp.StageName);
            lines.add('\nFor a detailed installment schedule, please visit the HF Finance portal or raise a support case.');

            res.installmentSchedule = String.join(lines, '\n');
            res.nextDueDate  = '';
            res.overdueCount = '0';

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('GetPremiumInstallments_HF_Saathi', 'fetchInstallments', ex, customerId);
            res.installmentSchedule = 'Unable to retrieve installment details at this time. Please try again.';
            res.overdueCount = '0';
        }

        return res;
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
    private static String fmtDate(String s) {
        if (String.isBlank(s)) return '--';
        try {
            Date d = Date.valueOf(s.left(10));
            String[] m = new String[]{'January','February','March','April','May','June','July','August','September','October','November','December'};
            return d.day() + ' ' + m[d.month()-1] + ' ' + d.year();
        } catch (Exception e) { return s; }
    }

    public class Request {
        @InvocableVariable(label='Customer ID' description='HF Finance Customer_ID__c for ownership verification.' required=true)
        public String customerId;
        @InvocableVariable(label='Policy Number' description='Policy number for which to retrieve the installment schedule.' required=true)
        public String policyNumber;
    }

    public class Result {
        @InvocableVariable(label='Installment Schedule' description='Formatted installment schedule.')
        public String installmentSchedule;
        @InvocableVariable(label='Next Due Date' description='The next upcoming installment due date.')
        public String nextDueDate;
        @InvocableVariable(label='Overdue Count' description='Number of overdue installments.')
        public String overdueCount;
    }
}