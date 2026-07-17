public with sharing class ContactTriggerHandler {

    private static final String ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    private static final String ID_PREFIX = 'CUST';
    private static final Integer SUFFIX_LENGTH = 6;

    public static void generateCustomerIds(List<Contact> newContacts) {
        for (Contact c : newContacts) {
            if (String.isBlank(c.Customer_ID__c)) {
                c.Customer_ID__c = ID_PREFIX + randomSuffix();
            }
        }
    }

    private static String randomSuffix() {
        String result = '';
        for (Integer i = 0; i < SUFFIX_LENGTH; i++) {
            Integer idx = Math.mod(Crypto.getRandomInteger() & 2147483647, ALPHABET.length());
            result += ALPHABET.substring(idx, idx + 1);
        }
        return result;
    }
}