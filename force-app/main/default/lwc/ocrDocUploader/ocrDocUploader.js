import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import createOCRDocument from '@salesforce/apex/OCRDocOverviewController.createOCRDocument';

export default class OcrDocUploader extends NavigationMixin(LightningElement) {

    @track uploadedFiles = [];
    isLoading = false;

    acceptedFormats = ['.pdf', '.docx', '.xlsx'];

    get uploadedFileCount() {
        return this.uploadedFiles.length + ' Files';
    }

    get isDisabled() {
        return this.uploadedFiles.length === 0 || this.isLoading;
    }

    handleUploadFinished(event) {
        this.uploadedFiles = event.detail.files;
    }

    handleSubmit() {
        this.isLoading = true;

        const contentDocumentIds = this.uploadedFiles.map(f => f.documentId);

        createOCRDocument({ contentDocumentIds })
            .then(result => {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: result,
                        objectApiName: 'OCR_DOC__c',
                        actionName: 'view'
                    }
                });
            })
            .catch(error => {
                console.error(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
}