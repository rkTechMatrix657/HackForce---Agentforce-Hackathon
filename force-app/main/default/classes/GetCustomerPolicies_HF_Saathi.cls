/**
 * Agentforce Apex Action: GetCustomerPolicies_HF_Saathi
 *
 * Returns HF Finance insurance policies for the verified customer by querying
 * the Opportunity object (Policy_Holder__c = contactId). All policy data lives
 * in CRM — no Data Cloud / ConnectApi queries used.
 */
public without sharing class GetCustomerPolicies_HF_Saathi {

    @InvocableMethod(
        label='Get Customer Policies'
        description='Returns all HF Finance insurance policies for the identified customer from the Opportunity object.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(fetchPolicies(req.contactId));
        }
        return results;
    }

    private static Result fetchPolicies(String contactId) {
        Result res = new Result();

        try {
            List<Opportunity> policies = [
                SELECT Id, Name, Policy_Number__c, Insurance__c, Premium__c,
                       Premium_Amount__c, Premium_Frequency__c, Sum_Assured__c,
                       Policy_Term__c, Activation_Date__c, StageName,
                       Opportunity_Type__c, Application_Number__c, CloseDate
                FROM Opportunity
                WHERE Policy_Holder__c = :contactId
                ORDER BY Activation_Date__c DESC NULLS LAST, CreatedDate DESC
                LIMIT 20
            ];

            if (policies.isEmpty()) {
                res.policySummary    = 'You do not have any policies on record with HF Finance. Would you like to explore our insurance options?';
                res.activePolicyCount = '0';
                res.heldInsuranceTypes = '';
                res.policyListJson   = '[]';
                return res;
            }

            List<String> policyLines = new List<String>();
            List<String> appLines    = new List<String>();
            List<String> jsonItems   = new List<String>();
            Set<String>  heldTypes   = new Set<String>();
            Integer activeCount      = 0;

            String[] months = new String[]{
                'January','February','March','April','May','June',
                'July','August','September','October','November','December'
            };

            for (Opportunity opp : policies) {
                Boolean isPolicy = (opp.StageName == 'Policy Number Generated'
                                 || opp.StageName == 'Activated'
                                 || opp.StageName == 'Active');
                Boolean isApplication = String.isNotBlank(opp.Application_Number__c)
                                     && opp.StageName != 'Policy Number Generated';

                if (String.isNotBlank(opp.Insurance__c)) heldTypes.add(opp.Insurance__c);

                if (isApplication) {
                    // Pending / new application created via chat
                    appLines.add('• App No: ' + opp.Application_Number__c
                        + ' | Plan: ' + (String.isNotBlank(opp.Insurance__c) ? opp.Insurance__c : opp.Name)
                        + ' | Premium: ' + (String.isNotBlank(opp.Premium__c) ? opp.Premium__c : '--')
                        + ' | Status: ' + opp.StageName);
                } else {
                    // Active or issued policy
                    if (isPolicy) activeCount++;
                    String activationStr = '--';
                    if (opp.Activation_Date__c != null) {
                        Date d = opp.Activation_Date__c;
                        activationStr = d.day() + ' ' + months[d.month()-1] + ' ' + d.year();
                    }
                    policyLines.add('• ' + (String.isNotBlank(opp.Insurance__c) ? opp.Insurance__c : opp.Name)
                        + (String.isNotBlank(opp.Policy_Number__c) ? ' | Policy No: ' + opp.Policy_Number__c : '')
                        + ' | Sum Assured: ' + fmtCcy(opp.Sum_Assured__c)
                        + ' | Premium: ' + fmtCcy(opp.Premium_Amount__c)
                        + (String.isNotBlank(opp.Premium_Frequency__c) ? '/' + opp.Premium_Frequency__c : '')
                        + ' | Status: ' + opp.StageName
                        + ' | Activated: ' + activationStr);
                }

                jsonItems.add('{"policyNumber":"' + esc(opp.Policy_Number__c) + '",'
                    + '"insuranceType":"' + esc(opp.Insurance__c) + '",'
                    + '"premiumPlan":"' + esc(opp.Premium__c) + '",'
                    + '"sumAssured":' + (opp.Sum_Assured__c != null ? String.valueOf(opp.Sum_Assured__c) : 'null') + ','
                    + '"premiumAmount":' + (opp.Premium_Amount__c != null ? String.valueOf(opp.Premium_Amount__c) : 'null') + ','
                    + '"premiumFrequency":"' + esc(opp.Premium_Frequency__c) + '",'
                    + '"policyTerm":' + (opp.Policy_Term__c != null ? String.valueOf(opp.Policy_Term__c.intValue()) : 'null') + ','
                    + '"status":"' + esc(opp.StageName) + '",'
                    + '"applicationNumber":"' + esc(opp.Application_Number__c) + '",'
                    + '"opportunityId":"' + esc(opp.Id) + '"}');
            }

            List<String> summaryParts = new List<String>();
            if (!appLines.isEmpty()) {
                summaryParts.add('Your Pending Applications:\n' + String.join(appLines, '\n'));
            }
            if (!policyLines.isEmpty()) {
                summaryParts.add('Your HF Finance Policies:\n' + String.join(policyLines, '\n'));
            }

            res.policySummary      = summaryParts.isEmpty() ? 'No records found.' : String.join(summaryParts, '\n\n');
            res.activePolicyCount  = String.valueOf(activeCount);
            res.heldInsuranceTypes = String.join(new List<String>(heldTypes), ',');
            res.policyListJson     = '[' + String.join(jsonItems, ',') + ']';

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('GetCustomerPolicies_HF_Saathi', 'fetchPolicies', ex, contactId);
            res.policySummary     = 'Unable to retrieve your policies at this time. Please try again.';
            res.activePolicyCount = '0';
            res.heldInsuranceTypes = '';
            res.policyListJson    = '[]';
        }
        return res;
    }

    private static String fmtCcy(Decimal d) {
        if (d == null) return '--';
        return 'Rs.' + String.valueOf(d.setScale(0)).replaceAll('(\\d)(?=(\\d{2})+(?!\\d))', '$1,');
    }
    private static String esc(String s) {
        return s != null ? s.replace('"', '\\"') : '';
    }

    public class Request {
        @InvocableVariable(label='Contact ID' description='Salesforce Contact ID of the verified customer.' required=true)
        public String contactId;

        @InvocableVariable(label='Customer ID' description='HF Finance Customer ID — kept for backward compatibility, not used in CRM query.' required=false)
        public String customerId;
    }

    public class Result {
        @InvocableVariable(label='Policy Summary' description='Formatted list of all policies for the customer.')
        public String policySummary;

        @InvocableVariable(label='Active Policy Count' description='Number of currently active policies.')
        public String activePolicyCount;

        @InvocableVariable(label='Held Insurance Types' description='Comma-separated list of insurance types the customer already holds.')
        public String heldInsuranceTypes;

        @InvocableVariable(label='Policy List JSON' description='JSON array of policy records for downstream actions.')
        public String policyListJson;
    }
}