public with sharing class GetCaseComments_HF_Saathi {

    @InvocableMethod(
        label='Get Case Comments'
        description='Returns the most recent published comments for a specific support case, scoped to the verified customer Contact.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(fetchComments(req.caseNumber, req.contactId));
        }
        return results;
    }

    private static Result fetchComments(String caseNumber, String contactId) {
        Result res = new Result();
        try {
            List<Case> cases = [
                SELECT Id, CaseNumber, Subject, Status
                FROM Case
                WHERE CaseNumber = :caseNumber
                  AND ContactId  = :contactId
                LIMIT 1
            ];

            if (cases.isEmpty()) {
                res.comments = 'Case ' + caseNumber + ' was not found on your account. Please check the number and try again.';
                return res;
            }

            Case c = cases[0];
            List<CaseComment> comments = [
                SELECT CommentBody, CreatedDate, CreatedBy.Name
                FROM CaseComment
                WHERE ParentId    = :c.Id
                  AND IsPublished = true
                ORDER BY CreatedDate DESC
                LIMIT 5
            ];

            if (comments.isEmpty()) {
                res.comments = 'There are no updates on Case ' + caseNumber + ' (' + c.Subject + ') yet. '
                    + 'Status: ' + c.Status + '.';
                return res;
            }

            List<String> lines = new List<String>();
            lines.add('Latest updates on Case ' + caseNumber + ' — ' + c.Subject + ' (' + c.Status + '):\n');

            String[] months = new String[]{
                'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
            };
            for (CaseComment cc : comments) {
                Date d = cc.CreatedDate.date();
                String dateStr = d.day() + ' ' + months[d.month()-1] + ' ' + d.year();
                lines.add('• ' + dateStr + ' — ' + cc.CreatedBy.Name);
                lines.add('  ' + cc.CommentBody.trim());
                lines.add('');
            }

            res.comments = String.join(lines, '\n').trim();

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('GetCaseComments_HF_Saathi', 'fetchComments', ex, caseNumber);
            res.comments = 'Unable to retrieve case comments at this time. Please try again.';
        }
        return res;
    }

    public class Request {
        @InvocableVariable(label='Case Number' description='The case number to fetch comments for (e.g. 00001234).' required=true)
        public String caseNumber;

        @InvocableVariable(label='Contact ID' description='Verified customer Contact ID — ensures comments are only returned for the customer\'s own cases.' required=true)
        public String contactId;
    }

    public class Result {
        @InvocableVariable(label='Comments' description='Formatted recent case comments to display to the customer.')
        public String comments;
    }
}