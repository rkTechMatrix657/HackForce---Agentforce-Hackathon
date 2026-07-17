/**
 * Agentforce Apex Action: GetCustomerProfile_HF_Saathi
 *
 * IDENTIFICATION STRATEGY (tried in order):
 *
 * 0. sessionEmail (from @MessagingSession.Customer_Email__c via prechat hidden field)
 *    Populated automatically for logged-in Experience Cloud users.
 *    Lookup by Contact.Email. Skips all manual identification questions on match.
 *
 * 1. sessionContactId (from @MessagingEndUser.ContactId)
 *    Already resolved by a previous call or by HF_Saathi_Link_Authenticated_User flow.
 *
 * 2. messagingEndUserId (from @MessagingSession.MessagingEndUserId)
 *    Queries MessagingEndUser record to read AuthenticatedEndUserId.
 *    AuthenticatedEndUserId → User.ContactId → Contact.
 *    On success: writes ContactId + AccountId back to the MEU record so that
 *    @MessagingEndUser.ContactId is available in subsequent turns.
 *
 * 3. customerIdentifier (typed by the customer)
 *    Lookup by Contact.Customer_ID__c, Phone/MobilePhone, or PAN__c.
 *    On success: writes ContactId + AccountId to the MEU record.
 *
 * 4. All strategies failed:
 *    - sessionEmail was blank → needsLeadCapture = true (guest user, collect lead details)
 *    - sessionEmail was present but no Contact found → needsIdentification = true
 *
 * Note: Debug Case creation is for TESTING only. Remove createDebugCase() before production.
 */
public without sharing class GetCustomerProfile_HF_Saathi {

    @InvocableMethod(
        label='Get Customer Profile'
        description='Identifies the HF Finance customer. Strategy 0: email from MessagingSession.Customer_Email__c (logged-in users). Strategy 1: @MessagingEndUser.ContactId. Strategy 2: AuthenticatedEndUserId via MEU. Strategy 3: customer-typed identifier. If email is blank and all strategies fail, returns needsLeadCapture=true for guest lead capture flow.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(identify(
                req.messagingEndUserId,
                req.sessionContactId,
                req.customerIdentifier,
                req.sessionEmail,
                req.messagingSessionId
            ));
        }
        return results;
    }

    // ─────────────────────────────────────────────────────────────────────────
    private static Result identify(
            String messagingEndUserId,
            String sessionContactId,
            String customerIdentifier,
            String sessionEmail,
            String messagingSessionId) {

        Result res = new Result();
        res.isIdentified        = false;
        res.needsIdentification = false;
        res.needsLeadCapture    = false;

        Contact cust = null;

        // ── Strategy 0: session email from MessagingSession.Customer_Email__c ─
        if (String.isNotBlank(sessionEmail)) {
            cust = lookupByEmail(sessionEmail.trim());
            if (cust != null && String.isNotBlank(messagingEndUserId)) {
                updateMEURecord(messagingEndUserId, cust.Id, cust.AccountId,
                    'Auto-resolved via session email: ' + sessionEmail);
            }
        }

        // ── Strategy 1: sessionContactId already set ──────────────────────────
        if (cust == null && String.isNotBlank(sessionContactId)) {
            cust = loadContact(sessionContactId);
        }

        // ── Strategy 2: resolve via MessagingEndUser.AuthenticatedEndUserId ───
        if (cust == null && String.isNotBlank(messagingEndUserId)) {
            cust = resolveViaMessagingEndUser(messagingEndUserId);
        }

        // ── Strategy 3: customer-provided identifier ──────────────────────────
        if (cust == null && String.isNotBlank(customerIdentifier)) {
            cust = lookupByIdentifier(customerIdentifier.trim());
            if (cust != null && String.isNotBlank(messagingEndUserId)) {
                updateMEURecord(messagingEndUserId, cust.Id, cust.AccountId,
                    'Identified via Customer ID input: ' + customerIdentifier.trim());
            }
            if (cust == null) {
                res.outcomeMessage = 'I could not find an HF Finance account with that identifier. '
                    + 'Please check and try again, or type "agent" to speak with a representative.';
                return res;
            }
        }

        // ── All strategies failed ─────────────────────────────────────────────
        if (cust == null) {
            if (String.isBlank(sessionEmail)) {
                // Session contact not resolved — all authenticated strategies failed
                res.outcomeMessage = 'Namaste! Welcome to HF Saathi. How can I help you today?';
            } else {
                // Logged-in user whose email has no matching Contact
                res.needsIdentification = true;
                res.outcomeMessage = 'I was unable to locate your HF Finance account. '
                    + 'Please contact our support team or type "agent" to speak with a representative.';
                ExceptionLogger_HF_Saathi.log('GetCustomerProfile_HF_Saathi', 'identify',
                    'Strategy 0 (email) found no Contact for: ' + sessionEmail
                    + '. Strategies 1-3 also failed.',
                    messagingEndUserId);
            }
            return res;
        }

        // ── Build result ───────────────────────────────────────────────────────
        Account family = loadFamily(cust.AccountId);
        enrichFromDataCloud(cust.Customer_ID__c);

        String firstName = String.isNotBlank(cust.FirstName) ? cust.FirstName : 'there';
        String segment   = family != null ? family.Family_Segment__c : '';

        res.isIdentified        = true;
        res.needsIdentification = false;
        res.contactId           = cust.Id;
        res.familyId            = cust.AccountId;
        res.customerId          = cust.Customer_ID__c;
        res.customerName        = firstName;
        res.familySegment       = segment;
        res.churnRiskScore      = family != null && family.Churn_Risk_Score__c != null
                                  ? String.valueOf(family.Churn_Risk_Score__c.intValue()) : '0';
        res.householdIncome     = family != null ? family.Household_Income__c : null;
        res.activePolicies      = family != null && family.Number_of_Active_Policies__c != null
                                  ? String.valueOf(family.Number_of_Active_Policies__c.intValue()) : '0';

        // ── Tag Contact to MessagingSession so conversation appears on Contact timeline ─
        tagSessionContact(messagingSessionId, cust.Id, cust.Customer_ID__c);

        res.outcomeMessage = segment == 'High Value'
            ? 'Namaste, ' + firstName + '! Welcome back to HF Saathi. '
              + 'As a valued HF Finance member, how can I assist you today?'
            : 'Namaste, ' + firstName + '! Welcome to HF Saathi, '
              + 'your personal insurance assistant from HF Finance. How can I help you today?';

        return res;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Strategy 2: read AuthenticatedEndUserId from MEU → User → Contact
    // Also updates MEU.ContactId and MEU.AccountId on success.
    // ─────────────────────────────────────────────────────────────────────────
    private static Contact resolveViaMessagingEndUser(String meuId) {
        try {
            List<MessagingEndUser> meuList = [
                SELECT Id, AuthenticatedEndUserId, ContactId, AccountId
                FROM MessagingEndUser
                WHERE Id = :meuId
                LIMIT 1
            ];
            if (meuList.isEmpty()) return null;

            MessagingEndUser meu = meuList[0];

            // Already has ContactId set (e.g. by the flow)
            if (String.isNotBlank(meu.ContactId)) {
                return loadContact(meu.ContactId);
            }

            // Resolve via AuthenticatedEndUserId → User.ContactId
            if (String.isNotBlank(meu.AuthenticatedEndUserId)) {
                List<User> users = [
                    SELECT Id, ContactId
                    FROM User
                    WHERE Id = :meu.AuthenticatedEndUserId
                      AND ContactId != null
                    LIMIT 1
                ];
                if (!users.isEmpty()) {
                    Contact cust = loadContact(users[0].ContactId);
                    if (cust != null) {
                        updateMEURecord(meuId, cust.Id, cust.AccountId,
                            'Auto-resolved from AuthenticatedEndUserId: ' + meu.AuthenticatedEndUserId);
                        return cust;
                    }
                }

                ExceptionLogger_HF_Saathi.log('GetCustomerProfile_HF_Saathi', 'resolveViaMessagingEndUser',
                    'AuthenticatedEndUserId (' + meu.AuthenticatedEndUserId + ') found on MEU but User has no ContactId.',
                    meuId);
                return null;
            }

            ExceptionLogger_HF_Saathi.log('GetCustomerProfile_HF_Saathi', 'resolveViaMessagingEndUser',
                'MessagingEndUser.AuthenticatedEndUserId is blank — channel may not be in authenticated mode.',
                meuId);
            return null;

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('GetCustomerProfile_HF_Saathi', 'resolveViaMessagingEndUser', ex, meuId);
            return null;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Updates MessagingEndUser.ContactId AND AccountId
    // ─────────────────────────────────────────────────────────────────────────
    private static void updateMEURecord(String meuId, String contactId, String accountId, String reason) {
        try {
            MessagingEndUser meu = new MessagingEndUser(Id = meuId);
            meu.ContactId = contactId;
            if (String.isNotBlank(accountId)) meu.AccountId = accountId;
            update meu;
        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('GetCustomerProfile_HF_Saathi', 'updateMEURecord', ex, meuId);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Tags the identified Contact to the MessagingSession so the conversation
    // appears on the Contact's Activity timeline and related list.
    // ─────────────────────────────────────────────────────────────────────────
    private static Boolean isValidSessionId(String id) {
        if (String.isBlank(id) || id.length() < 15) return false;
        String prefix = Schema.SObjectType.MessagingSession.getKeyPrefix();
        return String.isBlank(prefix) || id.startsWith(prefix);
    }

    // EndUserContactId is intentionally NOT updated here — the platform auto-links
    // it via the authorized Messaging User for Experience Cloud, making manual
    // update unnecessary and the field read-only in this context.
    private static void tagSessionContact(String messagingSessionId, String contactId, String customerId) {
        if (String.isBlank(messagingSessionId) || String.isBlank(customerId)) return;
        if (!isValidSessionId(messagingSessionId)) return;
        try {
            MessagingSession ms = new MessagingSession(Id = messagingSessionId);
            ms.Customer_Id__c = customerId;
            update ms;
        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('GetCustomerProfile_HF_Saathi', 'tagSessionContact', ex, messagingSessionId);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Strategy 0: look up Contact by Email
    // ─────────────────────────────────────────────────────────────────────────
    private static Contact lookupByEmail(String email) {
        List<Contact> found = [
            SELECT Id, Customer_ID__c, FirstName, LastName, AccountId,
                   Birthdate, Annual_Income__c, Occupation__c, Life_Stage__c,
                   Member_Churn_Risk__c, Next_Best_Product__c, KYC_Status__c
            FROM Contact WHERE Email = :email LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Strategy 3: look up Contact by Customer_ID__c, Phone, or PAN
    // ─────────────────────────────────────────────────────────────────────────
    private static Contact lookupByIdentifier(String trimmed) {
        // 1. Customer_ID__c
        List<Contact> byId = [
            SELECT Id, Customer_ID__c, FirstName, LastName, AccountId,
                   Birthdate, Annual_Income__c, Occupation__c, Life_Stage__c,
                   Member_Churn_Risk__c, Next_Best_Product__c, KYC_Status__c
            FROM Contact WHERE Customer_ID__c = :trimmed LIMIT 1
        ];
        if (!byId.isEmpty()) return byId[0];

        // 2. Phone / MobilePhone
        List<Contact> byPhone = [
            SELECT Id, Customer_ID__c, FirstName, LastName, AccountId,
                   Birthdate, Annual_Income__c, Occupation__c, Life_Stage__c,
                   Member_Churn_Risk__c, Next_Best_Product__c, KYC_Status__c
            FROM Contact WHERE Phone = :trimmed OR MobilePhone = :trimmed LIMIT 1
        ];
        if (!byPhone.isEmpty()) return byPhone[0];

        // 3. PAN
        List<Contact> byPan = [
            SELECT Id, Customer_ID__c, FirstName, LastName, AccountId,
                   Birthdate, Annual_Income__c, Occupation__c, Life_Stage__c,
                   Member_Churn_Risk__c, Next_Best_Product__c, KYC_Status__c
            FROM Contact WHERE PAN__c = :trimmed.toUpperCase() LIMIT 1
        ];
        return byPan.isEmpty() ? null : byPan[0];
    }

    // ─────────────────────────────────────────────────────────────────────────
    private static Contact loadContact(String contactId) {
        List<Contact> found = [
            SELECT Id, Customer_ID__c, FirstName, LastName, AccountId,
                   Birthdate, Annual_Income__c, Occupation__c, Life_Stage__c,
                   Member_Churn_Risk__c, Next_Best_Product__c, KYC_Status__c
            FROM Contact WHERE Id = :contactId LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    private static Account loadFamily(String accountId) {
        if (String.isBlank(accountId)) return null;
        List<Account> found = [
            SELECT Id, Name, Family_Segment__c, Churn_Risk_Score__c,
                   CLV__c, Total_Premium_Value__c, Household_Income__c,
                   Number_of_Members__c, Number_of_Active_Policies__c,
                   Customer_Since__c, Preferred_Language__c
            FROM Account WHERE Id = :accountId LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    private static void enrichFromDataCloud(String customerId) {
        try {
            if (String.isBlank(customerId)) return;
            ConnectApi.CdpQueryInput qi = new ConnectApi.CdpQueryInput();
            qi.sql = 'SELECT ssot__Name__c, ssot__BirthDate__c, ssot__AnnualIncome__c ' +
                     'FROM UnifiedssotIndividualR1__dlm ' +
                     'WHERE ssot__CustomerId__c = \'' +
                     String.escapeSingleQuotes(customerId) + '\' LIMIT 1';
            ConnectApi.CdpQuery.queryAnsiSqlV2(qi);
        } catch (Exception ex) {
            // Non-critical enrichment — silently swallow if Data Cloud is inaccessible
            // for this running user. Does not affect customer identification.
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    public class Request {
        @InvocableVariable(
            label='Messaging End User ID'
            description='MessagingEndUser record ID from @MessagingSession.MessagingEndUserId. Used to look up AuthenticatedEndUserId and update ContactId + AccountId on the MEU record.'
            required=false
        )
        public String messagingEndUserId;

        @InvocableVariable(
            label='Session Contact ID'
            description='Contact ID from @MessagingEndUser.ContactId. Pre-populated when the flow or a previous call already resolved the user.'
            required=false
        )
        public String sessionContactId;

        @InvocableVariable(
            label='Customer Identifier'
            description='Customer ID, mobile number, or PAN typed by the customer. Used only when auto-identification via MEU fails.'
            required=false
        )
        public String customerIdentifier;

        @InvocableVariable(
            label='Session Email'
            description='Email from MessagingSession.Customer_Email__c — populated via prechat hidden field for logged-in Experience Cloud users. Used as Strategy 0 for instant identification without asking the customer any questions.'
            required=false
        )
        public String sessionEmail;

        @InvocableVariable(
            label='Messaging Session ID'
            description='MessagingSession ID from @MessagingSession.Id. Used to set MessagingSession.ContactId after identification so the conversation appears on the Contact activity timeline.'
            required=false
        )
        public String messagingSessionId;
    }

    public class Result {
        @InvocableVariable(label='Is Identified' description='True when the customer profile was loaded successfully.')
        public Boolean isIdentified;

        @InvocableVariable(label='Needs Identification' description='True when a logged-in user email was present but no matching Contact was found.')
        public Boolean needsIdentification;

        @InvocableVariable(label='Needs Lead Capture' description='True when sessionEmail is blank (guest user) and all strategies failed. Agent must collect FirstName, LastName, Email, Phone and call CreateLeadFromSession_HF_Saathi.')
        public Boolean needsLeadCapture;

        @InvocableVariable(label='Contact ID' description='Salesforce Contact ID.')
        public String contactId;

        @InvocableVariable(label='Family ID' description='Salesforce Account (Family) ID.')
        public String familyId;

        @InvocableVariable(label='Customer ID' description='HF Finance Customer_ID__c.')
        public String customerId;

        @InvocableVariable(label='Customer Name' description='First name for personalised greeting.')
        public String customerName;

        @InvocableVariable(label='Family Segment' description='High Value / Growth / At-Risk.')
        public String familySegment;

        @InvocableVariable(label='Churn Risk Score' description='Household churn risk score 0-100.')
        public String churnRiskScore;

        @InvocableVariable(label='Household Income' description='Combined household income.')
        public Decimal householdIncome;

        @InvocableVariable(label='Active Policies' description='Number of active policies.')
        public String activePolicies;

        @InvocableVariable(label='Outcome Message' description='Greeting (identified) or outcome description. Always display to the customer.')
        public String outcomeMessage;
    }
}