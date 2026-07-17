/**
 * Called from embeddedMessagingSetRecordUser LWC when a user logs in or registers mid-conversation.
 *
 * Handles two scenarios:
 *
 * Case 1 — Mid-session LOGIN (existing customer):
 *   Prechat fields are frozen at session start, so Customer_Email__c remains blank for
 *   sessions that started as guest. This method finds that session and updates it so
 *   the agent can re-identify the customer on the next turn.
 *
 * Case 2 — Mid-session REGISTRATION (new customer):
 *   Experience Cloud self-registration creates a Contact + Account + Community User.
 *   If a Lead was previously created in this chat session (e.g., the guest provided
 *   their details), this method finds that Lead by email or phone and converts it to
 *   the newly created Contact + Account, preventing duplicate records.
 */
public without sharing class UpdateSessionEmail_HF_Saathi {

    @AuraEnabled
    public static void updateSessionEmail(String email, String contactId, String accountId) {
        if (String.isBlank(email)) return;
        try {
            Datetime cutoff = Datetime.now().addMinutes(-60);

            List<MessagingSession> sessions = [
                SELECT Id, Customer_Email__c, MessagingEndUserId
                FROM MessagingSession
                WHERE Customer_Email__c = null
                  AND CreatedDate >= :cutoff
                  AND Status != 'Ended'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (sessions.isEmpty()) return;

            MessagingSession ms = sessions[0];

            // ── Fetch Customer_ID__c from the Contact record ──────────────────────
            String customerId = null;
            if (String.isNotBlank(contactId)) {
                List<Contact> contacts = [
                    SELECT Customer_ID__c FROM Contact WHERE Id = :contactId LIMIT 1
                ];
                if (!contacts.isEmpty()) customerId = contacts[0].Customer_ID__c;
            }

            // ── Update session fields in one DML ─────────────────────────────────
            // EndUserContactId is NOT updated here — the authorized Messaging User
            // for Experience Cloud auto-populates it via the platform.
            ms.Customer_Email__c = email;
            if (String.isNotBlank(customerId)) ms.Customer_Id__c = customerId;
            update ms;

            // ── Update MessagingEndUser.ContactId ─────────────────────────────────
            if (String.isNotBlank(contactId) && String.isNotBlank(ms.MessagingEndUserId)) {
                try {
                    MessagingEndUser meu = new MessagingEndUser(Id = ms.MessagingEndUserId);
                    meu.ContactId = contactId;
                    if (String.isNotBlank(accountId)) meu.AccountId = accountId;
                    update meu;
                } catch (Exception ex) {
                    ExceptionLogger_HF_Saathi.log('UpdateSessionEmail_HF_Saathi', 'updateSessionEmail - MEU', ex, ms.MessagingEndUserId);
                }
            }

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('UpdateSessionEmail_HF_Saathi', 'updateSessionEmail', ex, email);
        }
    }
}