import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { RefreshEvent } from 'lightning/refresh';
import getFiles from '@salesforce/apex/RecordFilesListController.getFiles';

const ICONS = {
    pdf: 'doctype:pdf',
    png: 'doctype:image', jpg: 'doctype:image', jpeg: 'doctype:image', gif: 'doctype:image',
    bmp: 'doctype:image', svg: 'doctype:image',
    doc: 'doctype:word', docx: 'doctype:word',
    xls: 'doctype:excel', xlsx: 'doctype:excel',
    csv: 'doctype:csv',
    ppt: 'doctype:ppt', pptx: 'doctype:ppt',
    zip: 'doctype:zip', rar: 'doctype:zip',
    txt: 'doctype:txt', log: 'doctype:txt',
    xml: 'doctype:xml', html: 'doctype:html',
    mp4: 'doctype:video', mov: 'doctype:video',
    mp3: 'doctype:audio', wav: 'doctype:audio'
};
const MAX_TITLE = 60;

export default class RecordFilesList extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;
    @api maxRows = 6;

    files = [];
    totalCount = 0;
    error;
    isLoading = true;
    wiredResult;

    @wire(getFiles, { recordId: '$recordId', maxRows: '$maxRows' })
    wiredFiles(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.totalCount = data.totalCount;
            this.files = data.files.map((f) => this.decorate(f));
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.error = error?.body?.message || 'Unable to load files.';
            this.files = [];
            this.isLoading = false;
        }
    }

    get hasFiles() {
        return this.files.length > 0;
    }

    get showViewAll() {
        return this.totalCount > 0;
    }

    decorate(f) {
        const ext = (f.fileExtension || '').toLowerCase();
        const title = f.title || '';
        return {
            id: f.contentDocumentId,
            title,
            displayTitle: title.length > MAX_TITLE ? `${title.substring(0, MAX_TITLE)}…` : title,
            fileExtension: ext,
            iconName: ICONS[ext] || 'doctype:unknown',
            sizeLabel: this.formatSize(f.contentSize),
            modifiedDate: this.formatDate(f.lastModified)
        };
    }

    // 28-Oct-2026
    formatDate(value) {
        if (!value) return '';
        const d = new Date(value);
        const mon = d.toLocaleString('en-US', { month: 'short' });
        return `${String(d.getDate()).padStart(2, '0')}-${mon}-${d.getFullYear()}`;
    }

    // 767B, 12KB, 1.5MB
    formatSize(bytes) {
        if (bytes === null || bytes === undefined) return '';
        if (bytes < 1024) return `${bytes}B`;
        const kb = bytes / 1024;
        if (kb < 1024) return `${Math.round(kb)}KB`;
        const mb = kb / 1024;
        if (mb < 1024) return `${mb.toFixed(1).replace(/\.0$/, '')}MB`;
        return `${(mb / 1024).toFixed(1).replace(/\.0$/, '')}GB`;
    }

    handleOpenFile(event) {
        event.preventDefault();
        const id = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: {
                recordIds: this.files.map((f) => f.id).join(','),
                selectedRecordId: id
            }
        });
    }

    handleViewAll(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: this.objectApiName,
                relationshipApiName: 'AttachedContentDocuments',
                actionName: 'view'
            }
        });
    }

    // Re-query when the page is refreshed (e.g. a file was added elsewhere on the page)
    connectedCallback() {
        this.addEventListener('refreshview', () => refreshApex(this.wiredResult));
    }

    @api
    refresh() {
        return refreshApex(this.wiredResult).then(() => this.dispatchEvent(new RefreshEvent()));
    }
}