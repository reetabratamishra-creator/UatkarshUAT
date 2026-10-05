import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

import getDashboardData
from '@salesforce/apex/OCRDocOverviewController.getDashboardData';

const COLUMNS = [
    {
        label: 'Document Name',
        fieldName: 'Name'
    },
    {
        label: 'Status',
        fieldName: 'AI_Status__c'
    },
    {
        label: 'Confidence',
        fieldName: 'Confidence_Score__c',
        type: 'percent'
    },
    {
        label: 'Created Date',
        fieldName: 'CreatedDate',
        type: 'date'
    },
    {
        type: 'button',
        typeAttributes: {
            label: 'View',
            name: 'view',
            variant: 'brand'
        }
    }
];

export default class OcrDocOverview extends NavigationMixin(LightningElement) {

    dashboard;

    columns = COLUMNS;

    @wire(getDashboardData)
    wiredDashboard({ data, error }) {

        if (data) {
            this.dashboard = data;
        } else if (error) {
            console.error(error);
        }
    }

    handleRowAction(event) {

        const row = event.detail.row;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: row.Id,
                objectApiName: 'OCR_DOC__c',
                actionName: 'view'
            }
        });
    }
}