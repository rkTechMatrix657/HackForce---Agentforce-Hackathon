import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getMyPolicies from '@salesforce/apex/HFCustomerAccountController.getMyPolicies';
import getMyPayments from '@salesforce/apex/HFCustomerAccountController.getMyPayments';
import getMyInstallments from '@salesforce/apex/HFCustomerAccountController.getMyInstallments';
import getMyClaims from '@salesforce/apex/HFCustomerAccountController.getMyClaims';
import getMyCases from '@salesforce/apex/HFCustomerAccountController.getMyCases';
import createCase from '@salesforce/apex/HFCustomerAccountController.createCase';
import closeCase from '@salesforce/apex/HFCustomerAccountController.closeCase';
import getCaseComments from '@salesforce/apex/HFCaseCommentController.getCaseComments';
import addCaseComment from '@salesforce/apex/HFCaseCommentController.addCaseComment';

const DEEP_LINK_KEY = 'hf_open_case_number';

const TABS = [
    { id: 'policies', label: 'My Policies', icon: '\u{1F4D1}' },
    { id: 'payments', label: 'Payments', icon: '\u{1F4B3}' },
    { id: 'installments', label: 'Installments', icon: '\u{1F4C5}' },
    { id: 'claims', label: 'Claims', icon: '\u{1F6E1}\u{FE0F}' },
    { id: 'cases', label: 'Cases & Support', icon: '\u{1F4AC}' }
];

const POLICY_STATUS_CLASS = {
    Active: 'hf-badge hf-badge_success',
    Lapsed: 'hf-badge hf-badge_danger',
    Matured: 'hf-badge hf-badge_info',
    Cancelled: 'hf-badge hf-badge_danger'
};

const GENERIC_STATUS_CLASS = {
    Paid: 'hf-badge hf-badge_success',
    Success: 'hf-badge hf-badge_success',
    Approved: 'hf-badge hf-badge_success',
    Settled: 'hf-badge hf-badge_success',
    Pending: 'hf-badge hf-badge_warning',
    Overdue: 'hf-badge hf-badge_danger',
    Failed: 'hf-badge hf-badge_danger',
    Rejected: 'hf-badge hf-badge_danger'
};

function badgeClass(map, status) {
    return map[status] || 'hf-badge hf-badge_neutral';
}

function trimZero(num) {
    return Number(num.toFixed(1)).toString();
}

function formatINR(amount) {
    if (amount === null || amount === undefined) {
        return 'On request';
    }
    const value = Number(amount);
    if (value >= 10000000) {
        return '₹' + trimZero(value / 10000000) + ' Cr';
    }
    if (value >= 100000) {
        return '₹' + trimZero(value / 100000) + ' L';
    }
    return '₹' + value.toLocaleString('en-IN');
}

function formatDate(value) {
    if (!value) {
        return '—';
    }
    const d = new Date(value);
    return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
}

export default class HfMyAccountDashboard extends LightningElement {
    activeTab = 'policies';

    rawPolicies = [];
    rawPayments = [];
    rawInstallments = [];
    rawClaims = [];
    rawCases = [];

    isLoadingPolicies = true;
    isLoadingPayments = true;
    isLoadingInstallments = true;
    isLoadingClaims = true;
    isLoadingCases = true;

    wiredCasesResult;

    subject = '';
    description = '';
    isSubmitting = false;
    showCaseForm = false;
    showSuccess = false;
    errorMessage = '';

    expandedCaseId = '';
    commentsByCaseId = {};
    loadingCommentsCaseId = '';
    newCommentText = '';
    isSubmittingComment = false;
    closingCaseId = '';
    pendingDeepLinkCaseNumber = '';

    boundHandleOpenCaseEvent = this.handleOpenCaseEvent.bind(this);

    connectedCallback() {
        const targetCaseNumber = sessionStorage.getItem(DEEP_LINK_KEY);
        if (targetCaseNumber) {
            sessionStorage.removeItem(DEEP_LINK_KEY);
            this.activeTab = 'cases';
            this.pendingDeepLinkCaseNumber = targetCaseNumber;
        }
        window.addEventListener('hfopencase', this.boundHandleOpenCaseEvent);
    }

    disconnectedCallback() {
        window.removeEventListener('hfopencase', this.boundHandleOpenCaseEvent);
    }

    handleOpenCaseEvent(event) {
        const caseNumber = event.detail && event.detail.caseNumber;
        if (!caseNumber) {
            return;
        }
        sessionStorage.removeItem(DEEP_LINK_KEY);
        this.activeTab = 'cases';
        this.pendingDeepLinkCaseNumber = caseNumber;
        this.resolvePendingDeepLink();
    }

    @wire(getMyPolicies)
    wiredPolicies({ data, error }) {
        this.isLoadingPolicies = false;
        if (data) {
            this.rawPolicies = data;
        } else if (error) {
            this.rawPolicies = [];
        }
    }

    @wire(getMyPayments)
    wiredPayments({ data, error }) {
        this.isLoadingPayments = false;
        if (data) {
            this.rawPayments = data;
        } else if (error) {
            this.rawPayments = [];
        }
    }

    @wire(getMyInstallments)
    wiredInstallments({ data, error }) {
        this.isLoadingInstallments = false;
        if (data) {
            this.rawInstallments = data;
        } else if (error) {
            this.rawInstallments = [];
        }
    }

    @wire(getMyClaims)
    wiredClaims({ data, error }) {
        this.isLoadingClaims = false;
        if (data) {
            this.rawClaims = data;
        } else if (error) {
            this.rawClaims = [];
        }
    }

    @wire(getMyCases)
    wiredCases(result) {
        this.wiredCasesResult = result;
        const { data, error } = result;
        this.isLoadingCases = false;
        if (data) {
            this.rawCases = data;
            this.resolvePendingDeepLink();
        } else if (error) {
            this.rawCases = [];
        }
    }

    resolvePendingDeepLink() {
        if (!this.pendingDeepLinkCaseNumber) {
            return;
        }
        const match = this.rawCases.find((c) => c.caseNumber === this.pendingDeepLinkCaseNumber);
        this.pendingDeepLinkCaseNumber = '';
        if (match) {
            this.openCaseComments(match.id);
        }
    }

    get tabs() {
        return TABS.map((t) => ({
            ...t,
            cssClass: t.id === this.activeTab ? 'hf-tab hf-tab_active' : 'hf-tab'
        }));
    }

    get isPolicies() {
        return this.activeTab === 'policies';
    }
    get isPayments() {
        return this.activeTab === 'payments';
    }
    get isInstallments() {
        return this.activeTab === 'installments';
    }
    get isClaims() {
        return this.activeTab === 'claims';
    }
    get isCases() {
        return this.activeTab === 'cases';
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    get policies() {
        return this.rawPolicies.map((p) => ({
            key: p.policyNumber,
            policyNumber: p.policyNumber,
            productName: p.productName || 'Insurance Policy',
            insuranceType: p.insuranceType,
            statusClass: badgeClass(POLICY_STATUS_CLASS, p.status),
            status: p.status,
            premiumLabel: formatINR(p.premiumAmount),
            frequencyLabel: p.frequency || '',
            sumAssuredLabel:
                p.sumAssured != null
                    ? formatINR(p.sumAssured)
                    : p.sumAssuredMin != null && p.sumAssuredMax != null
                    ? `${formatINR(p.sumAssuredMin)} – ${formatINR(p.sumAssuredMax)} (Plan Range)`
                    : 'On request',
            issueDateLabel: formatDate(p.issueDate),
            startDateLabel: formatDate(p.startDate),
            endDateLabel: formatDate(p.endDate),
            progressPercent: p.progressPercent,
            progressStyle: `width: ${p.progressPercent}%`,
            installmentsPaid: p.installmentsPaid,
            installmentsPending: p.installmentsPending,
            installmentsOverdue: p.installmentsOverdue,
            hasOverdue: p.installmentsOverdue > 0
        }));
    }

    get hasPolicies() {
        return this.policies.length > 0;
    }

    get payments() {
        return this.rawPayments.map((p) => ({
            key: p.paymentNumber,
            paymentNumber: p.paymentNumber,
            policyNumber: p.policyNumber,
            dateLabel: formatDate(p.paymentDate),
            mode: p.paymentMode || '—',
            statusClass: badgeClass(GENERIC_STATUS_CLASS, p.status),
            status: p.status,
            transactionId: p.transactionId,
            amountLabel: formatINR(p.amount)
        }));
    }

    get hasPayments() {
        return this.payments.length > 0;
    }

    get installments() {
        return this.rawInstallments.map((i) => ({
            key: i.installmentName,
            installmentName: i.installmentName,
            policyNumber: i.policyNumber,
            installmentNo: i.installmentNo,
            dueDateLabel: formatDate(i.dueDate),
            paidDateLabel: i.paidDate ? formatDate(i.paidDate) : '—',
            receiptNumber: i.receiptNumber || '—',
            statusClass: badgeClass(GENERIC_STATUS_CLASS, i.status),
            status: i.status,
            amountLabel: formatINR(i.amount)
        }));
    }

    get hasInstallments() {
        return this.installments.length > 0;
    }

    get claims() {
        return this.rawClaims.map((c) => ({
            key: c.claimNumber,
            claimNumber: c.claimNumber,
            policyNumber: c.policyNumber,
            claimType: c.claimType,
            dateLabel: formatDate(c.claimDate),
            statusClass: badgeClass(GENERIC_STATUS_CLASS, c.status),
            status: c.status,
            claimedLabel: formatINR(c.claimedAmount),
            approvedLabel: c.approvedAmount != null ? formatINR(c.approvedAmount) : 'Under Assessment'
        }));
    }

    get hasClaims() {
        return this.claims.length > 0;
    }

    get cases() {
        return this.rawCases.map((c) => {
            const isExpanded = this.expandedCaseId === c.id;
            return {
                key: c.id,
                id: c.id,
                caseNumber: c.caseNumber,
                subject: c.subject,
                description: c.description,
                statusClass: c.isClosed ? 'hf-badge hf-badge_neutral' : 'hf-badge hf-badge_warning',
                status: c.status,
                createdLabel: formatDate(c.createdDate),
                isClosed: c.isClosed,
                isClosing: this.closingCaseId === c.id,
                isExpanded,
                toggleLabel: isExpanded ? 'Hide Comments' : 'View Comments',
                cardClass: isExpanded ? 'hf-case-row hf-case-row_expanded' : 'hf-case-row',
                comments: this.commentsByCaseId[c.id] || [],
                isLoadingComments: this.loadingCommentsCaseId === c.id
            };
        });
    }

    get hasCases() {
        return this.cases.length > 0;
    }

    get openCasesCount() {
        return this.rawCases.filter((c) => !c.isClosed).length;
    }

    get closedCasesCount() {
        return this.rawCases.filter((c) => c.isClosed).length;
    }

    get isSubmitDisabled() {
        return this.isSubmitting || !this.subject || !this.description;
    }

    get submitButtonLabel() {
        return this.isSubmitting ? 'Submitting…' : 'Submit Case';
    }

    get raiseCaseButtonLabel() {
        return this.showCaseForm ? 'Cancel' : 'Raise a New Case';
    }

    handleToggleCaseForm() {
        this.showCaseForm = !this.showCaseForm;
        this.showSuccess = false;
        this.errorMessage = '';
    }

    handleSubjectChange(event) {
        this.subject = event.target.value;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    async handleSubmitCase() {
        this.isSubmitting = true;
        this.errorMessage = '';
        try {
            await createCase({ subject: this.subject, description: this.description });
            this.isSubmitting = false;
            this.showSuccess = true;
            this.showCaseForm = false;
            this.subject = '';
            this.description = '';
            if (this.wiredCasesResult) {
                refreshApex(this.wiredCasesResult);
            }
        } catch (error) {
            this.isSubmitting = false;
            this.errorMessage = (error.body && error.body.message) || 'We could not submit your case. Please try again.';
        }
    }

    handleToggleComments(event) {
        const caseId = event.currentTarget.dataset.caseId;
        if (this.expandedCaseId === caseId) {
            this.expandedCaseId = '';
            return;
        }
        this.openCaseComments(caseId);
    }

    openCaseComments(caseId) {
        this.expandedCaseId = caseId;
        this.newCommentText = '';
        if (!this.commentsByCaseId[caseId]) {
            this.loadComments(caseId);
        }
    }

    async loadComments(caseId) {
        this.loadingCommentsCaseId = caseId;
        try {
            const data = await getCaseComments({ caseId });
            this.commentsByCaseId = {
                ...this.commentsByCaseId,
                [caseId]: data.map((c) => ({
                    key: c.id,
                    body: c.body,
                    authorName: c.isMine ? 'You' : c.authorName || 'HF Finance Team',
                    dateLabel: formatDate(c.createdDate),
                    rowClass: c.isMine ? 'hf-comment hf-comment_mine' : 'hf-comment'
                }))
            };
        } catch (error) {
            this.commentsByCaseId = { ...this.commentsByCaseId, [caseId]: [] };
        } finally {
            this.loadingCommentsCaseId = '';
        }
    }

    handleNewCommentChange(event) {
        this.newCommentText = event.target.value;
    }

    get isAddCommentDisabled() {
        return this.isSubmittingComment || !this.newCommentText;
    }

    get addCommentLabel() {
        return this.isSubmittingComment ? 'Posting…' : 'Post Comment';
    }

    async handleAddComment(event) {
        const caseId = event.currentTarget.dataset.caseId;
        if (!this.newCommentText) {
            return;
        }
        this.isSubmittingComment = true;
        try {
            await addCaseComment({ caseId, commentBody: this.newCommentText });
            this.newCommentText = '';
            const textarea = this.template.querySelector('.hf-comments__textarea');
            if (textarea) {
                textarea.value = '';
            }
            await this.loadComments(caseId);
        } catch (error) {
            // surfaced via disabled state; comment box remains for retry
        } finally {
            this.isSubmittingComment = false;
        }
    }

    async handleCloseCase(event) {
        const caseId = event.currentTarget.dataset.caseId;
        // eslint-disable-next-line no-alert
        if (!window.confirm('Are you sure you want to close this case?')) {
            return;
        }
        this.closingCaseId = caseId;
        try {
            await closeCase({ caseId });
            if (this.wiredCasesResult) {
                await refreshApex(this.wiredCasesResult);
            }
        } catch (error) {
            // status remains open; user can retry
        } finally {
            this.closingCaseId = '';
        }
    }
}