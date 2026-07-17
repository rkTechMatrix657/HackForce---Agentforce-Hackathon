import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import currentUserId from '@salesforce/user/Id';
import getMyNotifications from '@salesforce/apex/HFNotificationController.getMyNotifications';
import markNotificationRead from '@salesforce/apex/HFNotificationController.markNotificationRead';
import markAllNotificationsRead from '@salesforce/apex/HFNotificationController.markAllNotificationsRead';

const DEEP_LINK_KEY = 'hf_open_case_number';
const POLL_INTERVAL_MS = 25000;

function relativeTime(value) {
    if (!value) {
        return '';
    }
    const then = new Date(value).getTime();
    const diffMs = Date.now() - then;
    const minutes = Math.floor(diffMs / 60000);
    if (minutes < 1) {
        return 'Just now';
    }
    if (minutes < 60) {
        return `${minutes}m ago`;
    }
    const hours = Math.floor(minutes / 60);
    if (hours < 24) {
        return `${hours}h ago`;
    }
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
}

export default class HfNotificationBell extends NavigationMixin(LightningElement) {
    rawNotifications = [];
    isOpen = false;
    pollHandle;

    connectedCallback() {
        this.refresh();
        this.pollHandle = setInterval(() => this.refresh(), POLL_INTERVAL_MS);
    }

    disconnectedCallback() {
        if (this.pollHandle) {
            clearInterval(this.pollHandle);
        }
    }

    async refresh() {
        try {
            this.rawNotifications = await getMyNotifications();
        } catch (error) {
            this.rawNotifications = [];
        }
    }

    get unreadCount() {
        return this.rawNotifications.filter((n) => !n.isRead).length;
    }

    get hasUnread() {
        return this.unreadCount > 0;
    }

    get badgeLabel() {
        return this.unreadCount > 9 ? '9+' : String(this.unreadCount);
    }

    get bellClass() {
        return this.hasUnread ? 'hf-bell hf-bell_active' : 'hf-bell';
    }

    get panelClass() {
        return this.isOpen ? 'hf-bell__panel hf-bell__panel_open' : 'hf-bell__panel';
    }

    get hasNotifications() {
        return this.rawNotifications.length > 0;
    }

    get notifications() {
        return this.rawNotifications.map((n) => ({
            key: n.id,
            id: n.id,
            caseId: n.caseId,
            caseNumber: n.caseNumber,
            preview: n.preview,
            commenterName: n.commenterName || 'HF Finance Team',
            caseSubject: n.caseSubject,
            timeLabel: relativeTime(n.createdDate),
            isRead: n.isRead,
            rowClass: n.isRead ? 'hf-bell__item' : 'hf-bell__item hf-bell__item_unread'
        }));
    }

    handleToggle() {
        this.isOpen = !this.isOpen;
        if (this.isOpen) {
            this.refresh();
        }
    }

    handleClose() {
        this.isOpen = false;
    }

    async handleNotificationClick(event) {
        const id = event.currentTarget.dataset.id;
        const caseNumber = event.currentTarget.dataset.caseNumber;
        const caseId = event.currentTarget.dataset.caseId;

        this.rawNotifications = this.rawNotifications.map((n) =>
            n.id === id ? { ...n, isRead: true } : n
        );
        markNotificationRead({ notificationId: id }).catch(() => {});

        if (caseNumber) {
            sessionStorage.setItem(DEEP_LINK_KEY, caseNumber);
            window.dispatchEvent(new CustomEvent('hfopencase', { detail: { caseNumber } }));
        }
        this.isOpen = false;

        if (caseId) {
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

    async handleMarkAllRead() {
        this.rawNotifications = this.rawNotifications.map((n) => ({ ...n, isRead: true }));
        try {
            await markAllNotificationsRead();
        } catch (error) {
            this.refresh();
        }
    }
}