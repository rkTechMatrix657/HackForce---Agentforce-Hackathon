import { LightningElement, api, wire } from 'lwc';
import getCatalog from '@salesforce/apex/HFInsuranceCatalogController.getCatalog';

const ICON_BY_SUBCATEGORY = {
    Term: '\u{1F6E1}\u{FE0F}',
    Endowment: '\u{1F4C8}',
    'Child Plan': '\u{1F393}',
    ULIP: '\u{1F4B9}'
};

function trimZero(num) {
    return Number(num.toFixed(1)).toString();
}

function formatINR(amount) {
    if (amount === null || amount === undefined) {
        return '₹-';
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

export default class HfInsuranceProductShowcase extends LightningElement {
    @api heading = 'Plans built around your life';
    @api subheading = 'Real products, real premiums — sourced live from our policy catalog.';

    activeFilter = 'All';
    expandedCode = '';
    rawCatalog = [];
    error;

    @wire(getCatalog)
    wiredCatalog({ data, error }) {
        if (data) {
            this.rawCatalog = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.rawCatalog = [];
        }
    }

    truncate(text, max) {
        if (!text) {
            return '';
        }
        if (text.length <= max) {
            return text;
        }
        return text.slice(0, max).trim() + '…';
    }

    decorateProduct(p) {
        const icon = ICON_BY_SUBCATEGORY[p.subCategory] || '\u{1F4BC}';
        const premiums = (p.plans || []).map((pl) => pl.premiumAmount).filter((v) => v !== null && v !== undefined);
        const startingPremium = premiums.length ? Math.min(...premiums) : null;
        const isExpanded = this.expandedCode === p.code;
        return {
            id: p.id,
            code: p.code,
            name: p.name,
            insuranceType: p.insuranceType,
            category: p.category,
            subCategory: p.subCategory,
            description: p.description,
            shortDescription: this.truncate(p.description, 150),
            icon,
            sumAssuredRange:
                p.sumAssuredMin != null && p.sumAssuredMax != null
                    ? `${formatINR(p.sumAssuredMin)} – ${formatINR(p.sumAssuredMax)}`
                    : 'On request',
            policyTermRange: `${p.policyTermMin}–${p.policyTermMax} Yrs`,
            startingPremiumLabel: startingPremium !== null ? `${formatINR(startingPremium)} / month` : 'On request',
            plans: (p.plans || []).map((pl) => ({
                id: pl.id,
                name: pl.name,
                ageBand: pl.ageBand,
                premiumLabel: formatINR(pl.premiumAmount),
                sumAssuredLabel: pl.sumAssured != null ? formatINR(pl.sumAssured) : 'On request',
                termLabel: `${pl.policyTerm} Yrs`,
                frequencyLabel: (pl.frequency || '').split(';').join(' · ')
            })),
            isExpanded,
            toggleLabel: isExpanded ? 'Hide Premium Plans' : `View ${(p.plans || []).length} Premium Plans`,
            cardClass: `hf-card${isExpanded ? ' hf-card_expanded' : ''}`
        };
    }

    get decoratedCatalog() {
        return this.rawCatalog.map((p) => this.decorateProduct(p));
    }

    get filters() {
        return ['All', 'Life', 'Health'].map((label) => ({
            label,
            value: label,
            cssClass: label === this.activeFilter ? 'hf-filter-pill hf-filter-pill_active' : 'hf-filter-pill'
        }));
    }

    get products() {
        if (this.activeFilter === 'All') {
            return this.decoratedCatalog;
        }
        return this.decoratedCatalog.filter((p) => p.insuranceType === this.activeFilter);
    }

    get hasProducts() {
        return this.products && this.products.length > 0;
    }

    handleFilterClick(event) {
        this.activeFilter = event.currentTarget.dataset.value;
    }

    handleToggleExpand(event) {
        const code = event.currentTarget.dataset.code;
        this.expandedCode = this.expandedCode === code ? '' : code;
    }

    handleExploreClick(event) {
        const code = event.currentTarget.dataset.code;
        this.dispatchEvent(
            new CustomEvent('exploreplan', {
                detail: { code }
            })
        );
    }
}