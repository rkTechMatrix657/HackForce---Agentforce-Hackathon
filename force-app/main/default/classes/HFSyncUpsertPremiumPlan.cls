public with sharing class HFSyncUpsertPremiumPlan {

    public class Request {
        @InvocableVariable(required=true) public String sourceRecordId;
        @InvocableVariable public String planName;
        @InvocableVariable(required=true) public String productSourceId;
        @InvocableVariable public Decimal premiumAmount;
        @InvocableVariable public String premiumFrequency;
        @InvocableVariable public Decimal sumAssured;
        @InvocableVariable public Decimal policyTerm;
        @InvocableVariable public String ageBand;
        @InvocableVariable public Boolean active;
    }

    @InvocableMethod(label='HF: Upsert Premium Plan (Data Cloud Sync)')
    public static void run(List<Request> requests) {
        Set<String> productSourceIds = new Set<String>();
        for (Request r : requests) {
            productSourceIds.add(r.productSourceId);
        }
        Map<String, Id> productIdBySourceId = new Map<String, Id>();
        for (Insurance_Product__c p : [
            SELECT Id, Source_Record_Id__c FROM Insurance_Product__c WHERE Source_Record_Id__c IN :productSourceIds
        ]) {
            productIdBySourceId.put(p.Source_Record_Id__c, p.Id);
        }

        List<Premium_Plan__c> records = new List<Premium_Plan__c>();
        for (Request r : requests) {
            records.add(new Premium_Plan__c(
                Source_Record_Id__c = r.sourceRecordId,
                Name = r.planName,
                Insurance_Product__c = productIdBySourceId.get(r.productSourceId),
                Premium_Amount__c = r.premiumAmount,
                Premium_Frequency__c = r.premiumFrequency,
                Sum_Assured__c = r.sumAssured,
                Policy_Term__c = r.policyTerm,
                Age_Band__c = r.ageBand,
                Active__c = r.active == null ? true : r.active
            ));
        }
        if (!records.isEmpty()) {
            upsert records Source_Record_Id__c;
        }
    }
}