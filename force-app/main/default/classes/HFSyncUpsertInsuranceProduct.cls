public with sharing class HFSyncUpsertInsuranceProduct {

    public class Request {
        @InvocableVariable(required=true) public String sourceRecordId;
        @InvocableVariable public String productName;
        @InvocableVariable public String productCode;
        @InvocableVariable public String insuranceType;
        @InvocableVariable public String category;
        @InvocableVariable public String subCategory;
        @InvocableVariable public String description;
        @InvocableVariable public Decimal sumAssuredMin;
        @InvocableVariable public Decimal sumAssuredMax;
        @InvocableVariable public Decimal policyTermMin;
        @InvocableVariable public Decimal policyTermMax;
    }

    @InvocableMethod(label='HF: Upsert Insurance Product (Data Cloud Sync)')
    public static void run(List<Request> requests) {
        List<Insurance_Product__c> records = new List<Insurance_Product__c>();
        for (Request r : requests) {
            records.add(new Insurance_Product__c(
                Source_Record_Id__c = r.sourceRecordId,
                Name = r.productName,
                Product_Code__c = r.productCode,
                Insurance_Type__c = r.insuranceType,
                Category__c = r.category,
                Sub_Category__c = r.subCategory,
                Description__c = r.description,
                Sum_Assured_Min__c = r.sumAssuredMin,
                Sum_Assured_Max__c = r.sumAssuredMax,
                Policy_Term_Min__c = r.policyTermMin,
                Policy_Term_Max__c = r.policyTermMax
            ));
        }
        if (!records.isEmpty()) {
            upsert records Source_Record_Id__c;
        }
    }
}