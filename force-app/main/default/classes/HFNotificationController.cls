public without sharing class HFNotificationController {

    @AuraEnabled
    public static List<NotificationWrapper> getMyNotifications() {
        Id contactId = HFCustomerAccountController.getCurrentContactId();
        List<NotificationWrapper> result = new List<NotificationWrapper>();
        if (contactId == null) {
            return result;
        }

        for (Case_Notification__c n : [
            SELECT Id, Comment_Preview__c, Commenter_Name__c, Is_Read__c, CreatedDate,
                   Case__c, Case__r.CaseNumber, Case__r.Subject
            FROM Case_Notification__c
            WHERE Contact__c = :contactId
            ORDER BY CreatedDate DESC
            LIMIT 30
        ]) {
            NotificationWrapper w = new NotificationWrapper();
            w.id = n.Id;
            w.preview = n.Comment_Preview__c;
            w.commenterName = n.Commenter_Name__c;
            w.isRead = n.Is_Read__c;
            w.createdDate = n.CreatedDate;
            w.caseId = n.Case__c;
            w.caseNumber = n.Case__r != null ? n.Case__r.CaseNumber : null;
            w.caseSubject = n.Case__r != null ? n.Case__r.Subject : null;
            result.add(w);
        }
        return result;
    }

    @AuraEnabled
    public static void markNotificationRead(Id notificationId) {
        Id contactId = HFCustomerAccountController.getCurrentContactId();
        List<Case_Notification__c> notifs = [
            SELECT Id, Contact__c, Is_Read__c FROM Case_Notification__c WHERE Id = :notificationId LIMIT 1
        ];
        if (notifs.isEmpty() || contactId == null || notifs[0].Contact__c != contactId) {
            return;
        }
        if (!notifs[0].Is_Read__c) {
            notifs[0].Is_Read__c = true;
            update notifs[0];
        }
    }

    @AuraEnabled
    public static void markAllNotificationsRead() {
        Id contactId = HFCustomerAccountController.getCurrentContactId();
        if (contactId == null) {
            return;
        }
        List<Case_Notification__c> notifs = [
            SELECT Id, Is_Read__c
            FROM Case_Notification__c
            WHERE Contact__c = :contactId AND Is_Read__c = false
        ];
        for (Case_Notification__c n : notifs) {
            n.Is_Read__c = true;
        }
        if (!notifs.isEmpty()) {
            update notifs;
        }
    }

    public class NotificationWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String preview;
        @AuraEnabled public String commenterName;
        @AuraEnabled public Boolean isRead;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String caseSubject;
    }
}