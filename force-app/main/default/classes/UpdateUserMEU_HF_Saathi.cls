/**
 * Apex Action: UpdateUserMEU_HF_Saathi
 *
 * Called from the hfSaathiAutoIdentify LWC after the user opens the chat.
 * Finds the most recently created MessagingEndUser (within the last 60 seconds)
 * with a null ContactId, and updates it with the current community user's
 * ContactId and AccountId.
 *
 * This allows the agent's @MessagingEndUser.ContactId linked variable to be
 * populated even when the channel is in UNAUTH mode, enabling auto-identification.
 *
 * Polling approach: the LWC calls this repeatedly (every 500ms for up to 10s)
 * after the chat button is clicked because the MEU is created asynchronously
 * when the session is established, not when the button is clicked.
 */
public without sharing class UpdateUserMEU_HF_Saathi {

    public class UpdateResult {
        @AuraEnabled public Boolean updated;
        @AuraEnabled public String  meuId;
        @AuraEnabled public String  contactId;
        @AuraEnabled public String  message;
    }

    @AuraEnabled
    public static UpdateResult findAndUpdateMEU() {
        UpdateResult res = new UpdateResult();
        res.updated   = false;
        res.meuId     = null;
        res.contactId = null;

        // ── Step 1: Get current community user's Contact ──────────────────────
        String userId = UserInfo.getUserId();
        List<User> users = [SELECT Id, ContactId FROM User WHERE Id = :userId AND ContactId != null LIMIT 1];
        if (users.isEmpty()) {
            res.message = 'Current user has no ContactId — cannot update MEU';
            return res;
        }

        String contactId = users[0].ContactId;
        List<Contact> contacts = [SELECT Id, AccountId FROM Contact WHERE Id = :contactId LIMIT 1];
        if (contacts.isEmpty()) {
            res.message = 'Contact record not found for id: ' + contactId;
            return res;
        }
        String accountId = contacts[0].AccountId;

        // ── Step 2: Find the most recent MEU with null ContactId (last 60 sec) ─
        Datetime cutoff = Datetime.now().addSeconds(-60);
        List<MessagingEndUser> meuList = [
            SELECT Id, ContactId, AccountId, CreatedDate
            FROM MessagingEndUser
            WHERE ContactId = null
              AND CreatedDate >= :cutoff
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (meuList.isEmpty()) {
            res.message = 'No recent MEU found yet (created in last 60s with null ContactId). Retrying...';
            return res;
        }

        // ── Step 3: Update MEU with ContactId and AccountId ───────────────────
        MessagingEndUser meu = meuList[0];
        meu.ContactId = contactId;
        if (String.isNotBlank(accountId)) meu.AccountId = accountId;

        try {
            update meu;
            res.updated   = true;
            res.meuId     = meu.Id;
            res.contactId = contactId;
            res.message   = 'MEU ' + meu.Id + ' updated with ContactId ' + contactId
                          + ' and AccountId ' + accountId;
        } catch (DmlException ex) {
            ExceptionLogger_HF_Saathi.log('UpdateUserMEU_HF_Saathi', 'findAndUpdateMEU', ex, meu.Id);
            res.message = 'DML error updating MEU: ' + ex.getMessage();
        }

        return res;
    }
}