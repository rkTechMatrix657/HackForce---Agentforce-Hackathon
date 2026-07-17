public without sharing class CaseCommentTriggerHandler {

    public static void afterInsert(List<CaseComment> newComments) {
        Set<Id> caseIds = new Set<Id>();
        for (CaseComment cc : newComments) {
            if (cc.IsPublished) {
                caseIds.add(cc.ParentId);
            }
        }
        if (caseIds.isEmpty()) {
            return;
        }

        Map<Id, Case> caseById = new Map<Id, Case>([
            SELECT Id, ContactId FROM Case WHERE Id IN :caseIds AND ContactId != null
        ]);
        if (caseById.isEmpty()) {
            return;
        }

        Set<Id> contactIds = new Set<Id>();
        for (Case c : caseById.values()) {
            contactIds.add(c.ContactId);
        }

        Map<Id, Id> portalUserIdByContactId = new Map<Id, Id>();
        for (User u : [SELECT Id, ContactId FROM User WHERE ContactId IN :contactIds AND IsActive = true]) {
            portalUserIdByContactId.put(u.ContactId, u.Id);
        }

        Set<Id> commenterIds = new Set<Id>();
        for (CaseComment cc : newComments) {
            commenterIds.add(cc.CreatedById);
        }
        Map<Id, String> nameByUserId = new Map<Id, String>();
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :commenterIds]) {
            nameByUserId.put(u.Id, u.Name);
        }

        List<Case_Notification__c> toInsert = new List<Case_Notification__c>();
        for (CaseComment cc : newComments) {
            if (!cc.IsPublished) {
                continue;
            }
            Case parentCase = caseById.get(cc.ParentId);
            if (parentCase == null) {
                continue;
            }
            Id portalUserId = portalUserIdByContactId.get(parentCase.ContactId);
            if (portalUserId == null || portalUserId == cc.CreatedById) {
                continue;
            }

            Case_Notification__c note = new Case_Notification__c();
            note.Contact__c = parentCase.ContactId;
            note.Case__c = parentCase.Id;
            note.Commenter_Name__c = nameByUserId.get(cc.CreatedById);
            String body = cc.CommentBody == null ? '' : cc.CommentBody;
            note.Comment_Preview__c = body.length() > 255 ? body.substring(0, 255) : body;
            toInsert.add(note);
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }
}