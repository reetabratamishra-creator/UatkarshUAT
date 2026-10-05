// import { LightningElement, api, wire } from 'lwc';
// import getResults from '@salesforce/apex/OCR_Doc_ResultController.getResults';

// export default class OcrDocResults extends LightningElement {
//     @api recordId;
//     results = [];
//     isLoading = true;

//     @wire(getResults, { ocrDocId: '$recordId' })
//     wiredResults({ data, error }) {
//         this.isLoading = false;
//         if (data) {
//             this.results = data;
//         }
//     }

//     get hasResults() {
//         return this.results && this.results.length > 0;
//     }
// }
import { LightningElement, api, wire } from 'lwc';
import getResults from '@salesforce/apex/OCR_Doc_ResultController.getResults';

export default class OcrDocResults extends LightningElement {
    @api recordId;
    flatRows = [];
    isLoading = true;

    @wire(getResults, { ocrDocId: '$recordId' })
    wiredResults({ data, error }) {
        this.isLoading = false;
        if (data) {
            const rows = [];
            data.forEach(res => {
                // Parse matchedSections from JSON string field
                let sections = [];
                try {
                    sections = res.Matched_Sections__c
                        ? JSON.parse(res.Matched_Sections__c)
                        : [];
                } catch (e) {
                    sections = [];
                }

                if (sections.length > 0) {
                    sections.forEach((sec, idx) => {
                        rows.push({
                            rowKey: res.Id + '_' + idx,
                            fileName: res.File_Name__c,
                            department: res.Matched_Department__c,
                            keyword: sec.keyword || '',
                            page: sec.page || '',
                            section: sec.section || '',
                            matchedText: sec.matchedText || ''
                        });
                    });
                } else {
                    // Fallback: show the record with no section detail
                    rows.push({
                        rowKey: res.Id + '_0',
                        fileName: res.File_Name__c,
                        department: res.Matched_Department__c,
                        keyword: res.Matched_Keywords__c || '',
                        page: '',
                        section: '',
                        matchedText: ''
                    });
                }
            });
            this.flatRows = rows;
        }
    }

    get hasResults() {
        return this.flatRows && this.flatRows.length > 0;
    }
}