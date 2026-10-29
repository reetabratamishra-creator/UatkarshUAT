import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getInitData from '@salesforce/apex/AccountCreationController.getInitData';
import createAccountFromJson from '@salesforce/apex/AccountCreationController.createAccountFromJson';

const EMAIL_RE = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
const PAN_RE = /^[A-Z]{5}[0-9]{4}[A-Z]{1}$/;
const GSTIN_RE = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$/;
const WEBSITE_RE = /^(https?:\/\/)?([a-z0-9-]+\.)+[a-z]{2,}(\/.*)?$/;

function blankAddress() {
    return { key: Date.now() + '-' + Math.random(), street: '', city: '', pin: '', country: '', state: '', zone: '' };
}

export default class AccountCreation extends NavigationMixin(LightningElement) {
    @track initData;
    @track loading = true;
    @track submitting = false;
    @track step = 1; // 1 = record type, 2 = details, 3 = success

    recordTypeId;
    accountName = '';
    isChildAccount = false;
    parentAccountId;
    accountSource = '';
    industry = '';
    departmentName = '';
    selectedMultiDepartments = [];
    phone = '';
    email = '';
    website = '';
    pan = '';
    gstin = '';

    useExistingContact = false;
    existingContactId;
    contactFirstName = '';
    contactLastName = '';
    contactEmail = '';
    contactPhone = '';

    primaryAddress = blankAddress();
    fillMoreAddresses = false;
    @track additionalAddresses = [];

    createdAccountId;
    errorMessage;

    contactObjectInfo = { objectApiName: 'Contact' };
    accountObjectInfo = { objectApiName: 'Account' };

    @wire(getInitData)
    wiredInit({ data, error }) {
        this.loading = false;
        if (data) {
            this.initData = data;
            if (!data.isAllowed) {
                return;
            }
        } else if (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        }
    }

    get isAllowed() {
        return this.initData && this.initData.isAllowed;
    }

    get notAllowed() {
        return this.initData && !this.initData.isAllowed;
    }

    get isStep1() { return this.step === 1; }
    get isStep2() { return this.step === 2; }
    get isStep3() { return this.step === 3; }

    get isDealer() {
        return this.initData && this.recordTypeId && this.recordTypeId === this.initData.dealerRecordTypeId;
    }

    get showIndiaFieldsPrimary() {
        return this.primaryAddress.country === 'India';
    }

    get parentAccountFilter() {
        return { criteria: [{ fieldPath: 'ParentId', operator: 'eq', value: null }] };
    }

    // ---- navigation ----

    handleRecordTypeChange(event) {
        this.recordTypeId = event.detail.value;
    }

    goToStep2() {
        if (!this.recordTypeId) {
            this.showToast('Missing selection', 'Please select a Record Type.', 'warning');
            return;
        }
        this.step = 2;
    }

    goToStep1() {
        this.step = 1;
    }

    // ---- step 2 field handlers ----

    handleAccountName(e) { this.accountName = e.target.value; }
    handleIsChildAccount(e) {
        this.isChildAccount = e.target.checked;
        if (!this.isChildAccount) { this.parentAccountId = undefined; }
    }
    handleParentAccount(e) { this.parentAccountId = e.detail.recordId; }
    handleAccountSource(e) { this.accountSource = e.detail.value; }
    handleIndustry(e) { this.industry = e.detail.value; }
    handleDepartment(e) { this.departmentName = e.detail.value; }
    handleMultiDepartment(e) { this.selectedMultiDepartments = e.detail.value; }
    handlePhone(e) {
        const v = e.target.value;
        if (!this.contactPhone || this.contactPhone === this.phone) { this.contactPhone = v; }
        this.phone = v;
    }
    handleEmail(e) {
        const v = e.target.value;
        if (!this.contactEmail || this.contactEmail === this.email) { this.contactEmail = v; }
        this.email = v;
    }
    handleWebsite(e) { this.website = e.target.value; }
    handlePan(e) { this.pan = e.target.value; }
    handleGstin(e) { this.gstin = e.target.value; }

    handleUseExistingContact(e) {
        this.useExistingContact = e.target.checked;
        if (!this.useExistingContact) { this.existingContactId = undefined; }
    }
    handleExistingContact(e) { this.existingContactId = e.detail.recordId; }
    handleContactFirstName(e) { this.contactFirstName = e.target.value; }
    handleContactLastName(e) { this.contactLastName = e.target.value; }
    handleContactEmail(e) { this.contactEmail = e.target.value; }
    handleContactPhone(e) { this.contactPhone = e.target.value; }

    handlePrimaryField(e) {
        const field = e.target.dataset.field;
        this.primaryAddress = { ...this.primaryAddress, [field]: e.target.value ?? e.detail?.value };
    }
    handlePrimaryCombobox(e) {
        const field = e.target.dataset.field;
        this.primaryAddress = { ...this.primaryAddress, [field]: e.detail.value };
        if (field === 'country' && e.detail.value !== 'India') {
            this.primaryAddress = { ...this.primaryAddress, state: '', zone: '' };
        }
    }

    handleFillMoreAddresses(e) {
        this.fillMoreAddresses = e.target.checked;
        if (this.fillMoreAddresses && this.additionalAddresses.length === 0) {
            this.additionalAddresses = [blankAddress()];
        }
    }
    addAnotherAddress() {
        this.additionalAddresses = [...this.additionalAddresses, blankAddress()];
    }
    removeAddress(e) {
        const key = e.target.dataset.key;
        this.additionalAddresses = this.additionalAddresses.filter((a) => a.key !== key);
    }
    handleAdditionalField(e) {
        const key = e.target.dataset.key;
        const field = e.target.dataset.field;
        const value = e.target.value ?? e.detail?.value;
        this.additionalAddresses = this.additionalAddresses.map((a) =>
            a.key === key ? { ...a, [field]: value } : a
        );
    }
    handleAdditionalCombobox(e) {
        const key = e.target.dataset.key;
        const field = e.target.dataset.field;
        const value = e.detail.value;
        this.additionalAddresses = this.additionalAddresses.map((a) => {
            if (a.key !== key) return a;
            const updated = { ...a, [field]: value };
            if (field === 'country' && value !== 'India') {
                updated.state = '';
                updated.zone = '';
            }
            return updated;
        });
    }

    // ---- validation ----

    validateClientSide() {
        if (!this.accountName) return 'Account Name is required.';
        if (!EMAIL_RE.test(this.email || '')) return 'Please enter a valid email address.';
        if (this.pan && !PAN_RE.test(this.pan.toUpperCase())) return 'Please enter a valid PAN number in the format ABCDE1234F.';
        if (this.gstin && !GSTIN_RE.test(this.gstin.toUpperCase())) return 'Please enter a valid GSTIN in the format 29ABCDE1234F1Z5.';
        if (this.website && !WEBSITE_RE.test(this.website.toLowerCase())) return 'Please enter a valid website URL (for example: www.google.com or https://www.google.com).';
        if (!this.primaryAddress.street || !this.primaryAddress.city || !this.primaryAddress.pin || !this.primaryAddress.country) {
            return 'Please complete the primary address (Street, City, PIN, Country).';
        }
        if (this.useExistingContact) {
            if (!this.existingContactId) return 'Please select an existing Contact.';
        } else {
            if (!this.contactLastName || !this.contactEmail) return 'Contact Last Name and Email are required.';
        }
        return null;
    }

    // ---- submit ----

    async handleSubmit() {
        const err = this.validateClientSide();
        if (err) {
            this.showToast('Missing/invalid information', err, 'warning');
            return;
        }

        this.submitting = true;
        const request = {
            recordTypeId: this.recordTypeId,
            accountName: this.accountName,
            isChildAccount: this.isChildAccount,
            parentAccountId: this.parentAccountId,
            accountSource: this.accountSource,
            industry: this.industry,
            departmentName: this.isDealer ? null : this.departmentName,
            departmentNameMultiSelect: this.isDealer ? (this.selectedMultiDepartments || []).join(';') : null,
            phone: this.phone,
            email: this.email,
            website: this.website,
            pan: this.pan,
            gstin: this.gstin,
            useExistingContact: this.useExistingContact,
            existingContactId: this.existingContactId,
            contactFirstName: this.contactFirstName,
            contactLastName: this.contactLastName,
            contactEmail: this.contactEmail,
            contactPhone: this.contactPhone,
            primaryAddress: this.toAddressPayload(this.primaryAddress),
            additionalAddresses: this.fillMoreAddresses
                ? this.additionalAddresses.filter((a) => a.street).map((a) => this.toAddressPayload(a))
                : []
        };

        try {
            const result = await createAccountFromJson({ reqJson: JSON.stringify(request) });
            this.createdAccountId = result.accountId;
            this.step = 3;
        } catch (e) {
            this.showToast('Could not create Account', this.reduceError(e), 'error');
        } finally {
            this.submitting = false;
        }
    }

    toAddressPayload(a) {
        return { street: a.street, city: a.city, pin: a.pin, country: a.country, state: a.state, zone: a.zone };
    }

    navigateToAccount() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.createdAccountId, objectApiName: 'Account', actionName: 'view' }
        });
    }

    startOver() {
        this.step = 1;
        this.recordTypeId = undefined;
        this.accountName = '';
        this.isChildAccount = false;
        this.parentAccountId = undefined;
        this.accountSource = '';
        this.industry = '';
        this.departmentName = '';
        this.selectedMultiDepartments = [];
        this.phone = '';
        this.email = '';
        this.website = '';
        this.pan = '';
        this.gstin = '';
        this.useExistingContact = false;
        this.existingContactId = undefined;
        this.contactFirstName = '';
        this.contactLastName = '';
        this.contactEmail = '';
        this.contactPhone = '';
        this.primaryAddress = blankAddress();
        this.fillMoreAddresses = false;
        this.additionalAddresses = [];
        this.createdAccountId = undefined;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'An unknown error occurred.';
    }
}