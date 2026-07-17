/**
 * Agentforce Apex Action: GetPremiumsForContact_HF_Saathi
 *
 * Returns HF Finance premium plans filtered by the customer's age.
 * Age is auto-determined from Contact.Birthdate — never asks the customer.
 *
 * Premium values are hardcoded here (not read from Schema.getPicklistValues)
 * to avoid the record-type restriction that returns empty results for the agent bot user.
 *
 * Format: {Product Name} ({Product Code}/{Age Band} A/{Premium Amount} INR/{Term Years} TY)
 */
public without sharing class GetPremiumsForContact_HF_Saathi {

    // All active HF Finance premium picklist values.
    // Update this list whenever premiums are added or removed in Salesforce Setup.
    private static final List<String> PREMIUM_VALUES = new List<String>{
        'HF Jeevan Suraksha (HFLTR001/25-35 A/500 INR/20 TY)',
        'HF Jeevan Suraksha (HFLTR001/36-50 A/1000 INR/20 TY)',
        'HF Arogya Suraksha (HFHTR002/25-35 A/500 INR/10 TY)',
        'HF Arogya Suraksha (HFHTR002/36-50 A/1000 INR/10 TY)',
        'HF Jeevan Samriddhi (HFLEN003/25-35 A/1000 INR/20 TY)',
        'HF Jeevan Samriddhi (HFLEN003/36-45 A/2500 INR/20 TY)',
        'HF Jeevan Samriddhi (HFLEN003/46-55 A/5000 INR/20 TY)',
        'HF Bal Labh (HFLCP004/0-20 A/1000 INR/10 TY)',
        'HF Bal Labh (HFLCP004/0-20 A/2500 INR/15 TY)',
        'HF Bal Labh (HFLCP004/0-20 A/5000 INR/20 TY)',
        'HF Nivesh Jeevan (HFLUL005/25-35 A/1000 INR/15 TY)',
        'HF Nivesh Jeevan (HFLUL005/36-45 A/2500 INR/15 TY)',
        'HF Nivesh Jeevan (HFLUL005/46-55 A/5000 INR/15 TY)',
        'HF Jeevan Labh (HFHEN006/25-35 A/1000 INR/15 TY)',
        'HF Jeevan Labh (HFHEN006/36-45 A/2500 INR/15 TY)',
        'HF Jeevan Labh (HFHEN006/46-55 A/5000 INR/15 TY)',
        'HF Bal Jeevan Umang (HFLCP007/0-20 A/1000 INR/10 TY)',
        'HF Bal Jeevan Umang (HFLCP007/0-20 A/2500 INR/15 TY)',
        'HF Bal Jeevan Umang (HFLCP007/0-20 A/5000 INR/20 TY)',
        'HF Index Plus (HFLUL008/25-35 A/1000 INR/10 TY)',
        'HF Index Plus (HFLUL008/36-45 A/2500 INR/10 TY)',
        'HF Index Plus (HFLUL008/46-55 A/5000 INR/10 TY)'
    };

    @InvocableMethod(
        label='Get Premiums For Contact'
        description='Returns HF Finance premium plans as a formatted numbered list filtered by the customer\'s age from Contact.Birthdate. No customer input required.'
        category='HF Saathi'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(getPremiums(req.contactId));
        }
        return results;
    }

    private static Result getPremiums(String contactId) {
        Result res = new Result();
        try {
            Integer age = getContactAge(contactId);

            List<String> lines   = new List<String>();
            List<String> matched = new List<String>();
            Integer idx = 1;

            for (String value : PREMIUM_VALUES) {
                PremiumInfo info = parsePremiumLabel(value);
                if (info == null) continue;

                // Filter by age band when age is available
                if (age != null && !ageInBand(age, info.ageBandMin, info.ageBandMax)) continue;

                lines.add(idx + '. ' + info.productName + ':');
                lines.add('   Age Band: ' + info.ageBand + ' Years');
                lines.add('   Premium: ' + info.premiumAmount + ' INR');
                lines.add('   Policy Term: ' + info.termYears + ' Years');
                lines.add('');
                matched.add(value);
                idx++;
            }

            if (matched.isEmpty()) {
                res.premiumList = age != null
                    ? 'No plans are currently available for your age (' + age + '). Please speak with an HF Finance representative.'
                    : 'No plans are currently available. Please speak with an HF Finance representative.';
                res.availablePremiums = '';
                return res;
            }

            String header = age != null
                ? 'Here are the HF Finance insurance plans available for you (Age: ' + age + '):\n'
                : 'Here are all available HF Finance insurance plans:\n';
            lines.add(0, header);

            res.premiumList       = String.join(lines, '\n').trim();
            res.availablePremiums = String.join(matched, '|');

        } catch (Exception ex) {
            ExceptionLogger_HF_Saathi.log('GetPremiumsForContact_HF_Saathi', 'getPremiums', ex, contactId);
            res.premiumList = 'Unable to load plans at this time. Please speak with an HF Finance representative.';
            res.availablePremiums = '';
        }
        return res;
    }

    private static Integer getContactAge(String contactId) {
        if (String.isBlank(contactId)) return null;
        try {
            List<Contact> contacts = [SELECT Birthdate FROM Contact WHERE Id = :contactId LIMIT 1];
            if (contacts.isEmpty() || contacts[0].Birthdate == null) return null;
            return contacts[0].Birthdate.daysBetween(Date.today()) / 365;
        } catch (Exception ex) { return null; }
    }

    // Parses: "HF Jeevan Suraksha (HFLTR001/25-35 A/500 INR/20 TY)"
    private static PremiumInfo parsePremiumLabel(String label) {
        if (String.isBlank(label)) return null;
        try {
            Integer parenOpen  = label.indexOf('(');
            Integer parenClose = label.lastIndexOf(')');
            if (parenOpen == -1 || parenClose == -1) return null;

            String productName  = label.substring(0, parenOpen).trim();
            String innerContent = label.substring(parenOpen + 1, parenClose);
            List<String> parts  = innerContent.split('/');
            if (parts.size() < 4) return null;

            String ageBandRaw    = parts[1].replaceAll('\\s*A\\s*$', '').trim();
            String premiumAmtRaw = parts[2].replaceAll('\\s*INR\\s*$', '').trim();
            String termRaw       = parts[3].replaceAll('\\s*TY\\s*$', '').trim();

            List<String> ageParts = ageBandRaw.split('-');
            if (ageParts.size() != 2) return null;

            PremiumInfo info   = new PremiumInfo();
            info.productName   = productName;
            info.productCode   = parts[0].trim();
            info.ageBand       = ageBandRaw;
            info.ageBandMin    = Integer.valueOf(ageParts[0].trim());
            info.ageBandMax    = Integer.valueOf(ageParts[1].trim());
            info.premiumAmount = premiumAmtRaw;
            info.termYears     = termRaw;
            return info;
        } catch (Exception ex) { return null; }
    }

    private static Boolean ageInBand(Integer age, Integer min, Integer max) {
        return age >= min && age <= max;
    }

    // Called by CreatePolicyInquiry_HF_Saathi to derive Insurance__c from a premium label
    public static String deriveInsuranceFromPremium(String premiumLabel) {
        try {
            Integer parenOpen = premiumLabel.indexOf('(');
            Integer slashIdx  = premiumLabel.indexOf('/');
            if (parenOpen == -1 || slashIdx == -1) return null;
            String productCode = premiumLabel.substring(parenOpen + 1, slashIdx).trim();
            Schema.SObjectField insField = Schema.SObjectType.Opportunity.fields.getMap().get('Insurance__c');
            if (insField == null) return null;
            for (Schema.PicklistEntry entry : insField.getDescribe().getPicklistValues()) {
                if (entry.isActive() && entry.getValue().contains(productCode)) return entry.getValue();
            }
        } catch (Exception ex) { /* non-fatal */ }
        return null;
    }

    private class PremiumInfo {
        String productName, productCode, ageBand, premiumAmount, termYears;
        Integer ageBandMin, ageBandMax;
    }

    public class Request {
        @InvocableVariable(label='Contact ID' description='Salesforce Contact ID — used to read Birthdate for age calculation.' required=true)
        public String contactId;
    }

    public class Result {
        @InvocableVariable(label='Premium List' description='Formatted numbered list of premium plans matching the customer\'s age band. Display exactly as returned.')
        public String premiumList;

        @InvocableVariable(label='Available Premiums' description='Pipe-separated full labels of matched premiums for agent reference when customer selects one.')
        public String availablePremiums;
    }
}