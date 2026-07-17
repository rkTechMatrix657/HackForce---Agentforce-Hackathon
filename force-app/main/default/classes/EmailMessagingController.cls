/**
 * Sends a confirmation email to the customer when they confirm interest in
 * an HF Finance insurance policy (Opportunity created via HF Saathi).
 * Called as an InvocableMethod from the agent OR directly from Apex.
 */
public with sharing class EmailMessagingController {

    @InvocableMethod(
        label='Send Policy Confirmation Email'
        description='Sends an email to the customer confirming their insurance policy interest registration, including the product name, selected plan, and a representative follow-up commitment.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(sendEmail(req));
        }
        return results;
    }

    // Direct Apex call from CreatePolicyInquiry_HF_Saathi
    public static void sendPolicyEmail(String contactId, String opportunityId,
                                        String productName, String premiumPlan) {
        Request req      = new Request();
        req.contactId    = contactId;
        req.opportunityId = opportunityId;
        req.productName  = productName;
        req.premiumPlan  = premiumPlan;
        sendEmail(req);
    }

    private static Result sendEmail(Request req) {
        Result res  = new Result();
        res.success = false;

        if (String.isBlank(req.contactId) || String.isBlank(req.productName)) {
            res.message = 'Missing contactId or productName.';
            return res;
        }

        try {
            List<Contact> contacts = [
                SELECT Id, FirstName, LastName, Email
                FROM Contact WHERE Id = :req.contactId LIMIT 1
            ];

            if (contacts.isEmpty() || String.isBlank(contacts[0].Email)) {
                res.message = 'Customer email address not found.';
                return res;
            }

            Contact c         = contacts[0];
            String firstName  = String.isNotBlank(c.FirstName) ? c.FirstName : 'Valued Customer';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ c.Email });
            mail.setSubject('Your HF Finance Policy Interest — ' + req.productName);
            mail.setHtmlBody(buildBody(firstName, req.productName, req.premiumPlan, req.opportunityId));
            mail.setSaveAsActivity(true);
            mail.setTargetObjectId(req.contactId);
            if (String.isNotBlank(req.opportunityId)) mail.setWhatId(req.opportunityId);

            Messaging.SendEmailResult[] sendResults =
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });

            if (sendResults[0].isSuccess()) {
                res.success = true;
            } else {
                res.message = sendResults[0].getErrors()[0].getMessage();
                ExceptionLogger_HF_Saathi.log('EmailMessagingController', 'sendEmail', res.message, req.contactId);
            }

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('EmailMessagingController', 'sendEmail', ex, req.contactId);
            res.message = ex.getMessage();
        }
        return res;
    }

    private static String buildBody(String firstName, String product, String plan, String oppId) {
        return
            '<div style="font-family:Arial,sans-serif;max-width:600px;margin:auto;padding:24px;border:1px solid #e0e0e0;border-radius:8px;">'
          + '<h2 style="color:#003366;margin-bottom:4px;">HF Finance</h2>'
          + '<p style="color:#666;margin-top:0;">Policy Interest Confirmation</p>'
          + '<hr style="border:none;border-top:1px solid #e0e0e0;"/>'
          + '<p>Dear <strong>' + firstName + '</strong>,</p>'
          + '<p>Thank you for your interest in <strong>' + product + '</strong> with HF Finance!</p>'
          + '<p>We have registered your inquiry and an HF Finance representative will contact you '
          + 'within <strong>24 hours</strong> to guide you through the next steps.</p>'
          + (String.isNotBlank(plan)
              ? '<table style="background:#f9f9f9;padding:12px;border-radius:4px;width:100%;">'
              + '<tr><td><strong>Selected Plan</strong></td><td>' + plan + '</td></tr>'
              + (String.isNotBlank(oppId)
                  ? '<tr><td><strong>Reference No.</strong></td><td>' + oppId + '</td></tr>'
                  : '')
              + '</table><br/>'
              : '')
          + '<p style="color:#888;font-size:12px;">This is an automated message from HF Saathi. '
          + 'If you did not initiate this request, please contact HF Finance immediately.</p>'
          + '</div>';
    }

    public class Request {
        @InvocableVariable(label='Contact ID' description='Salesforce Contact ID of the customer.' required=true)
        public String contactId;

        @InvocableVariable(label='Opportunity ID' description='Salesforce Opportunity ID of the created policy inquiry.' required=false)
        public String opportunityId;

        @InvocableVariable(label='Product Name' description='Insurance product the customer expressed interest in.' required=true)
        public String productName;

        @InvocableVariable(label='Premium Plan' description='Selected premium plan details.' required=false)
        public String premiumPlan;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True if the email was sent successfully.')
        public Boolean success;

        @InvocableVariable(label='Message' description='Error message if the email failed.')
        public String message;
    }
}