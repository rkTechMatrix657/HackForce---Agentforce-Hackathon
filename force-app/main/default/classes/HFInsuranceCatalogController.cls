public with sharing class HFInsuranceCatalogController {

    private static final Pattern PREMIUM_AMOUNT_PATTERN = Pattern.compile('(\\d+(?:\\.\\d+)?)\\s*INR');

    @AuraEnabled(cacheable=true)
    public static List<ProductWrapper> getCatalog() {
        Map<String, ProductWrapper> byProductId = new Map<String, ProductWrapper>();
        List<ProductWrapper> result = new List<ProductWrapper>();

        for (Product2_ExternalOrgSF__dlm p : [
            SELECT Id__c, Name__c, ProductCode__c, Insurance_Type_c__c, Category_c__c, Sub_Category_c__c,
                   Description__c, Sum_Assured_Min_c__c, Sum_Assured_Max_c__c, Policy_Term_Min_c__c, Policy_Term_Max_c__c
            FROM Product2_ExternalOrgSF__dlm
        ]) {
            ProductWrapper w = new ProductWrapper();
            w.id = p.Id__c;
            w.name = p.Name__c;
            w.code = p.ProductCode__c;
            w.insuranceType = p.Insurance_Type_c__c;
            w.category = p.Category_c__c;
            w.subCategory = p.Sub_Category_c__c;
            w.description = p.Description__c;
            w.sumAssuredMin = p.Sum_Assured_Min_c__c;
            w.sumAssuredMax = p.Sum_Assured_Max_c__c;
            w.policyTermMin = p.Policy_Term_Min_c__c;
            w.policyTermMax = p.Policy_Term_Max_c__c;
            w.plans = new List<PlanWrapper>();
            byProductId.put(w.id, w);
            result.add(w);
        }

        for (Premium__dlm pr : [
            SELECT Id__c, Name__c, Premium_Amount_c__c, Premium_Frequency_c__c, Sum_Assured_c__c, Policy_Term_c__c, Age_Band_c__c, Product_c__c
            FROM Premium__dlm
            WHERE Active_c__c = TRUE
        ]) {
            ProductWrapper w = byProductId.get(pr.Product_c__c);
            if (w == null) {
                continue;
            }
            PlanWrapper pw = new PlanWrapper();
            pw.id = pr.Id__c;
            pw.name = pr.Name__c;
            pw.premiumAmount = pr.Premium_Amount_c__c != null ? pr.Premium_Amount_c__c : parsePremiumAmount(pr.Name__c);
            pw.frequency = pr.Premium_Frequency_c__c;
            pw.sumAssured = pr.Sum_Assured_c__c;
            pw.policyTerm = pr.Policy_Term_c__c;
            pw.ageBand = pr.Age_Band_c__c;
            w.plans.add(pw);
        }

        return result;
    }

    public static Decimal parsePremiumAmount(String name) {
        if (String.isBlank(name)) {
            return null;
        }
        Matcher m = PREMIUM_AMOUNT_PATTERN.matcher(name);
        if (m.find()) {
            return Decimal.valueOf(m.group(1));
        }
        return null;
    }

    public class ProductWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String code;
        @AuraEnabled public String insuranceType;
        @AuraEnabled public String category;
        @AuraEnabled public String subCategory;
        @AuraEnabled public String description;
        @AuraEnabled public Decimal sumAssuredMin;
        @AuraEnabled public Decimal sumAssuredMax;
        @AuraEnabled public Decimal policyTermMin;
        @AuraEnabled public Decimal policyTermMax;
        @AuraEnabled public List<PlanWrapper> plans;
    }

    public class PlanWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal premiumAmount;
        @AuraEnabled public String frequency;
        @AuraEnabled public Decimal sumAssured;
        @AuraEnabled public Decimal policyTerm;
        @AuraEnabled public String ageBand;
    }
}