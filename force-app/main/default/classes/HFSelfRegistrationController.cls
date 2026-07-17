public without sharing class HFSelfRegistrationController {

    private static final String CUSTOMER_PROFILE_NAME = 'Customer Community User';

    @AuraEnabled
    public static String registerCustomer(String firstName, String lastName, String email, String phone, String password) {
        if (String.isBlank(firstName) || String.isBlank(lastName) || String.isBlank(email) || String.isBlank(password)) {
            throw raise('Please fill in all required fields.');
        }

        Account family;
        try {
            List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :CUSTOMER_PROFILE_NAME LIMIT 1];
            if (profiles.isEmpty()) {
                throw raise('Registration is temporarily unavailable. Please try again later.');
            }

            family = new Account(Name = lastName.trim() + ' Family');
            insert family;

            User newUser = new User();
            newUser.FirstName = firstName.trim();
            newUser.LastName = lastName.trim();
            newUser.Email = email.trim();
            newUser.Username = email.trim();
            newUser.CommunityNickname = buildNickname(firstName, lastName);
            newUser.Alias = buildAlias(firstName, lastName);
            newUser.ProfileId = profiles[0].Id;
            newUser.TimeZoneSidKey = 'Asia/Kolkata';
            newUser.LocaleSidKey = 'en_IN';
            newUser.EmailEncodingKey = 'UTF-8';
            newUser.LanguageLocaleKey = 'en_US';
            if (String.isNotBlank(phone)) {
                newUser.Phone = phone.trim();
            }

            String newUserId = Site.createPortalUser(newUser, family.Id, password);
            assignMemberDataAccess(newUserId);
            return newUserId;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            if (family != null && family.Id != null) {
                delete family;
            }
            if (e.getMessage().contains('DUPLICATE_USERNAME') || e.getMessage().contains('username already exists')) {
                throw raise('An account with this email already exists. Please log in instead.');
            }
            throw raise('We could not complete your registration: ' + e.getMessage());
        }
    }

    private static void assignMemberDataAccess(String userId) {
        try {
            List<PermissionSet> permSets = [
                SELECT Id FROM PermissionSet WHERE Name = 'HF_Site_Member_Data_Access' LIMIT 1
            ];
            if (!permSets.isEmpty()) {
                insert new PermissionSetAssignment(
                    AssigneeId = userId,
                    PermissionSetId = permSets[0].Id
                );
            }
        } catch (Exception e) {
            // Registration already succeeded; dashboard access can be granted later if this fails.
        }
    }

    private static AuraHandledException raise(String message) {
        AuraHandledException ahe = new AuraHandledException(message);
        ahe.setMessage(message);
        return ahe;
    }

    private static String buildAlias(String firstName, String lastName) {
        String raw = (firstName + lastName).replaceAll('[^a-zA-Z0-9]', '');
        if (raw.length() > 8) {
            raw = raw.substring(0, 8);
        }
        if (String.isBlank(raw)) {
            raw = 'hfuser';
        }
        return raw;
    }

    private static String buildNickname(String firstName, String lastName) {
        String base = (firstName + lastName).replaceAll('[^a-zA-Z0-9]', '');
        if (base.length() > 20) {
            base = base.substring(0, 20);
        }
        Integer suffix = Math.mod(Math.abs(Crypto.getRandomInteger()), 9999);
        return base + suffix;
    }
}