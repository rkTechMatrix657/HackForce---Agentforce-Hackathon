import { LightningElement } from 'lwc';
import isGuest from '@salesforce/user/isGuest';

export default class HfHeroSection extends LightningElement {
    isGuestUser = isGuest;
}