import { LightningElement, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import Id from '@salesforce/user/Id';
import USER_CONTACT_ID from '@salesforce/schema/User.ContactId';
import USER_ACCOUNT_ID from '@salesforce/schema/User.AccountId';
import USER_EMAIL from '@salesforce/schema/User.Email';
import CONTACT_CUSTOMER_ID from '@salesforce/schema/Contact.Customer_ID__c';
import updateSessionEmail from '@salesforce/apex/UpdateSessionEmail_HF_Saathi.updateSessionEmail';

const USER_FIELDS    = [USER_CONTACT_ID, USER_ACCOUNT_ID, USER_EMAIL];
const CONTACT_FIELDS = [CONTACT_CUSTOMER_ID];

export default class EmbeddedMessagingSetRecordUser extends LightningElement {
    userId = Id;

    // Stored from User wire — used reactively by Contact wire
    _contactId;
    _accountId;
    _email;

    // ── Wire 1: get ContactId, AccountId, Email from the User record ──────────
    @wire(getRecord, { recordId: '$userId', fields: USER_FIELDS })
    wiredUser({ error, data }) {
        if (error) {
            console.error('Error loading user record:', error);
            return;
        }
        if (data) {
            this._contactId = getFieldValue(data, USER_CONTACT_ID);
            this._accountId = getFieldValue(data, USER_ACCOUNT_ID);
            this._email     = getFieldValue(data, USER_EMAIL);

            // Guest user has no ContactId — dispatch without customerId
            if (!this._contactId) {
                this._dispatchAndUpdate(null);
            }
            // If ContactId is present, Wire 2 fires reactively and handles dispatch
        }
    }

    // ── Wire 2: get Customer_ID__c from the linked Contact record ─────────────
    // Triggered automatically when _contactId becomes available
    @wire(getRecord, { recordId: '$_contactId', fields: CONTACT_FIELDS })
    wiredContact({ error, data }) {
        if (data) {
            const customerId = getFieldValue(data, CONTACT_CUSTOMER_ID);
            this._dispatchAndUpdate(customerId);
        }
    }

    // ── Dispatch userInfo event and update mid-session if chat is active ──────
    _dispatchAndUpdate(customerId) {
        const { _contactId: contactId, _accountId: accountId, _email: email } = this;

        console.log('contactId-->', contactId);
        console.log('accountId-->', accountId);
        console.log('email-->'    , email);
        console.log('customerId-->', customerId);

        // Broadcast for head markup prechat script (sets hidden fields on new sessions)
        window.dispatchEvent(new CustomEvent('userInfo', {
            detail: { contactId, accountId, email, customerId },
            bubbles: true,
            composed: true
        }));

        // Mid-session login/registration: update active guest session directly
        if (email && window.embeddedservice_bootstrap) {
            updateSessionEmail({ email, contactId, accountId })
                .catch(err => console.error('UpdateSessionEmail error:', err));
        }
    }
}