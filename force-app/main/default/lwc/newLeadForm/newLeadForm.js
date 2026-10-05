import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead';
import PRODUCT_CATEGORY_OBJECT from '@salesforce/schema/Product_Category__c';
import getInitContext from '@salesforce/apex/LeadCreationController.getInitContext';
import getOwnerOptions from '@salesforce/apex/LeadCreationController.getOwnerOptions';
import uploadFile from '@salesforce/apex/LeadCreationController.uploadFile';
import deleteUploadedFile from '@salesforce/apex/LeadCreationController.deleteUploadedFile';
import createLead from '@salesforce/apex/LeadCreationController.createLead';

/* ================================================================
 *  CONSTANTS — extracted verbatim from Lead_New_Lead_Flow .This LWC is for testing purpose not for production,
 * ================================================================ */

// Decision: Checking_if_System_Administrator ($Profile.Name)
const ADMIN_PATH_PROFILES = [
    'System Administrator', 'Utkarsh Admin', 'Utkarsh CRM',
    'CRM Head', 'Utkarsh Sales', 'Utkarsh HOD'
];

// Others-path decision: is_Sales_User
const OTHERS_SALES_PROFILES = ['Utkarsh Sales', 'Utkarsh Tender'];
const OTHERS_HOD_PROFILES = ['Utkarsh HOD', 'CRM Head'];

// Lead Source choice subsets per profile dropdown (flow static choices)
const SOURCES_CRM_HOD = [
    'INBOUND EMAIL', 'INBOUND PHONE CALL', 'EMAIL CAMPAIGNING',
    'OUTBOUND PHONE CALL', 'EVENT ACTIVATION', 'OFFLINE CRM',
    'TENDER', 'CRM RESOURCE', 'Offline Marketing'
];
const SOURCES_CRM_HEAD = [
    'INBOUND EMAIL', 'INBOUND PHONE CALL', 'EMAIL CAMPAIGNING',
    'OUTBOUND PHONE CALL', 'OFFLINE CRM', 'TENDER',
    'CRM RESOURCE', 'Offline Marketing'
];
const SOURCES_SALES = ['TENDER', 'Offline Marketing'];
// Others path: HOD/CRM Head list == SOURCES_CRM_HOD; Sales/Tender == SOURCES_SALES

// Department static choice list for CRM Head / HOD / Sales (Admin path)
const DEPARTMENTS_HOD_HEAD_SALES = [
    'High Mast & Polygonal', 'Steel Pipes', 'Crash Barrier',
    'Steel Tubular Poles', 'Polymer', 'HDPE',
    'Transmission & Telecom Tower', 'Pre-engineered Building',
    'Solar Structure', 'Railway Electrification Structure'
];

// Others path: UserRole.Name CONTAINS token -> department value
// (order preserved from the screen; DeveloperName also checked for safety)
const ROLE_DEPARTMENT_TOKENS = [
    { token: 'High Mast & Polygonal',              value: 'High Mast & Polygonal' },
    { token: 'Steel Pipes',                        value: 'Steel Pipes' },
    { token: 'Crash Barrier',                      value: 'Crash Barrier' },
    { token: 'Steel_Tubular_Poles',                value: 'Steel Tubular Poles' },
    { token: 'HDPE',                               value: 'HDPE' },
    { token: 'Polymer',                            value: 'Polymer' },
    { token: 'TransmissionTelecomTower',           value: 'Transmission & Telecom Tower' },
    { token: 'Pre_engineered_Building',            value: 'Pre-engineered Building' },
    { token: 'Solar_Structure',                    value: 'Solar Structure' },
    { token: 'Railway_Electrification_Structure',  value: 'Railway Electrification Structure' },
    { token: 'Enquiry',                            value: 'Enquiry' }
];

// Doc-required CASE tables — verbatim from the six flow formulas
const R = 'REQUIRED', N = 'NOT REQUIRED';
const DOC_TABLE_ADMIN = {           // DocRequiredforAdmin / DocRequiredforUtkarshCRM_HOD
    'FACEBOOK': R, 'FB LEAD ADS': N, 'INBOUND EMAIL': R, 'INBOUND PHONE CALL': R,
    'INDIAMART': R, 'INDIAMART V2': R, 'ONLINE CAMPAIGNING': N, 'PAY PER CLICK ADS': R,
    'WEBSITE': R, 'WHATSAPP CAMPAIGNING': R, 'EMAIL CAMPAIGNING': R,
    'Offline Marketing': N, 'OUTBOUND PHONE CALL': R, 'EVENT ACTIVATION': N,
    'TENDER': R, 'CRM RESOURCE': N, 'WEBSITE BOT CHAT': R, 'OFFLINE CRM': N
};
const DOC_TABLE_CRM_HEAD = {        // DocRequiredforCRMHead
    'INBOUND EMAIL': R, 'INBOUND PHONE CALL': R, 'EMAIL CAMPAIGNING': R,
    'Offline Marketing': N, 'OUTBOUND PHONE CALL': R, 'TENDER': R,
    'CRM RESOURCE': N, 'OFFLINE CRM': N
};
const DOC_TABLE_SALES = {           // DocRequiredforUtkarshSales
    'Offline Marketing': N, 'TENDER': R
};
const DOC_TABLE_OTHERS = {          // DocRequiredforOthers / DocRequiredforOthers2
    'FACEBOOK': R, 'FB LEAD ADS': N, 'INBOUND EMAIL': R, 'INBOUND PHONE CALL': R,
    'INDIAMART': R, 'ONLINE CAMPAIGNING': N, 'PAY PER CLICK ADS': R,
    'WEBSITE': R, 'WHATSAPP CAMPAIGNING': R, 'EMAIL CAMPAIGNING': R,
    'Offline Marketing': N, 'OUTBOUND PHONE CALL': R, 'EVENT ACTIVATION': N,
    'TENDER': R, 'CRM RESOUCE': N
};

const ENQUIRY = 'Enquiry';
const CRM_RESOURCE = 'CRM RESOURCE';
const MAX_FILE_BYTES = 3.5 * 1024 * 1024; // Apex base64 heap-safe ceiling

let rowKey = 0;

export default class NewLeadForm extends NavigationMixin(LightningElement) {

    /* ---------------- user / path context ---------------- */
    ctx;
    contextError;
    get isAdminPath() {
        return this.ctx && ADMIN_PATH_PROFILES.includes(this.ctx.profileName);
    }
    get isOthersPath() { return this.ctx && !this.isAdminPath; }

    /* ---------------- form state ---------------- */
    @track lead = {
        name: '', email: '', phone: '', companyName: '',
        status: 'Prospect', leadSource: '', previousSource: '', rating: '',
        industry: '', customerCategory: '', departmentName: '',
        zone: '', street: '', city: '', country: '', state: '', pin: ''
    };
    @track productRows = [];
    addProductCategory = true;          // flow's required "Add Product Category" toggle
    @track uploadedFiles = [];          // [{contentDocumentId, fileName}]
    ownerId = '';
    @track ownerOptions = [];
    isSaving = false;
    isUploading = false;

    /* ---------------- picklist wires ---------------- */
    leadRecordTypeId;
    pcRecordTypeId;
    leadPicklists;
    pcPicklists;

    @wire(getInitContext)
    wiredCtx({ data, error }) {
        if (data) {
            this.ctx = data;
            this.applyOthersDefaultDepartment();
        } else if (error) {
            this.contextError = this.reduceError(error);
        }
    }

    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    leadInfo({ data }) {
        if (data) { this.leadRecordTypeId = data.defaultRecordTypeId; }
    }
    @wire(getObjectInfo, { objectApiName: PRODUCT_CATEGORY_OBJECT })
    pcInfo({ data }) {
        if (data) { this.pcRecordTypeId = data.defaultRecordTypeId; }
    }
    @wire(getPicklistValuesByRecordType, {
        objectApiName: LEAD_OBJECT, recordTypeId: '$leadRecordTypeId'
    })
    wiredLeadPicklists({ data }) {
        if (data) { this.leadPicklists = data.picklistFieldValues; }
    }
    @wire(getPicklistValuesByRecordType, {
        objectApiName: PRODUCT_CATEGORY_OBJECT, recordTypeId: '$pcRecordTypeId'
    })
    wiredPcPicklists({ data }) {
        if (data) {
            this.pcPicklists = data.picklistFieldValues;
            if (this.productRows.length === 0) { this.addRow(); }
        }
    }

    @wire(getOwnerOptions, { department: '$ownerFilterDepartment' })
    wiredOwners({ data }) {
        if (data) {
            this.ownerOptions = data.map(o => ({ label: o.label, value: o.value }));
        }
    }

    /* ================================================================
     *  BRANCHING — mirrors flow decisions
     * ================================================================ */

    get profileName() { return this.ctx ? this.ctx.profileName : ''; }

    get isSysOrUtkarshAdmin() {
        return ['System Administrator', 'Utkarsh Admin'].includes(this.profileName);
    }
    get isUtkarshCRM()  { return this.profileName === 'Utkarsh CRM'; }
    get isCRMHead()     { return this.profileName === 'CRM Head'; }
    get isUtkarshHOD()  { return this.profileName === 'Utkarsh HOD'; }
    get isUtkarshSales(){ return this.profileName === 'Utkarsh Sales'; }

    get isOthersSalesGroup() {
        return this.isOthersPath && OTHERS_SALES_PROFILES.includes(this.profileName);
    }
    get isOthersHodGroup() {
        // flow default: any non-sales profile on Others path uses the HOD/Dept-Head dropdown
        return this.isOthersPath && !this.isOthersSalesGroup;
    }

    /* ----- Lead Source options: profile-specific dropdown, as on the screens ----- */
    get leadSourceOptions() {
        if (this.isSysOrUtkarshAdmin) {
            return this.picklist('LeadSource');                    // full choice set
        }
        if (this.isUtkarshCRM || this.isUtkarshHOD) {
            return this.toOptions(SOURCES_CRM_HOD);
        }
        if (this.isCRMHead)      { return this.toOptions(SOURCES_CRM_HEAD); }
        if (this.isUtkarshSales) { return this.toOptions(SOURCES_SALES); }
        if (this.isOthersSalesGroup) { return this.toOptions(SOURCES_SALES); }
        return this.toOptions(SOURCES_CRM_HOD);                    // Others: HOD/Dept-Head list
    }

    /* ----- Department field: which control, which values ----- */
    get showDepartmentFullPicklist() {   // DepartmentAdminCRMUser (Admin / Utkarsh CRM)
        return this.isSysOrUtkarshAdmin || this.isUtkarshCRM;
    }
    get showDepartmentStaticList() {     // DepartmentHODCRMHeadSales
        return this.isCRMHead || this.isUtkarshHOD || this.isUtkarshSales;
    }
    get departmentOptions() {
        if (this.showDepartmentFullPicklist) {
            return this.picklist('Department_Name__c');
        }
        if (this.showDepartmentStaticList) {
            return this.toOptions(DEPARTMENTS_HOD_HEAD_SALES);
        }
        // Others path: role-gated single choices (Get_UserRole.Name Contains token)
        const roleText = `${this.ctx?.roleName || ''}||${this.ctx?.roleDeveloperName || ''}`;
        return ROLE_DEPARTMENT_TOKENS
            .filter(t => roleText.includes(t.token))
            .map(t => ({ label: t.value, value: t.value }));
    }

    applyOthersDefaultDepartment() {
        if (this.isOthersPath) {
            const opts = this.departmentOptions;
            if (opts.length === 1) {
                this.lead = { ...this.lead, departmentName: opts[0].value };
            }
        }
    }

    /* ----- Previous Source: visible only when source == CRM RESOURCE ----- */
    get showPreviousSource() {
        return this.lead.leadSource === CRM_RESOURCE
            || this.lead.leadSource === 'CRM RESOUCE';
    }

    /* ----- Enquiry: hide product categories (flow visibility + skip) ----- */
    get isEnquiryDepartment() { return this.lead.departmentName === ENQUIRY; }
    get showProductSection()  {
        return !!this.lead.departmentName && !this.isEnquiryDepartment;
    }
    get showProductRows() { return this.showProductSection && this.addProductCategory; }

    /* ----- Owner rules (decision: is_CRM_user_with_department_enquiry) ----- */
    get needsOwnerSelection() {
        if (!this.ctx || this.isOthersPath) { return false; }   // Others: OwnerId = $User.Id
        if (this.isSysOrUtkarshAdmin) { return true; }
        if (this.isUtkarshCRM) { return !this.isEnquiryDepartment; }
        // CRM Head / HOD / Sales: choose owner only when dept != own department
        return this.lead.departmentName !== (this.ctx.userDepartment || '');
    }
    get showOwnerSection() {
        return !!this.lead.departmentName && this.needsOwnerSelection;
    }
    get ownerFilterDepartment() {
        return this.showOwnerSection ? this.lead.departmentName : '';
    }
    get ownerSummary() {
        if (!this.lead.departmentName) { return ''; }
        return this.needsOwnerSelection
            ? ''
            : `Lead owner: ${this.ctx?.userName || 'you'} (auto-assigned)`;
    }

    /* ----- Doc-required blocking (six CASE formulas) ----- */
    get docRequirement() {
        const src = this.lead.leadSource;
        if (!src) { return ''; }
        let table;
        if (this.isSysOrUtkarshAdmin)                { table = DOC_TABLE_ADMIN; }
        else if (this.isUtkarshCRM || this.isUtkarshHOD) { table = DOC_TABLE_ADMIN; }
        else if (this.isCRMHead)                     { table = DOC_TABLE_CRM_HEAD; }
        else if (this.isUtkarshSales)                { table = DOC_TABLE_SALES; }
        else                                          { table = DOC_TABLE_OTHERS; }
        return table[src] || '';
    }
    get isDocRequired()   { return this.docRequirement === R; }
    get showFileSection() { return this.isDocRequired; }
    get docBlockActive()  { return this.isDocRequired && this.uploadedFiles.length === 0; }
    get hasUploadedFiles(){ return this.uploadedFiles.length > 0; }

    /* ----- State visible only when Country == India ----- */
    get showState() { return this.lead.country === 'India'; }

    /* ================================================================
     *  PICKLIST HELPERS
     * ================================================================ */

    picklist(fieldApiName, source) {
        const src = source || this.leadPicklists;
        if (!src || !src[fieldApiName]) { return []; }
        return src[fieldApiName].values.map(v => ({ label: v.label, value: v.value }));
    }
    toOptions(list) { return list.map(v => ({ label: v, value: v })); }

    get statusOptions()           { return this.picklist('Status'); }
    get ratingOptions()           { return this.picklist('Rating'); }
    get industryOptions()         { return this.picklist('Industry'); }
    get previousSourceOptions()   { return this.picklist('Previous_Source__c'); }
    get customerCategoryOptions() { return this.picklist('Customer_Category__c'); }
    get zoneOptions()             { return this.picklist('Zone__c'); }
    get countryOptions()          { return this.picklist('Country__c'); }
    get stateOptions() {
        // dependent State__c filtered by Country__c via validFor
        if (!this.leadPicklists || !this.leadPicklists.State__c) { return []; }
        const field = this.leadPicklists.State__c;
        const ctrlValues = this.leadPicklists.Country__c
            ? this.leadPicklists.Country__c.values.map(v => v.value) : [];
        const idx = ctrlValues.indexOf(this.lead.country);
        return field.values
            .filter(v => idx < 0 || !v.validFor || v.validFor.includes(idx))
            .map(v => ({ label: v.label, value: v.value }));
    }

    get pcDepartmentOptions() {
        return this.picklist('Department_Name__c', this.pcPicklists);
    }
    get uomOptions() {
        return this.picklist('UOM__c', this.pcPicklists);
    }
    categoryOptionsFor(department) {
        if (!this.pcPicklists || !this.pcPicklists.Product_Category__c) { return []; }
        const field = this.pcPicklists.Product_Category__c;
        const ctrlValues = this.pcPicklists.Department_Name__c
            ? this.pcPicklists.Department_Name__c.values.map(v => v.value) : [];
        const idx = ctrlValues.indexOf(department);
        if (idx < 0) { return []; }
        return field.values
            .filter(v => v.validFor && v.validFor.includes(idx))
            .map(v => ({ label: v.label, value: v.value }));
    }

    /* ================================================================
     *  PRODUCT CATEGORY ROWS (flow repeater)
     * ================================================================ */

    addRow() {
        rowKey += 1;
        this.productRows = [...this.productRows, {
            key: `row-${rowKey}`,
            department: this.lead.departmentName || '',
            category: '', uom: '', quantity: null,
            categoryOptions: this.categoryOptionsFor(this.lead.departmentName || '')
        }];
    }
    handleAddRow() { this.addRow(); }
    handleRemoveRow(event) {
        const key = event.currentTarget.dataset.key;
        if (this.productRows.length > 1) {
            this.productRows = this.productRows.filter(r => r.key !== key);
        }
    }
    handleRowChange(event) {
        const { key, field } = event.currentTarget.dataset;
        const value = field === 'quantity'
            ? (event.detail.value === '' ? null : Number(event.detail.value))
            : event.detail.value;
        this.productRows = this.productRows.map(r => {
            if (r.key !== key) { return r; }
            const next = { ...r, [field]: value };
            if (field === 'department') {
                next.category = '';
                next.categoryOptions = this.categoryOptionsFor(value);
            }
            return next;
        });
    }
    get productRowsDisplay() {
        return this.productRows.map((r, i) => ({
            ...r,
            index: i + 1,
            removeDisabled: this.productRows.length <= 1
        }));
    }
    handleToggleProducts(event) {
        this.addProductCategory = event.detail.checked;
    }

    /* ================================================================
     *  FIELD HANDLERS
     * ================================================================ */

    handleLeadChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.detail ? event.detail.value : event.target.value;
        const next = { ...this.lead, [field]: value };

        if (field === 'leadSource') {
            // flow: Previous Source only participates when CRM RESOURCE
            if (value !== CRM_RESOURCE && value !== 'CRM RESOUCE') {
                next.previousSource = '';
            }
        }
        if (field === 'country' && value !== 'India') { next.state = ''; }
        if (field === 'departmentName') {
            this.ownerId = '';
            // reset rows to new default department (flow repeater topValue default)
            this.productRows = this.productRows.map(r => ({
                ...r,
                department: value,
                category: '',
                categoryOptions: this.categoryOptionsFor(value)
            }));
        }
        this.lead = next;
    }
    handleOwnerChange(event) { this.ownerId = event.detail.value; }

    /* ================================================================
     *  FILE UPLOAD (before Lead exists, as in the flow)
     * ================================================================ */

    handleFileSelected(event) {
        const files = Array.from(event.target.files || []);
        event.target.value = null;
        files.forEach(file => {
            if (file.size > MAX_FILE_BYTES) {
                this.toast('File too large',
                    `${file.name} exceeds 3.5 MB. Please upload a smaller file.`, 'error');
                return;
            }
            this.isUploading = true;
            const reader = new FileReader();
            reader.onload = () => {
                const base64 = String(reader.result).split(',')[1];
                uploadFile({ fileName: file.name, base64Data: base64 })
                    .then(res => {
                        this.uploadedFiles = [...this.uploadedFiles, {
                            contentDocumentId: res.contentDocumentId,
                            fileName: res.fileName
                        }];
                    })
                    .catch(err => this.toast('Upload failed', this.reduceError(err), 'error'))
                    .finally(() => { this.isUploading = false; });
            };
            reader.readAsDataURL(file);
        });
    }
    handleRemoveFile(event) {
        const docId = event.currentTarget.dataset.docid;
        deleteUploadedFile({ contentDocumentId: docId })
            .catch(() => { /* best-effort */ });
        this.uploadedFiles = this.uploadedFiles.filter(f => f.contentDocumentId !== docId);
    }

    /* ================================================================
     *  SUBMIT
     * ================================================================ */

    get submitDisabled() { return this.isSaving || this.isUploading; }

    handleSubmit() {
        if (!this.validate()) { return; }
        this.isSaving = true;

        const name = (this.lead.name || '').trim();
        const hasSpace = name.includes(' ');
        // FirstNameFormula / LastNameFormula
        const firstName = hasSpace ? name.substring(0, name.indexOf(' ')) : '';
        const lastName  = hasSpace ? name.substring(name.indexOf(' ') + 1).trim() : name;
        // CompanyFormula: Company_Name__c if present, else Name
        const company = this.lead.companyName ? this.lead.companyName : name;

        const payload = {
            firstName, lastName, company,
            companyName: this.lead.companyName,
            email: this.lead.email,
            phone: this.lead.phone,
            status: this.lead.status || 'Prospect',
            leadSource: this.lead.leadSource,
            previousSource: this.showPreviousSource ? this.lead.previousSource : '',
            rating: this.lead.rating,
            industry: this.lead.industry,
            customerCategory: this.lead.customerCategory,
            departmentName: this.lead.departmentName,
            zone: this.lead.zone,
            street: this.lead.street,
            city: this.lead.city,
            country: this.lead.country,
            state: this.showState ? this.lead.state : '',
            pin: this.lead.pin,
            ownerId: this.needsOwnerSelection ? this.ownerId : this.ctx.userId,
            productCategories: this.isEnquiryDepartment ? [] :
                this.productRows
                    .filter(r => r.category)
                    .map(r => ({
                        department: r.department,
                        category: r.category,
                        uom: r.uom,
                        quantity: r.quantity
                    })),
            contentDocumentIds: this.uploadedFiles.map(f => f.contentDocumentId)
        };

        createLead({ payloadJson: JSON.stringify(payload) })
            .then(result => {
                this.toast('Success', 'Lead has been created successfully', 'success');
                if (result.notificationsQueued === false) {
                    this.toast('Notification warning',
                        'Lead saved, but email/WhatsApp could not be queued: '
                        + (result.notificationError || ''), 'warning');
                }
                this.redirectToListView(result.listViewId);
            })
            .catch(err => this.toast('Error', this.reduceError(err), 'error'))
            .finally(() => { this.isSaving = false; });
    }

    validate() {
        // native input validity (required, email, tel, number)
        let valid = true;
        this.template.querySelectorAll(
            'lightning-input, lightning-combobox, lightning-textarea'
        ).forEach(el => {
            if (!el.reportValidity()) { valid = false; }
        });
        if (!valid) {
            this.toast('Missing information',
                'Please complete the highlighted fields.', 'error');
            return false;
        }
        // flow-equivalent blocking
        if (this.needsOwnerSelection && !this.ownerId) {
            this.toast('Choose Lead owner',
                'Please choose a Lead owner for the selected department.', 'error');
            return false;
        }
        if (this.showProductSection) {
            if (!this.addProductCategory) {
                this.toast('Product Category required',
                    'Please enable and add at least one product category.', 'error');
                return false;
            }
            const complete = this.productRows.some(r => r.department && r.category);
            if (!complete) {
                this.toast('Product Category required',
                    'Please add at least one product category row.', 'error');
                return false;
            }
        }
        if (this.docBlockActive) {
            this.toast('Document required',
                `Lead Source "${this.lead.leadSource}" requires a supporting document. `
                + 'Please upload it before saving.', 'error');
            return false;
        }
        return true;
    }

    redirectToListView(listViewId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Lead', actionName: 'list' },
            state: { filterName: listViewId || 'Recent' }
        });
    }

    /* ---------------- utils ---------------- */
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    reduceError(err) {
        if (!err) { return 'Unknown error'; }
        if (err.body && err.body.message) { return err.body.message; }
        if (Array.isArray(err.body)) {
            return err.body.map(e => e.message).join(', ');
        }
        return err.message || JSON.stringify(err);
    }
}