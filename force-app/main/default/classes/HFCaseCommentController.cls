public without sharing class HFCaseCommentController {

    @AuraEnabled(cacheable=true)
    public static List<CommentWrapper> getCaseComments(Id caseId) {
        assertOwnership(caseId);
        List<CommentWrapper> result = new List<CommentWrapper>();

        List<CaseComment> comments = [
            SELECT Id, CommentBody, CreatedById, CreatedDate
            FROM CaseComment
            WHERE ParentId = :caseId AND IsPublished = true
            ORDER BY CreatedDate ASC
        ];

        Set<Id> userIds = new Set<Id>();
        for (CaseComment cc : comments) {
            userIds.add(cc.CreatedById);
        }
        Map<Id, String> nameById = new Map<Id, String>();
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :userIds]) {
            nameById.put(u.Id, u.Name);
        }

        Id myUserId = UserInfo.getUserId();
        for (CaseComment cc : comments) {
            CommentWrapper w = new CommentWrapper();
            w.id = cc.Id;
            w.body = cc.CommentBody;
            w.createdDate = cc.CreatedDate;
            w.authorName = nameById.get(cc.CreatedById);
            w.isMine = cc.CreatedById == myUserId;
            result.add(w);
        }
        return result;
    }

    @AuraEnabled
    public static String addCaseComment(Id caseId, String commentBody) {
        assertOwnership(caseId);
        if (String.isBlank(commentBody)) {
            throw new AuraHandledException('Please enter a comment.');
        }

        CaseComment cc = new CaseComment();
        cc.ParentId = caseId;
        cc.CommentBody = commentBody;
        cc.IsPublished = true;

        try {
            insert cc;
        } catch (Exception e) {
            throw new AuraHandledException('We could not add your comment. Please try again.');
        }
        return cc.Id;
    }

    private static void assertOwnership(Id caseId) {
        Id contactId = HFCustomerAccountController.getCurrentContactId();
        List<Case> cases = [SELECT Id, ContactId FROM Case WHERE Id = :caseId LIMIT 1];
        if (contactId == null || cases.isEmpty() || cases[0].ContactId != contactId) {
            throw new AuraHandledException('We could not find that case.');
        }
    }

    public class CommentWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String body;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String authorName;
        @AuraEnabled public Boolean isMine;
    }
}