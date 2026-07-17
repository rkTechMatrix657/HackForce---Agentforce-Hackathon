public without sharing class HFCustomerAccountController {

    @AuraEnabled(cacheable=true)
    public static List<PolicyWrapper> getMyPolicies() {
        String customerId = getCurrentCustomerId();
        List<PolicyWrapper> result = new List<PolicyWrapper>();
        if (String.isBlank(customerId)) {
            return result;
        }

        Map<String, Product2_ExternalOrgSF__dlm> productByCode = new Map<String, Product2_ExternalOrgSF__dlm>();
        for (Product2_ExternalOrgSF__dlm p : [
            SELECT ProductCode__c, Name__c, Insurance_Type_c__c, Sub_Category_c__c, Sum_Assured_Min_c__c, Sum_Assured_Max_c__c
            FROM Product2_ExternalOrgSF__dlm
        ]) {
            productByCode.put(p.ProductCode__c, p);
        }

        Map<String, Premium__dlm> premiumById = new Map<String, Premium__dlm>();
        for (Premium__dlm pr : [SELECT Id__c, Name__c, Premium_Amount_c__c FROM Premium__dlm]) {
            premiumById.put(pr.Id__c, pr);
        }

        for (Policy_External__dlm policy : [
            SELECT Policy_Number_c__c, Product_Code__c, Product_Premium_c__c, Premium_Frequency_c__c,
                   Premium_Amount_c__c, Premium_Collected_c__c, Sum_Assured_c__c, Policy_Status_c__c,
                   Start_Date_c__c, End_Date_c__c, Issue_Date_c__c, Installments_Paid_c__c,
                   Installments_Pending_c__c, Installments_Overdue_c__c, Installments_Per_Year_c__c
            FROM Policy_External__dlm
            WHERE Customer_Id__c = :customerId
            ORDER BY Issue_Date_c__c DESC
        ]) {
            PolicyWrapper w = new PolicyWrapper();
            w.policyNumber = policy.Policy_Number_c__c;
            w.status = policy.Policy_Status_c__c;
            w.startDate = policy.Start_Date_c__c;
            w.endDate = policy.End_Date_c__c;
            w.issueDate = policy.Issue_Date_c__c;
            w.frequency = policy.Premium_Frequency_c__c;
            w.installmentsPaid = policy.Installments_Paid_c__c;
            w.installmentsPending = policy.Installments_Pending_c__c;
            w.installmentsOverdue = policy.Installments_Overdue_c__c;
            w.installmentsPerYear = policy.Installments_Per_Year_c__c;
            w.sumAssured = policy.Sum_Assured_c__c;

            Product2_ExternalOrgSF__dlm product = productByCode.get(policy.Product_Code__c);
            if (product != null) {
                w.productName = product.Name__c;
                w.insuranceType = product.Insurance_Type_c__c;
                w.subCategory = product.Sub_Category_c__c;
                w.sumAssuredMin = product.Sum_Assured_Min_c__c;
                w.sumAssuredMax = product.Sum_Assured_Max_c__c;
            }

            Decimal premiumAmount = policy.Premium_Amount_c__c;
            if (premiumAmount == null) {
                Premium__dlm matchedPremium = premiumById.get(policy.Product_Premium_c__c);
                if (matchedPremium != null) {
                    premiumAmount = matchedPremium.Premium_Amount_c__c != null
                        ? matchedPremium.Premium_Amount_c__c
                        : HFInsuranceCatalogController.parsePremiumAmount(matchedPremium.Name__c);
                }
            }
            w.premiumAmount = premiumAmount;

            Decimal paid = policy.Installments_Paid_c__c != null ? policy.Installments_Paid_c__c : 0;
            Decimal pending = policy.Installments_Pending_c__c != null ? policy.Installments_Pending_c__c : 0;
            Decimal total = paid + pending;
            w.progressPercent = total > 0 ? (paid * 100 / total).intValue() : 0;

            result.add(w);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<ClaimWrapper> getMyClaims() {
        String customerId = getCurrentCustomerId();
        List<ClaimWrapper> result = new List<ClaimWrapper>();
        if (String.isBlank(customerId)) {
            return result;
        }

        for (Claim_c_ExternalOrgSF__dlm claim : [
            SELECT Claim_Number_c__c, Policy_Number__c, Claim_Date_c__c, Claim_Type_c__c,
                   Claimed_Amount_c__c, Approved_Amount_c__c, Status_c__c
            FROM Claim_c_ExternalOrgSF__dlm
            WHERE Customer_Id__c = :customerId
            ORDER BY Claim_Date_c__c DESC
        ]) {
            ClaimWrapper w = new ClaimWrapper();
            w.claimNumber = claim.Claim_Number_c__c;
            w.policyNumber = claim.Policy_Number__c;
            w.claimDate = claim.Claim_Date_c__c;
            w.claimType = claim.Claim_Type_c__c;
            w.claimedAmount = claim.Claimed_Amount_c__c;
            w.approvedAmount = claim.Approved_Amount_c__c;
            w.status = claim.Status_c__c;
            result.add(w);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<PaymentWrapper> getMyPayments() {
        String customerId = getCurrentCustomerId();
        List<PaymentWrapper> result = new List<PaymentWrapper>();
        if (String.isBlank(customerId)) {
            return result;
        }

        Map<String, Decimal> premiumByPolicy = getPremiumAmountByPolicyNumber(customerId);
        if (premiumByPolicy.isEmpty()) {
            return result;
        }

        for (Premium_Payment_c_ExternalOrgSF__dlm payment : [
            SELECT Name__c, Policy_Number__c, Payment_Date_c__c, Payment_Mode_c__c,
                   Payment_Status_c__c, Transaction_Id_c__c, Amount_c__c
            FROM Premium_Payment_c_ExternalOrgSF__dlm
            WHERE Policy_Number__c IN :premiumByPolicy.keySet()
            ORDER BY Payment_Date_c__c DESC
        ]) {
            PaymentWrapper w = new PaymentWrapper();
            w.paymentNumber = payment.Name__c;
            w.policyNumber = payment.Policy_Number__c;
            w.paymentDate = payment.Payment_Date_c__c;
            w.paymentMode = payment.Payment_Mode_c__c;
            w.status = payment.Payment_Status_c__c;
            w.transactionId = payment.Transaction_Id_c__c;
            w.amount = payment.Amount_c__c != null ? payment.Amount_c__c : premiumByPolicy.get(payment.Policy_Number__c);
            result.add(w);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<InstallmentWrapper> getMyInstallments() {
        String customerId = getCurrentCustomerId();
        List<InstallmentWrapper> result = new List<InstallmentWrapper>();
        if (String.isBlank(customerId)) {
            return result;
        }

        Map<String, Decimal> premiumByPolicy = getPremiumAmountByPolicyNumber(customerId);
        if (premiumByPolicy.isEmpty()) {
            return result;
        }

        for (Premium_Installment__dlm inst : [
            SELECT Name__c, Policy_Number__c, Installment_No_c__c, Due_Date_c__c, Paid_Date_c__c,
                   Receipt_Number_c__c, Status_c__c, Premium_Amount_c__c
            FROM Premium_Installment__dlm
            WHERE Policy_Number__c IN :premiumByPolicy.keySet()
            ORDER BY Due_Date_c__c DESC
        ]) {
            InstallmentWrapper w = new InstallmentWrapper();
            w.installmentName = inst.Name__c;
            w.policyNumber = inst.Policy_Number__c;
            w.installmentNo = inst.Installment_No_c__c;
            w.dueDate = inst.Due_Date_c__c;
            w.paidDate = inst.Paid_Date_c__c;
            w.receiptNumber = inst.Receipt_Number_c__c;
            w.status = inst.Status_c__c;
            w.amount = inst.Premium_Amount_c__c != null ? inst.Premium_Amount_c__c : premiumByPolicy.get(inst.Policy_Number__c);
            result.add(w);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<CaseWrapper> getMyCases() {
        Id contactId = getCurrentContactId();
        List<CaseWrapper> result = new List<CaseWrapper>();
        if (contactId == null) {
            return result;
        }

        for (Case c : [
            SELECT Id, CaseNumber, Subject, Status, Origin, Description, CreatedDate, ClosedDate, IsClosed
            FROM Case
            WHERE ContactId = :contactId
            ORDER BY CreatedDate DESC
        ]) {
            CaseWrapper w = new CaseWrapper();
            w.id = c.Id;
            w.caseNumber = c.CaseNumber;
            w.subject = c.Subject;
            w.status = c.Status;
            w.origin = c.Origin;
            w.description = c.Description;
            w.createdDate = c.CreatedDate;
            w.closedDate = c.ClosedDate;
            w.isClosed = c.IsClosed;
            result.add(w);
        }
        return result;
    }

    @AuraEnabled
    public static String createCase(String subject, String description) {
        if (String.isBlank(subject) || String.isBlank(description)) {
            throw new AuraHandledException('Please provide a subject and description.');
        }
        Id contactId = getCurrentContactId();
        if (contactId == null) {
            throw new AuraHandledException('We could not find your account. Please contact support.');
        }

        Case c = new Case();
        c.ContactId = contactId;
        c.Subject = subject.length() > 255 ? subject.substring(0, 255) : subject;
        c.Description = description;
        c.Origin = 'Web';
        c.Status = 'New';

        try {
            insert c;
        } catch (Exception e) {
            throw new AuraHandledException('We could not submit your case. Please try again.');
        }
        return c.Id;
    }

    @AuraEnabled
    public static void closeCase(Id caseId) {
        Id contactId = getCurrentContactId();
        List<Case> cases = [SELECT Id, ContactId, IsClosed FROM Case WHERE Id = :caseId LIMIT 1];
        if (contactId == null || cases.isEmpty() || cases[0].ContactId != contactId) {
            throw new AuraHandledException('We could not find that case.');
        }
        if (cases[0].IsClosed) {
            return;
        }
        cases[0].Status = 'Closed';
        try {
            update cases[0];
        } catch (Exception e) {
            throw new AuraHandledException('We could not close the case. Please try again.');
        }
    }

    private static Map<String, Decimal> getPremiumAmountByPolicyNumber(String customerId) {
        Map<String, Decimal> result = new Map<String, Decimal>();
        if (String.isBlank(customerId)) {
            return result;
        }

        Map<String, Premium__dlm> premiumById = new Map<String, Premium__dlm>();
        for (Premium__dlm pr : [SELECT Id__c, Name__c, Premium_Amount_c__c FROM Premium__dlm]) {
            premiumById.put(pr.Id__c, pr);
        }

        for (Policy_External__dlm policy : [
            SELECT Policy_Number_c__c, Product_Premium_c__c, Premium_Amount_c__c
            FROM Policy_External__dlm
            WHERE Customer_Id__c = :customerId
        ]) {
            Decimal amount = policy.Premium_Amount_c__c;
            if (amount == null) {
                Premium__dlm matchedPremium = premiumById.get(policy.Product_Premium_c__c);
                if (matchedPremium != null) {
                    amount = matchedPremium.Premium_Amount_c__c != null
                        ? matchedPremium.Premium_Amount_c__c
                        : HFInsuranceCatalogController.parsePremiumAmount(matchedPremium.Name__c);
                }
            }
            result.put(policy.Policy_Number_c__c, amount);
        }
        return result;
    }

    public static Id getCurrentContactId() {
        List<User> users = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return users.isEmpty() ? null : users[0].ContactId;
    }

    private static String getCurrentCustomerId() {
        Id contactId = getCurrentContactId();
        if (contactId == null) {
            return null;
        }
        List<Contact> contacts = [SELECT Customer_ID__c FROM Contact WHERE Id = :contactId LIMIT 1];
        return contacts.isEmpty() ? null : contacts[0].Customer_ID__c;
    }

    public class PolicyWrapper {
        @AuraEnabled public String policyNumber;
        @AuraEnabled public String productName;
        @AuraEnabled public String insuranceType;
        @AuraEnabled public String subCategory;
        @AuraEnabled public String status;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Date issueDate;
        @AuraEnabled public String frequency;
        @AuraEnabled public Decimal premiumAmount;
        @AuraEnabled public Decimal sumAssured;
        @AuraEnabled public Decimal sumAssuredMin;
        @AuraEnabled public Decimal sumAssuredMax;
        @AuraEnabled public Decimal installmentsPaid;
        @AuraEnabled public Decimal installmentsPending;
        @AuraEnabled public Decimal installmentsOverdue;
        @AuraEnabled public Decimal installmentsPerYear;
        @AuraEnabled public Integer progressPercent;
    }

    public class ClaimWrapper {
        @AuraEnabled public String claimNumber;
        @AuraEnabled public String policyNumber;
        @AuraEnabled public Date claimDate;
        @AuraEnabled public String claimType;
        @AuraEnabled public Decimal claimedAmount;
        @AuraEnabled public Decimal approvedAmount;
        @AuraEnabled public String status;
    }

    public class PaymentWrapper {
        @AuraEnabled public String paymentNumber;
        @AuraEnabled public String policyNumber;
        @AuraEnabled public Date paymentDate;
        @AuraEnabled public String paymentMode;
        @AuraEnabled public String status;
        @AuraEnabled public String transactionId;
        @AuraEnabled public Decimal amount;
    }

    public class InstallmentWrapper {
        @AuraEnabled public String installmentName;
        @AuraEnabled public String policyNumber;
        @AuraEnabled public Decimal installmentNo;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Date paidDate;
        @AuraEnabled public String receiptNumber;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal amount;
    }

    public class CaseWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String origin;
        @AuraEnabled public String description;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime closedDate;
        @AuraEnabled public Boolean isClosed;
    }
}