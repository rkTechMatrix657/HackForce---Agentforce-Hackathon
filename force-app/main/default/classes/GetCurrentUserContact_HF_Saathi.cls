/**
 * AuraEnabled Apex Controller: GetCurrentUserContact_HF_Saathi
 *
 * Returns the logged-in community user's ContactId, AccountId, and Customer_ID__c
 * so the hfSaathiAutoIdentify LWC can set them as hidden pre-chat fields.
 *
 * Lookup strategy:
 *   1. User.ContactId (direct link — set when community user created from a Contact)
 *   2. Contact.Email = UserInfo.getUserEmail() (fallback when ContactId is null)
 *
 * Uses without sharing so the community user's own User + Contact records are
 * always accessible regardless of OWD sharing settings.
 */
public without sharing class GetCurrentUserContact_HF_Saathi {

    public class UserContactInfo {
        @AuraEnabled public String contactId;
        @AuraEnabled public String accountId;
        @AuraEnabled public String customerId;
        @AuraEnabled public String customerName;
        @AuraEnabled public String debugInfo;   // shown during testing
    }

    @AuraEnabled(cacheable=false)
    public static UserContactInfo getContact() {
        String userId    = UserInfo.getUserId();
        String userEmail = UserInfo.getUserEmail();
        String userName  = UserInfo.getName();

        UserContactInfo info   = new UserContactInfo();
        info.debugInfo = 'UserId=' + userId + ' | Email=' + userEmail;

        // ── Strategy 1: User.ContactId (direct link) ──────────────────────────
        List<User> users = [
            SELECT Id, ContactId, Email
            FROM User
            WHERE Id = :userId
            LIMIT 1
        ];

        if (!users.isEmpty() && String.isNotBlank(users[0].ContactId)) {
            return buildFromContactId(users[0].ContactId, info, 'User.ContactId');
        }

        // ── Strategy 2: Contact.Email fallback ────────────────────────────────
        if (String.isNotBlank(userEmail)) {
            List<Contact> byEmail = [
                SELECT Id, FirstName, LastName, AccountId, Customer_ID__c
                FROM Contact
                WHERE Email = :userEmail
                LIMIT 1
            ];
            if (!byEmail.isEmpty()) {
                return buildFromContact(byEmail[0], info, 'Contact.Email match');
            }
        }

        // ── Not found ─────────────────────────────────────────────────────────
        info.debugInfo += ' | Result=NOT_FOUND (User has no ContactId and no Contact with matching Email)';
        return info;
    }

    private static UserContactInfo buildFromContactId(String contactId, UserContactInfo info, String source) {
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, AccountId, Customer_ID__c
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];
        if (contacts.isEmpty()) {
            info.debugInfo += ' | Source=' + source + ' | ContactId=' + contactId + ' | Result=CONTACT_RECORD_NOT_FOUND';
            return info;
        }
        return buildFromContact(contacts[0], info, source);
    }

    private static UserContactInfo buildFromContact(Contact c, UserContactInfo info, String source) {
        info.contactId    = c.Id;
        info.accountId    = c.AccountId;
        info.customerId   = c.Customer_ID__c;
        info.customerName = c.FirstName;
        info.debugInfo   += ' | Source=' + source + ' | ContactId=' + c.Id + ' | AccountId=' + c.AccountId;
        return info;
    }
}