import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getCaseContacts from '@salesforce/apex/CaseContactsListController.getCaseContacts';

const DEFAULT_VISIBLE_ROWS = 3;

function reduceError(error) {
    if (!error) {
        return 'Unknown error';
    }
    if (Array.isArray(error.body)) {
        return error.body.map((e) => e.message).join(', ');
    }
    if (error.body && typeof error.body.message === 'string') {
        return error.body.message;
    }
    if (typeof error.message === 'string') {
        return error.message;
    }
    return 'Unknown error';
}

export default class CaseContactsList extends NavigationMixin(LightningElement) {
    @api recordId;
    @api cardTitle = 'Case Contacts';
    @api iconName = 'standard:case';
    @api visibleRows = DEFAULT_VISIBLE_ROWS;

    rows = [];
    error;
    isLoading = true;

    @wire(getCaseContacts, { caseId: '$recordId' })
    wiredCaseContacts({ data, error }) {
        if (data) {
            this.rows = data.map((c) => ({
                ...c,
                recordUrl: '/' + c.recordId,
                emailHref: c.email ? 'mailto:' + c.email : null
            }));
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.rows = [];
            this.error = reduceError(error);
            this.isLoading = false;
        }
    }

    get titleWithCount() {
        return `${this.cardTitle} (${this.rows.length})`;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.error && this.rows.length === 0;
    }

    renderedCallback() {
        this.applyScrollHeight();
    }

    // Limits the table to the first N rows (header included) and lets the rest scroll.
    // Heights are measured from the DOM so the cut-off is exact in any theme or density.
    applyScrollHeight() {
        const container = this.template.querySelector('.scroll-container');
        if (!container) {
            return;
        }
        const header = container.querySelector('thead');
        const bodyRows = container.querySelectorAll('tbody tr');
        const limit = Math.max(1, Number(this.visibleRows) || DEFAULT_VISIBLE_ROWS);

        if (bodyRows.length <= limit) {
            container.style.maxHeight = '';
            return;
        }
        // Not laid out yet (e.g. hidden tab): leave it unrestricted rather than collapse it.
        if (!header || header.offsetHeight === 0 || bodyRows[0].offsetHeight === 0) {
            return;
        }

        let height = header.offsetHeight;
        for (let i = 0; i < limit; i++) {
            height += bodyRows[i].offsetHeight;
        }
        container.style.maxHeight = `${height + 1}px`;
    }

    handleNavigate(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                actionName: 'view'
            }
        });
    }
}