public without sharing class CreateLeadFromSession_HF_Saathi {

    @InvocableMethod(
        label='Create Lead From Session'
        description='Before creating a Lead, checks if a Contact already exists with the provided email. If found, returns contactExists=true and asks the customer to log in. If not found, creates a Lead and tags it to the active MessagingSession.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(createLead(req));
        }
        return results;
    }

    private static Result createLead(Request req) {
        Result res = new Result();
        try {
            // ── Case 1: Check if a Contact already exists with this email ─────────
            if (String.isNotBlank(req.email)) {
                List<Contact> existing = [
                    SELECT Id FROM Contact WHERE Email = :req.email LIMIT 1
                ];
                if (!existing.isEmpty()) {
                    res.contactExists  = true;
                    res.outcomeMessage = 'It looks like an HF Finance account already exists for '
                        + req.email + '. '
                        + 'Please log in to the portal and start a new conversation — '
                        + 'I\'ll be able to personalise your experience right away! '
                        + 'Is there anything else I can help you with?';
                    return res;
                }
            }

            // ── No existing Contact — create Lead ─────────────────────────────────
            Lead l        = new Lead();
            l.FirstName   = req.firstName;
            l.LastName    = req.lastName;
            l.Email       = req.email;
            l.Phone       = req.phone;
            l.Company     = 'HF Finance Prospect';
            l.LeadSource  = 'Web';
            l.Status      = 'New';
            l.Description = 'Lead captured via HF Saathi chat assistant.';
            insert l;

            if (isValidSessionId(req.messagingSessionId)) {
                try {
                    MessagingSession ms = new MessagingSession(Id = req.messagingSessionId);
                    ms.put('LeadId', l.Id);
                    Database.SaveResult sr = Database.update(ms, false);
                    if (!sr.isSuccess()) {
                        List<String> errs = new List<String>();
                        for (Database.Error e : sr.getErrors()) {
                            errs.add(e.getStatusCode() + ': ' + e.getMessage());
                        }
                        ExceptionLogger_HF_Saathi.log('CreateLeadFromSession_HF_Saathi', 'createLead - sessionTag',
                            String.join(errs, '; '), req.messagingSessionId);
                    }
                } catch (Exception ex) {
                    ExceptionLogger_HF_Saathi.log('CreateLeadFromSession_HF_Saathi', 'createLead - sessionTag', ex, req.messagingSessionId);
                }
            }

            res.leadId         = l.Id;
            res.contactExists  = false;
            res.outcomeMessage = 'Thank you, ' + req.firstName + '! I\'ve noted your details. '
                + 'An HF Finance representative will reach out to you at ' + req.email
                + ' within 24 hours to discuss our insurance products. '
                + 'Is there anything else I can help you with today?';

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('CreateLeadFromSession_HF_Saathi', 'createLead', ex, req.messagingSessionId);
            res.outcomeMessage = 'I\'m sorry, I was unable to save your details at this time. '
                + 'Please try again or type "agent" to speak with a representative.';
        }
        return res;
    }

    private static Boolean isValidSessionId(String id) {
        if (String.isBlank(id) || id.length() < 15) return false;
        String prefix = Schema.SObjectType.MessagingSession.getKeyPrefix();
        return String.isBlank(prefix) || id.startsWith(prefix);
    }

    public class Request {
        @InvocableVariable(label='First Name' description='Lead first name.' required=true)
        public String firstName;

        @InvocableVariable(label='Last Name' description='Lead last name.' required=true)
        public String lastName;

        @InvocableVariable(label='Email' description='Lead email address.' required=true)
        public String email;

        @InvocableVariable(label='Phone' description='Lead phone or mobile number.' required=false)
        public String phone;

        @InvocableVariable(
            label='Messaging Session ID'
            description='MessagingSession ID used to tag the created Lead via MessagingSession.LeadId.'
            required=false
        )
        public String messagingSessionId;
    }

    public class Result {
        @InvocableVariable(label='Lead ID' description='Salesforce Lead ID of the created record.')
        public String leadId;

        @InvocableVariable(
            label='Contact Exists'
            description='True when a Contact with the provided email already exists. Agent must inform the customer to log in instead of completing lead capture.'
        )
        public Boolean contactExists;

        @InvocableVariable(label='Outcome Message' description='Confirmation or redirect message to display to the customer.')
        public String outcomeMessage;
    }
}