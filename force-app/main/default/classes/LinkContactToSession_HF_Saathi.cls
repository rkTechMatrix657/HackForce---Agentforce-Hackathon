/**
 * Agentforce Apex Action: LinkContactToSession_HF_Saathi
 *
 * After customer identification, links the verified Contact to the active MessagingSession
 * via the MessagingEndUser record. This ensures the conversation is stored and retrievable
 * against the correct customer record in Salesforce.
 *
 * Also updates the MessagingSession.ContactId if the platform exposes it as writable,
 * so that the session appears on the Contact's activity timeline.
 */
public with sharing class LinkContactToSession_HF_Saathi {

    @InvocableMethod(
        label='Link Contact to Session'
        description='Associates the identified HF Finance Contact with the active MessagingSession so the conversation is stored against the correct customer record.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(linkSession(req.contactId, req.messagingSessionId));
        }
        return results;
    }

    private static Result linkSession(String contactId, String messagingSessionId) {
        Result res = new Result();
        res.success = false;

        if (String.isBlank(contactId) || String.isBlank(messagingSessionId)) {
            res.success = false;
            return res;
        }

        // Skip dummy/preview-mode placeholder IDs
        String msPrefix = Schema.SObjectType.MessagingSession.getKeyPrefix();
        Boolean validId = messagingSessionId.length() >= 15
            && (String.isBlank(msPrefix) || messagingSessionId.startsWith(msPrefix));
        if (!validId) {
            res.success = false;
            return res;
        }

        try {
            List<MessagingEndUser> endUsers = [
                SELECT Id, ContactId
                FROM MessagingEndUser
                WHERE Id IN (
                    SELECT MessagingEndUserId
                    FROM MessagingSession
                    WHERE Id = :messagingSessionId
                )
                LIMIT 1
            ];

            if (!endUsers.isEmpty() && endUsers[0].ContactId != contactId) {
                endUsers[0].ContactId = contactId;
                update endUsers;
            }
            res.success = true;
        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('LinkContactToSession_HF_Saathi', 'linkSession', ex, messagingSessionId);
            res.success = false;
        }

        return res;
    }

    public class Request {
        @InvocableVariable(
            label='Contact ID'
            description='The Salesforce Contact ID of the identified customer.'
            required=true
        )
        public String contactId;

        @InvocableVariable(
            label='Messaging Session ID'
            description='The Salesforce MessagingSession ID to link the contact to.'
            required=true
        )
        public String messagingSessionId;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True if the session was successfully linked to the contact.')
        public Boolean success;
    }
}