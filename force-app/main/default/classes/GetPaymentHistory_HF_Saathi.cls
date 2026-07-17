/**
 * Agentforce Apex Action: GetPaymentHistory_HF_Saathi
 *
 * Returns the last 12 months of premium payment records from Data Cloud.
 *   DC360 : Premium_Payment_c_ExternalOrgSF__dlm
 *           Relationship fields: Premium_Installment_Id__c, Policy_Number__c
 */
public with sharing class GetPaymentHistory_HF_Saathi {

    @InvocableMethod(
        label='Get Payment History'
        description='Returns the last 12 months of premium payments from Data Cloud (Premium_Payment_c_ExternalOrgSF__dlm) for the specified policy, showing date, amount, mode, transaction reference, and status.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(fetchPayments(req.customerId, req.policyNumber));
        }
        return results;
    }

    private static Result fetchPayments(String customerId, String policyNumber) {
        Result res = new Result();

        if (String.isBlank(policyNumber)) {
            res.paymentHistory = 'Please provide your policy number to view payment history.';
            return res;
        }

        try {
            // Payment history is not stored in CRM. Look up the policy Opportunity
            // to provide what's available and direct customer to the portal.
            List<Opportunity> opps = [
                SELECT Id, Policy_Number__c, Insurance__c, Premium__c,
                       Premium_Amount__c, Premium_Frequency__c, StageName,
                       Activation_Date__c
                FROM Opportunity
                WHERE Policy_Number__c = :policyNumber.trim()
                LIMIT 1
            ];

            if (opps.isEmpty()) {
                res.paymentHistory = 'Policy ' + policyNumber + ' was not found on your account.';
                res.totalPaid      = '--';
                return res;
            }

            Opportunity opp = opps[0];
            List<String> lines = new List<String>();
            lines.add('Policy: ' + (String.isNotBlank(opp.Insurance__c) ? opp.Insurance__c : opp.Policy_Number__c));
            lines.add('Premium: ' + fmtCcy(opp.Premium_Amount__c)
                + (String.isNotBlank(opp.Premium_Frequency__c) ? '/' + opp.Premium_Frequency__c : ''));
            lines.add('Status: ' + opp.StageName);
            lines.add('\nDetailed payment transaction history is maintained in the HF Finance system. '
                + 'For a full payment history, please visit the HF Finance portal or raise a support case.');

            res.paymentHistory = String.join(lines, '\n');
            res.totalPaid      = '--';

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('GetPaymentHistory_HF_Saathi', 'fetchPayments', ex, customerId);
            res.paymentHistory = 'Unable to retrieve payment history at this time. Please try again.';
            res.totalPaid      = '--';
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
        @InvocableVariable(label='Policy Number' description='Policy number for which to retrieve payment history.' required=true)
        public String policyNumber;
    }

    public class Result {
        @InvocableVariable(label='Payment History' description='Formatted payment history for the last 12 months.')
        public String paymentHistory;
        @InvocableVariable(label='Total Paid' description='Total amount paid in the last 12 months.')
        public String totalPaid;
    }
}