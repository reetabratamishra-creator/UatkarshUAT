import { LightningElement, api, wire } from 'lwc';
import getPQCData from '@salesforce/apex/PQCViewerController.getPQCData';
import generateAndAttachPDF from '@salesforce/apex/PQCViewerController.generateAndAttachPDF';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class pqcViewer extends LightningElement {
    @api recordId;

    pqcResult;
    isLoading = true;
    isSaving = false;

    @wire(getPQCData, { recordId: '$recordId' })
    wiredPQC({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.pqcResult = data;
        } else if (error) {
            this.pqcResult = undefined;
            this.showToast('Error', 'Could not load PQC data.', 'error');
        }
    }

    get hasError() {
        return this.pqcResult && this.pqcResult.errorMessage;
    }

    get hasItems() {
        return this.pqcResult && this.pqcResult.items && this.pqcResult.items.length > 0;
    }

    // Decorates each raw item with a unique row key + a ready-to-use badge class
    // get items() {
    //     if (!this.pqcResult || !this.pqcResult.items) {
    //         return [];
    //     }
    //     return this.pqcResult.items.map((item, index) => {
    //         return {
    //             ...item,
    //             key: index + '-' + (item.pqcLabel || 'item'),
    //             badgeClass: 'slds-badge ' + this.getBadgeTheme(item.statusVariant)
    //         };
    //     });
    // }
    get items() {
    if (!this.pqcResult || !this.pqcResult.items) return [];
    return this.pqcResult.items.map((item, index) => ({
        ...item,
        key       : index + '-' + (item.pqcLabel || 'item'),
        badgeClass: 'status-badge ' + this.getBadgeTheme(item.statusVariant)
    }));
}

    getBadgeTheme(variant) {
        if (variant === 'success') return 'badge-found';
        if (variant === 'error') return 'badge-notfound';
        if (variant === 'warning') return 'badge-partial';
        return 'badge-default';
    }

    get totalCount() {
        return this.items.length;
    }

    get foundCount() {
        return this.countByStatus('found');
    }

    get notFoundCount() {
        return this.countByStatus('not found');
    }

    get partialCount() {
        return this.countByStatus('partial');
    }

    countByStatus(target) {
        return this.items.filter(
            (i) => i.status && i.status.toLowerCase() === target
        ).length;
    }

    // Opens the Visualforce PDF page in a new tab — the browser
    // downloads/displays the PDF directly, nothing is saved to the record.
    handleDownloadPdf() {
        const url = '/apex/PQCReportPDF?id=' + this.recordId;
        window.open(url, '_blank');
    }

    // Generates the same PDF server-side and attaches it to the record
    // as a file (visible in the record's Files related list).
    async handleSaveAsAttachment() {
        this.isSaving = true;
        try {
            await generateAndAttachPDF({ recordId: this.recordId });
            this.showToast('Success', 'PQC report saved as an attachment on this record.', 'success');
        } catch (error) {
            const message = (error && error.body && error.body.message) || 'Unknown error';
            this.showToast('Error', 'Failed to save PDF: ' + message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}