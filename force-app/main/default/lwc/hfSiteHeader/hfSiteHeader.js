import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuest from '@salesforce/user/isGuest';
import currentUserId from '@salesforce/user/Id';
import LOGO_URL from '@salesforce/resourceUrl/hfFinanceLogo';

const NAV_ITEMS = [
    { label: 'Home', href: '/HFFinance/s/#home' },
    { label: 'About Us', href: '/HFFinance/s/#about-us' },
    { label: 'Our Plans', href: '/HFFinance/s/#our-plans' },
    { label: 'Contact Us', href: '/HFFinance/s/#contact-us' }
];

export default class HfSiteHeader extends NavigationMixin(LightningElement) {
    logoUrl = LOGO_URL;
    isGuestUser = isGuest;
    navItems = NAV_ITEMS;
    isScrolled = false;
    boundScrollHandler;

    connectedCallback() {
        this.boundScrollHandler = this.handleScroll.bind(this);
        window.addEventListener('scroll', this.boundScrollHandler, { passive: true });
    }

    disconnectedCallback() {
        window.removeEventListener('scroll', this.boundScrollHandler);
    }

    handleScroll() {
        const scrolled = window.scrollY > 12;
        if (scrolled !== this.isScrolled) {
            this.isScrolled = scrolled;
        }
    }

    get headerClass() {
        return this.isScrolled ? 'hf-header hf-header_scrolled' : 'hf-header';
    }

    handleProfileClick() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: currentUserId,
                objectApiName: 'User',
                actionName: 'view'
            }
        });
    }
}