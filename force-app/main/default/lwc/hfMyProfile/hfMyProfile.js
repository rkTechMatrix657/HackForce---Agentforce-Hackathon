import { LightningElement, wire } from 'lwc';
import currentUserId from '@salesforce/user/Id';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import NAME_FIELD from '@salesforce/schema/User.Name';
import EMAIL_FIELD from '@salesforce/schema/User.Email';

export default class HfMyProfile extends LightningElement {
    userId = currentUserId;

    @wire(getRecord, { recordId: '$userId', fields: [NAME_FIELD, EMAIL_FIELD] })
    userRecord;

    get userName() {
        return (this.userRecord.data && getFieldValue(this.userRecord.data, NAME_FIELD)) || '';
    }

    get userEmail() {
        return (this.userRecord.data && getFieldValue(this.userRecord.data, EMAIL_FIELD)) || '';
    }

    get userInitials() {
        const parts = this.userName.trim().split(/\s+/).filter(Boolean);
        if (!parts.length) {
            return '';
        }
        const first = parts[0].charAt(0);
        const last = parts.length > 1 ? parts[parts.length - 1].charAt(0) : '';
        return (first + last).toUpperCase();
    }
}