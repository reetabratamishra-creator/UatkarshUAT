import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getAssignContext from '@salesforce/apex/CaseDepartmentAssignController.getAssignContext';
import getUsersByDepartment from '@salesforce/apex/CaseDepartmentAssignController.getUsersByDepartment';
import assignCase from '@salesforce/apex/CaseDepartmentAssignController.assignCase';

export default class CaseDepartmentAssign extends LightningElement {
    _recordId;
    _requested = false;

    searchTerm = '';
    isDropdownOpen = false;
    selectedUserLabel = '';
    context;
    users = [];
    selectedDepartment;
    selectedUserId;
    errorMessage;
    isLoading = true;
    isLoadingUsers = false;
    isSaving = false;
    usersLoaded = false;

    /* recordId arrives asynchronously in a quick action, so load from the
     * setter rather than connectedCallback. */
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.loadIfReady();
    }

    /* Fallback for console tabs, Aura wrappers and URL-launched actions. */
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        if (this._recordId || !pageRef) {
            return;
        }
        const fromPageRef = pageRef.attributes?.recordId ?? pageRef.state?.recordId;
        if (fromPageRef) {
            this._recordId = fromPageRef;
            this.loadIfReady();
        }
    }

    loadIfReady() {
        if (this._recordId && !this._requested) {
            this._requested = true;
            this.loadContext();
        }
    }

    async loadContext() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.context = await getAssignContext({ caseId: this._recordId });
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    /* ---------------- getters ---------------- */

    get departments() {
        return this.context?.departments ?? [];
    }

    get currentOwnerName() {
        return this.context?.currentOwnerName;
    }

    get isBlocked() {
        return !!this.context?.blockReason;
    }

    get blockReason() {
        return this.context?.blockReason;
    }

    get showForm() {
        return !!this.context && !this.isBlocked && !this.errorMessage;
    }

    get showUserPicker() {
        return this.usersLoaded && this.users.length > 0;
    }

    get showNoUsers() {
        return this.usersLoaded && this.users.length === 0;
    }

    get saveDisabled() {
        return this.isSaving || !this.selectedDepartment || !this.selectedUserId;
    }
    get filteredUsers() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        if (!term) {
            return this.users;
        }
        return this.users.filter((u) => u.label.toLowerCase().includes(term));
    }

    get noSearchResults() {
        return this.filteredUsers.length === 0;
    }

    get comboboxClass() {
        return (
            'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click' +
            (this.isDropdownOpen ? ' slds-is-open' : '')
        );
    }

    get searchDisplayValue() {
        // While typing/open show the search text; otherwise show the selected user's name
        return this.isDropdownOpen ? this.searchTerm : this.selectedUserLabel;
    }

    /* ---------------- handlers ---------------- */

    async handleDepartmentChange(event) {
        this.selectedDepartment = event.detail.value;
        this.selectedUserId = undefined;
        this.selectedUserLabel = '';
        this.searchTerm = '';
        this.users = [];
        this.usersLoaded = false;
        this.errorMessage = undefined;

        this.isLoadingUsers = true;
        try {
            this.users = await getUsersByDepartment({ department: this.selectedDepartment });
            this.usersLoaded = true;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoadingUsers = false;
        }
    }

    handleUserChange(event) {
        this.selectedUserId = event.detail.value;
    }
    handleSearchFocus() {
        this.isDropdownOpen = true;
        this.searchTerm = '';
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
        this.isDropdownOpen = true;
    }

    handleSearchBlur() {
        this.isDropdownOpen = false;
        this.searchTerm = '';
    }

    handleUserSelect(event) {
        // mousedown fires before blur, so the selection is captured before the list closes
        const value = event.currentTarget.dataset.value;
        const label = event.currentTarget.dataset.label;
        this.selectedUserId = value;
        this.selectedUserLabel = label;
        this.searchTerm = '';
        this.isDropdownOpen = false;
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSave() {
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const result = await assignCase({
                caseId: this._recordId,
                department: this.selectedDepartment,
                newOwnerId: this.selectedUserId
            });

            const hasWarnings = result?.warnings?.length > 0;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: hasWarnings ? 'Case assigned, with issues' : 'Case assigned',
                    message: hasWarnings
                        ? `${result.ownerName} now owns this case. ${result.warnings.join(' ')}`
                        : `${result.ownerName} now owns this case.`,
                    variant: hasWarnings ? 'warning' : 'success',
                    mode: hasWarnings ? 'sticky' : 'dismissable'
                })
            );

            notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
            this.handleClose();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    reduceError(error) {
        return (
            error?.body?.message ||
            error?.body?.pageErrors?.[0]?.message ||
            error?.message ||
            'Something went wrong. Contact your administrator.'
        );
    }
    preventBlur(event) {
        // keeps the input focused when clicking the list scrollbar
        event.preventDefault();
    }
}