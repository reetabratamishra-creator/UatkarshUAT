import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getChildAccounts from '@salesforce/apex/ChildAccountsController.getChildAccounts';

const COLUMNS = [
    {
        label: 'Site Name',
        fieldName: 'accountUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'name' },
            target: '_self'
        },
        sortable: true
    },
    {
        label: 'Email',
        fieldName: 'email',
        type: 'email',
        sortable: true
    },
    {
        label: 'Phone',
        fieldName: 'phone',
        type: 'phone',
        sortable: true
    }
];

export default class ChildAccountsRelatedList extends LightningElement {
    /** Automatically populated with the current Parent Account Id. */
    @api recordId;

    columns = COLUMNS;
    accounts = [];
    errorMessage;
    isLoading = true;

    wiredResult;

    sortedBy = 'name';
    sortedDirection = 'asc';

    @wire(getChildAccounts, { recordId: '$recordId' })
    wiredAccounts(result) {
        this.wiredResult = result;

        const { data, error } = result;

        this.isLoading = false;

        if (data) {
            this.accounts = data;
            this.errorMessage = undefined;
        } else if (error) {
            this.accounts = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    get hasAccounts() {
        return this.accounts.length > 0;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get isEmpty() {
        return !this.isLoading &&
               !this.hasError &&
               this.accounts.length === 0;
    }

    get recordCountLabel() {
        const count = this.accounts.length;
        return `${count} ${count === 1 ? 'site' : 'sites'}`;
    }

    handleSort(event) {
        const {
            fieldName: sortedBy,
            sortDirection: sortedDirection
        } = event.detail;

        const cloned = [...this.accounts];

        cloned.sort((a, b) => {
            // The Site Name column is sorted by the display value,
            // not the URL.
            const key = sortedBy === 'accountUrl'
                ? 'name'
                : sortedBy;

            const valueA = a[key] ?? '';
            const valueB = b[key] ?? '';

            return valueA > valueB
                ? 1
                : valueA < valueB
                    ? -1
                    : 0;
        });

        this.accounts =
            sortedDirection === 'asc'
                ? cloned
                : cloned.reverse();

        this.sortedBy = sortedBy;
        this.sortedDirection = sortedDirection;
    }

    async handleRefresh() {
        this.isLoading = true;

        try {
            await refreshApex(this.wiredResult);
        } finally {
            this.isLoading = false;
        }
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body
                .map((e) => e.message)
                .join(', ');
        }

        return error?.body?.message ||
               error?.message ||
               'Something went wrong loading Sites.';
    }
}