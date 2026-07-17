public with sharing class HFSyncDeletePremiumPlan {

    public class Request {
        @InvocableVariable(required=true) public String sourceRecordId;
    }

    @InvocableMethod(label='HF: Delete Premium Plan (Data Cloud Sync)')
    public static void run(List<Request> requests) {
        Set<String> sourceIds = new Set<String>();
        for (Request r : requests) {
            sourceIds.add(r.sourceRecordId);
        }
        List<Premium_Plan__c> toDelete = [
            SELECT Id FROM Premium_Plan__c WHERE Source_Record_Id__c IN :sourceIds
        ];
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }
}