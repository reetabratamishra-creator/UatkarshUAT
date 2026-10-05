import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

// Opportunity Fields
import OPP_AMOUNT_FIELD from '@salesforce/schema/Opportunity.Amount';

// SObjects & Schemas
import ADDRESSBOOK_OBJECT from '@salesforce/schema/Address_Book__c';
import COUNTRY_FIELD from '@salesforce/schema/Address_Book__c.Country__c';
import STATE_FIELD from '@salesforce/schema/Address_Book__c.State__c';
import ZONE_FIELD from '@salesforce/schema/Address_Book__c.Zone__c';

import PRODUCT_CATEGORY_OBJECT from '@salesforce/schema/Product_Category__c';
import DEPARTMENT_FIELD from '@salesforce/schema/Product_Category__c.Department_Name__c';
import UOM_FIELD from '@salesforce/schema/Product_Category__c.UOM__c';
import PRODUCT_CATEGORY_FIELD from '@salesforce/schema/Product_Category__c.Product_Category__c';

// Apex Imports
import searchAccounts from '@salesforce/apex/bidderAwardController.searchAccounts';
import findDuplicateAccounts from '@salesforce/apex/bidderAwardController.findDuplicateAccounts';
import getBidderName from '@salesforce/apex/bidderAwardController.getBidderName';
import getOpportunityDepartment from '@salesforce/apex/bidderAwardController.getOpportunityDepartment';
import getAccountContacts from '@salesforce/apex/bidderAwardController.getAccountContacts';
import getBidderContactDetails from '@salesforce/apex/bidderAwardController.getBidderContactDetails';
import saveAndAwardOpportunity from '@salesforce/apex/bidderAwardController.saveAndAwardOpportunity';

const DEBOUNCE_MS = 300;
const MODE_SEARCH = 'search';
const MODE_DUPLICATE = 'duplicate';

const PRODUCT_COLUMNS = [
    { label: 'Department', fieldName: 'Department_Name__c', type: 'text' },
    { label: 'Product Category', fieldName: 'Product_Category__c', type: 'text' },
    { label: 'UOM', fieldName: 'UOM__c', type: 'text' },
    { label: 'Quantity', fieldName: 'Quantity__c', type: 'number', editable: true },
    {
        type: 'button-icon',
        fixedWidth: 60,
        typeAttributes: {
            iconName: 'utility:delete',
            name: 'delete',
            title: 'Delete',
            variant: 'bare',
            alternativeText: 'Delete'
        }
    }
];

export default class BidderAward extends LightningElement {
    @api recordId;

    phone = '';
    email = '';
    
    selectedMode = MODE_SEARCH;
    selectedAccountId = null;
    isExistingAccount = false;
    
    searchTerm = '';
    searchResults = [];
    showDropdown = false;
    isSearching = false;
    isLoading = false;

    duplicates = [];
    selectedDuplicateId;
    duplicateError;

    _timer;

    accountContacts = [];
    selectedContactId = null;
    bidderContactDetails = null;
    bidderName;

    selectedContactMode = 'manual'; 
    manualContact = { FirstName: '', LastName: '', Phone: '', Email: '' };

    productCategoryRows = [];
    productColumns = PRODUCT_COLUMNS;
    productDraftValues = [];

    opportunityDepartment = '';
    selectedUom = '';
    productQuantity = null;
    uomOptions = [];
    productRowCounter = 0;
    selectedProductCategory = '';
    productCategoryOptions = [];
    allProductCategoryValues = [];
    productCategoryControllerValues = {};
    isProductCategoryLoading = true;

    countryOptions = [];
    stateOptions = [];
    zoneOptions = [];
    selectedAddressBookId = null;

    newAddressBook = {
        Street__c: '',
        City__c: '',
        State__c: '',
        Country__c: '',
        PIN__c: '',
        Zone__c: '',
        Primary_Address__c: false
    };

    // Wire Amount for client-side early check
    @wire(getRecord, { recordId: '$recordId', fields: [OPP_AMOUNT_FIELD] })
    opportunityRecord;

    get oppAmount() {
        return getFieldValue(this.opportunityRecord.data, OPP_AMOUNT_FIELD);
    }

    get isAmountInvalid() {
        return this.opportunityRecord?.data && (this.oppAmount == null || Number(this.oppAmount) < 1);
    }

    @wire(getObjectInfo, { objectApiName: PRODUCT_CATEGORY_OBJECT })
    productCategoryInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$productCategoryInfo.data.defaultRecordTypeId',
        fieldApiName: UOM_FIELD
    })
    wiredUomValues({ data }) {
        if (data) this.uomOptions = data.values;
    }

    @wire(getPicklistValues, {
        recordTypeId: '$productCategoryInfo.data.defaultRecordTypeId',
        fieldApiName: PRODUCT_CATEGORY_FIELD
    })
    wiredProductCategoryValues({ data }) {
        if (data) {
            this.allProductCategoryValues = data.values;
            this.productCategoryControllerValues = data.controllerValues;
            this.setProductCategoryOptions();
        }
    }

    @wire(getOpportunityDepartment, { opportunityId: '$recordId' })
    wiredOpportunityDepartment({ error, data }) {
        if (data) {
            this.opportunityDepartment = data;
            this.setProductCategoryOptions();
        }
    }

    @wire(getBidderName, { opportunityId: '$recordId' })
    wiredBidderName({ error, data }) {
        if (data) {
            this.bidderName = data;
            if (!this.searchTerm) {
                this.searchTerm = data;
                if (this.searchTerm.trim().length >= 2) {
                    this.isSearching = true;
                    this.runSearch(this.searchTerm);
                }
            }
        }
    }

    @wire(getBidderContactDetails, { opportunityId: '$recordId' })
    wiredBidderDetails({ error, data }) {
        if (data) {
            this.bidderContactDetails = data;
            this.selectedContactMode = 'bidder';
            this.autoLoadDuplicates();
        }
    }

    @wire(getObjectInfo, { objectApiName: ADDRESSBOOK_OBJECT })
    addressBookInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$addressBookInfo.data.defaultRecordTypeId',
        fieldApiName: COUNTRY_FIELD
    })
    wiredCountryValues({ data }) {
        if (data) this.countryOptions = data.values;
    }

    @wire(getPicklistValues, {
        recordTypeId: '$addressBookInfo.data.defaultRecordTypeId',
        fieldApiName: STATE_FIELD
    })
    wiredStateValues({ data }) {
        if (data) this.stateOptions = data.values;
    }

    @wire(getPicklistValues, {
        recordTypeId: '$addressBookInfo.data.defaultRecordTypeId',
        fieldApiName: ZONE_FIELD
    })
    wiredZoneValues({ data }) {
        if (data) this.zoneOptions = data.values;
    }

    get hasNewAddressData() {
        const a = this.newAddressBook;
        return !!(a.Street__c || a.City__c || a.State__c || a.Country__c || a.PIN__c || a.Zone__c);
    }

    get showStateField() { return this.newAddressBook.Country__c === 'India'; }
    get showZoneField() { return this.newAddressBook.Country__c === 'India'; }
    get showNewAddressBookFields() {
        return !this.isExistingAccount || (this.isExistingAccount && !this.selectedAddressBookId);
    }

    autoLoadDuplicates() {
        if (!this.bidderContactDetails) return;
        this.isLoading = true;
        findDuplicateAccounts({
            companyName: this.bidderContactDetails.Bidders__r?.Name,
            phone: this.bidderContactDetails.Contact_Number__c,
            email: this.bidderContactDetails.Email__c
        })
        .then((res) => {
            this.duplicates = res || [];
            this.duplicateError = undefined;
        })
        .catch((err) => {
            this.duplicates = [];
            this.duplicateError = err?.body?.message || 'Unable to load duplicate accounts.';
        })
        .finally(() => { this.isLoading = false; });
    }

    handlePhoneChange(event) { this.phone = event.target.value; }
    handleEmailChange(event) { this.email = event.target.value; }

    handleAddressFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.target.type === 'checkbox'
            ? event.target.checked
            : (event.detail?.value ?? event.target.value);

        if (field === 'Country__c' && value !== 'India') {
            this.newAddressBook = { ...this.newAddressBook, Country__c: value, State__c: '' };
            return;
        }
        this.newAddressBook = { ...this.newAddressBook, [field]: value };
    }

    loadDuplicates() {
        if (!this.searchTerm && !this.phone && !this.email) {
            this.showToast('Info', 'Please provide a Name, Phone, or Email to check for duplicates.', 'info');
            return;
        }
        this.isLoading = true;
        findDuplicateAccounts({
            companyName: this.searchTerm,
            phone: this.phone,
            email: this.email
        })
        .then((res) => {
            this.duplicates = res || [];
            this.duplicateError = undefined;
            if (this.duplicates.length > 0) {
                this.selectedMode = MODE_DUPLICATE;
                this.showToast('Success', `Found ${this.duplicates.length} duplicate(s).`, 'success');
            } else {
                this.showToast('Info', 'No duplicates found.', 'info');
            }
        })
        .catch((err) => {
            this.duplicates = [];
            this.duplicateError = err?.body?.message || 'Unable to load duplicate accounts.';
        })
        .finally(() => { this.isLoading = false; });
    }

    get modeOptions() {
        return [
            { label: 'Search for or create a new account', value: MODE_SEARCH },
            { label: 'Select a matched duplicate account', value: MODE_DUPLICATE }
        ];
    }

    get isSearchMode() { return this.selectedMode === MODE_SEARCH; }
    get isDuplicateMode() { return this.selectedMode === MODE_DUPLICATE; }

    handleModeChange(event) {
        this.selectedMode = event.detail.value;
        this.clearSelection();
    }

    get hasDuplicates() { return this.duplicates && this.duplicates.length > 0; }

    get duplicateOptions() {
        return this.duplicates.map((a) => {
            const meta = [a.Phone, a.Email__c].filter(Boolean).join(' · ');
            return { label: meta ? `${a.Name} (${meta})` : a.Name, value: a.Id };
        });
    }

    handleDuplicateChange(event) {
        this.selectedDuplicateId = event.detail.value;
        this.selectedAccountId = this.selectedDuplicateId;
        this.isExistingAccount = true;
        this.selectedAddressBookId = null;
        this.fetchAccountContacts(this.selectedAccountId);
    }

    handleSearchChange(event) {
        const value = event.target.value;
        this.searchTerm = value;
        this.isExistingAccount = false; 
        this.selectedAccountId = null;

        window.clearTimeout(this._timer);
        if (!value || value.trim().length < 2) {
            this.searchResults = [];
            this.showDropdown = false;
            return;
        }
        this.isSearching = true;
        this._timer = window.setTimeout(() => this.runSearch(value), DEBOUNCE_MS);
    }

    runSearch(term) {
        searchAccounts({ searchKey: term })
            .then((res) => {
                this.searchResults = res;
                this.showDropdown = res.length > 0;
            })
            .catch(() => {
                this.searchResults = [];
                this.showDropdown = false;
            })
            .finally(() => { this.isSearching = false; });
    }

    handleOptionSelect(event) {
        this.selectedAccountId = event.currentTarget.dataset.id;
        this.searchTerm = event.currentTarget.dataset.name;
        this.isExistingAccount = true;
        this.showDropdown = false;
        this.fetchAccountContacts(this.selectedAccountId);
    }

    handleBlur() {
        window.setTimeout(() => { this.showDropdown = false; }, 150);
    }

    handleClearSearch() {
        this.searchTerm = '';
        this.searchResults = [];
        this.clearSelection();
    }

    get searchSelected() {
        return this.isSearchMode && !!this.selectedAccountId;
    }

    get comboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click ${
            this.showDropdown ? 'slds-is-open' : ''
        }`;
    }

    clearSelection() {
        this.selectedAccountId = null;
        this.isExistingAccount = false;
        this.selectedDuplicateId = null;
        this.selectedAddressBookId = null;
        this.showDropdown = false;
        this.accountContacts = [];
        this.selectedContactId = null;

        if (this.selectedContactMode === 'existing') {
            this.selectedContactMode = this.bidderContactDetails ? 'bidder' : 'manual';
        }
    }

    get hasProductCategories() { return this.productCategoryRows.length > 0; }
    get isProductCategoryDisabled() {
        return !this.opportunityDepartment || !this.productCategoryOptions || this.productCategoryOptions.length === 0;
    }
    get productCategoryPlaceholder() {
        return this.isProductCategoryLoading ? 'Loading product categories...' : 'Select Product Category';
    }

    setProductCategoryOptions() {
        if (!this.opportunityDepartment || !this.allProductCategoryValues.length) {
            this.productCategoryOptions = [];
            this.isProductCategoryLoading = true;
            return;
        }
        const controllerIndex = this.productCategoryControllerValues[this.opportunityDepartment];
        if (controllerIndex === undefined) {
            this.productCategoryOptions = [];
            this.isProductCategoryLoading = false;
            return;
        }
        this.productCategoryOptions = this.allProductCategoryValues.filter(option =>
            option.validFor.includes(controllerIndex)
        );
        this.isProductCategoryLoading = false;
    }

    handleUomChange(event) { this.selectedUom = event.detail.value; }
    handleQuantityChange(event) { this.productQuantity = event.target.value; }
    handleProductCategoryChange(event) { this.selectedProductCategory = event.detail.value; }

    handleAddProductCategory() {
        if (!this.selectedProductCategory || !this.selectedUom || !this.productQuantity) {
            this.showToast('Error', 'Please select Product Category, UOM and enter Quantity.', 'error');
            return;
        }
        if (Number(this.productQuantity) <= 0) {
            this.showToast('Error', 'Quantity must be greater than 0.', 'error');
            return;
        }
        const alreadyAdded = this.productCategoryRows.some(
            row => row.Product_Category__c === this.selectedProductCategory
        );
        if (alreadyAdded) {
            this.showToast('Product Category Already Added', 'This product category has already been added.', 'warning');
            return;
        }

        this.productRowCounter++;
        const newRow = {
            Id: `temp-${this.productRowCounter}`,
            Department_Name__c: this.opportunityDepartment,
            Product_Category__c: this.selectedProductCategory,
            UOM__c: this.selectedUom,
            Quantity__c: Number(this.productQuantity)
        };
        this.productCategoryRows = [...this.productCategoryRows, newRow];
        this.selectedProductCategory = '';
        this.selectedUom = '';
        this.productQuantity = null;
    }

    handleProductSave(event) {
        const drafts = event.detail.draftValues;
        this.productCategoryRows = this.productCategoryRows.map(row => {
            const changedRow = drafts.find(draft => draft.Id === row.Id);
            return changedRow ? { ...row, ...changedRow } : row;
        });
        this.productDraftValues = [];
    }

    handleProductRowAction(event) {
        if (event.detail.action.name === 'delete') {
            this.productCategoryRows = this.productCategoryRows.filter(item => item.Id !== event.detail.row.Id);
        }
    }

    fetchAccountContacts(accountId) {
        this.accountContacts = [];
        this.selectedContactId = null;
        getAccountContacts({ accountId: accountId })
            .then(result => {
                this.accountContacts = result.map(c => {
                    const meta = [c.Email, c.Phone].filter(Boolean).join(' · ');
                    return { label: meta ? `${c.Name} (${meta})` : c.Name, value: c.Id };
                });
            })
            .catch(err => console.error('Error fetching contacts', err));
    }

    get showAddressSelector() { return this.isExistingAccount && !!this.selectedAccountId; }
    handleAddressSelected(event) { this.selectedAddressBookId = event.detail.addressBookId; }

    get availableContactModes() {
        let modes = [];
        if (this.bidderContactDetails) modes.push({ label: 'Use Bidder Contact Details', value: 'bidder' });
        if (this.isExistingAccount) modes.push({ label: 'Select Existing Account Contact', value: 'existing' });
        modes.push({ label: 'Create New Contact Manually', value: 'manual' });
        return modes;
    }

    get isContactModeBidder() { return this.selectedContactMode === 'bidder'; }
    get isContactModeExisting() { return this.selectedContactMode === 'existing'; }
    get isContactModeManual() { return this.selectedContactMode === 'manual'; }

    handleContactModeChange(event) { this.selectedContactMode = event.detail.value; }
    handleManualContactChange(event) {
        const field = event.currentTarget.dataset.field;
        this.manualContact = { ...this.manualContact, [field]: event.target.value };
    }
    handleContactChange(event) { this.selectedContactId = event.detail.value; }

    // ==========================================
    // UNIFIED SAVE & DML LOGIC
    // ==========================================
    async handleSave() {
        // 0. Pre-validation: Immediate UI check for Amount
        if (this.isAmountInvalid) {
            this.showToast('Error', 'Please enter the Expected Deal Value (Amount) on the Opportunity before awarding!', 'error');
            return;
        }

        if (!this.productCategoryRows || this.productCategoryRows.length === 0) {
            this.showToast('Error', 'Please add at least one Product Category.', 'error');
            return;
        }

        if (this.isSearchMode && !this.selectedAccountId && !this.searchTerm.trim()) {
            this.showToast('Error', 'Search for an account or type a new account name.', 'error');
            return;
        }
        if (this.isDuplicateMode && !this.selectedAccountId) {
            this.showToast('Error', 'Select one of the matched duplicate accounts.', 'error');
            return;
        }

        if (this.showAddressSelector && !this.hasNewAddressData) {
            const addressSelector = this.template.querySelector('c-qa-address-book-selector');
            if (addressSelector) {
                const validation = addressSelector.validate();
                if (!validation.isValid) {
                    this.showToast('Error', validation.errorMessage, 'error');
                    return;
                }
            }
        }

        if (this.showNewAddressBookFields) {
            const addressInputs = this.template.querySelectorAll('.address-input');
            let isAddressValid = true;
            addressInputs.forEach(inputField => {
                if (!inputField.checkValidity()) {
                    inputField.reportValidity();
                    isAddressValid = false;
                }
            });
            if (!isAddressValid) {
                this.showToast('Error', 'Please complete all required fields for the new address book.', 'error');
                return;
            }
        }

        if (this.selectedContactMode === 'existing' && !this.selectedContactId) {
            this.showToast('Error', 'Please select an existing contact or change the contact assignment method.', 'error');
            return;
        }

        if (this.selectedContactMode === 'manual') {
            const contactInputs = this.template.querySelectorAll('.contact-input');
            let isContactValid = true;
            contactInputs.forEach(input => {
                if (!input.checkValidity()) {
                    input.reportValidity();
                    isContactValid = false;
                }
            });
            if (!isContactValid) {
                this.showToast('Error', 'Please complete all required fields for the new contact.', 'error');
                return;
            }
        }

        this.isLoading = true;

        // Build Payload
        const payload = {
            opportunityId: this.recordId,
            isExistingAccount: this.isExistingAccount,
            selectedAccountId: this.selectedAccountId,
            newAccountName: this.searchTerm,
            newAccountPhone: this.phone,
            newAccountEmail: this.email,
            contactMode: this.selectedContactMode,
            selectedContactId: this.selectedContactId,
            contactFirstName: this.manualContact.FirstName,
            contactLastName: this.manualContact.LastName,
            contactPhone: this.manualContact.Phone,
            contactEmail: this.manualContact.Email,
            selectedAddressBookId: this.selectedAddressBookId,
            newAddressData: this.hasNewAddressData ? this.newAddressBook : null,
            productCategories: this.productCategoryRows.map(row => ({
                Department_Name__c: row.Department_Name__c,
                Product_Category__c: row.Product_Category__c,
                UOM__c: row.UOM__c,
                Quantity__c: Number(row.Quantity__c)
            }))
        };

        try {
            await saveAndAwardOpportunity({ req: payload });
            this.showToast('Success', 'Account, Contact, Address and Product Categories successfully applied! Related opportunities closed.', 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            const msg = error?.body?.pageErrors?.[0]?.message ||
                        error?.body?.message ||
                        error?.message ||
                        'Unknown error';
            this.showToast('Error saving record', msg, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}