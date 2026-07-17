public with sharing class HFSyncDeleteInsuranceProduct {

    public class Request {
        @InvocableVariable(required=true) public String sourceRecordId;
    }

    @InvocableMethod(label='HF: Delete Insurance Product (Data Cloud Sync)')
    public static void run(List<Request> requests) {
        Set<String> sourceIds = new Set<String>();
        for (Request r : requests) {
            sourceIds.add(r.sourceRecordId);
        }
        List<Insurance_Product__c> toDelete = [
            SELECT Id FROM Insurance_Product__c WHERE Source_Record_Id__c IN :sourceIds
        ];
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }
}