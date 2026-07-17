/**
 * Agentforce Apex Action: GetCustomerCases_HF_Saathi
 *
 * Returns support cases associated with the verified customer Contact.
 * Used by the CaseManagement subagent to display existing cases to the customer.
 *
 * Orders by: open cases first, then by most recently modified.
 * Shows Case Number (not internal Case ID) to the customer.
 */
public with sharing class GetCustomerCases_HF_Saathi {

    @InvocableMethod(
        label='Get Customer Cases'
        description='Returns a formatted list of all support cases associated with the identified HF Finance customer, ordered by open cases first and most recent first.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(fetchCases(req.contactId));
        }
        return results;
    }

    private static Result fetchCases(String contactId) {
        Result res = new Result();

        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Description, Status,
                   CreatedDate, LastModifiedDate, ClosedDate,
                   Priority, Type
            FROM Case
            WHERE ContactId = :contactId
            ORDER BY LastModifiedDate DESC
            LIMIT 10
        ];

        // Sort open cases first in Apex (CASE in SOQL ORDER BY is not supported)
        cases.sort(new CaseComparator());

        if (cases.isEmpty()) {
            res.caseList = 'You have no support cases on record with HF Finance. ' +
                'If you\'d like to raise a new case, just let me know the details.';
            res.openCaseCount = '0';
            return res;
        }

        Integer openCount = 0;
        List<String> lines = new List<String>();
        lines.add('Your HF Finance Support Cases:\n');

        for (Case c : cases) {
            Boolean isOpen = (c.Status != 'Closed' && c.Status != 'Resolved');
            if (isOpen) openCount++;

            String statusLabel = isOpen ? '🔵 ' + c.Status : '✓ Closed';
            List<String> caseLine = new List<String>();
            caseLine.add('• Case No: ' + c.CaseNumber);
            caseLine.add('  Subject: ' + (String.isNotBlank(c.Subject) ? c.Subject : 'General Inquiry'));
            caseLine.add('  Status: ' + statusLabel);
            caseLine.add('  Raised: ' + formatDateTime(c.CreatedDate));
            if (!isOpen && c.ClosedDate != null) {
                caseLine.add('  Resolved: ' + formatDateTime(c.ClosedDate));
            }
            lines.add(String.join(caseLine, '\n'));
        }

        if (openCount > 0) {
            lines.add('\nYou have ' + openCount + ' open case(s). ' +
                'Would you like more details on any of these?');
        }

        res.caseList = String.join(lines, '\n');
        res.openCaseCount = String.valueOf(openCount);
        return res;
    }

    private static String formatDateTime(Datetime dt) {
        if (dt == null) return '—';
        Date d = dt.date();
        String[] months = new String[]{'January','February','March','April','May','June',
                                        'July','August','September','October','November','December'};
        return String.valueOf(d.day()) + ' ' + months[d.month() - 1] + ' ' + String.valueOf(d.year());
    }

    public class Request {
        @InvocableVariable(
            label='Contact ID'
            description='The Salesforce Contact ID of the verified customer.'
            required=true
        )
        public String contactId;
    }

    public class Result {
        @InvocableVariable(label='Case List' description='Formatted list of the customer\'s support cases.')
        public String caseList;

        @InvocableVariable(label='Open Case Count' description='Number of currently open cases.')
        public String openCaseCount;
    }

    private class CaseComparator implements Comparator<Case> {
        private Integer statusOrder(String status) {
            if (status == 'New')         return 0;
            if (status == 'In Progress') return 1;
            if (status == 'Escalated')   return 2;
            if (status == 'On Hold')     return 3;
            return 4; // Closed / Resolved
        }
        public Integer compare(Case a, Case b) {
            Integer oa = statusOrder(a.Status);
            Integer ob = statusOrder(b.Status);
            return oa - ob;
        }
    }
}