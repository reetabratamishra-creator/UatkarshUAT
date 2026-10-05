import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import AI_STATUS from '@salesforce/schema/OCR_DOC__c.AI_Status__c';
import AI_RESPONSE from '@salesforce/schema/OCR_DOC__c.AI_Response__c';
import CONFIDENCE_SCORE from '@salesforce/schema/OCR_DOC__c.Confidence_Score__c';
import MATCHED_DEPT from '@salesforce/schema/OCR_DOC__c.Matched_Department__c';
import MATCHED_KEYWORDS from '@salesforce/schema/OCR_DOC__c.Matched_Keywords__c';
import ERROR_MESSAGE from '@salesforce/schema/OCR_DOC__c.Error_Message__c';
import PQC_DETAILS1 from '@salesforce/schema/OCR_DOC__c.PQCDetails1__c';
import PQC_DETAILS2 from '@salesforce/schema/OCR_DOC__c.PQCDetails2__c';
import FILE_COUNT from '@salesforce/schema/OCR_DOC__c.Uploaded_File_Count__c';

const FIELDS = [
    AI_STATUS, AI_RESPONSE, CONFIDENCE_SCORE,
    MATCHED_DEPT, MATCHED_KEYWORDS, ERROR_MESSAGE,
    PQC_DETAILS1, PQC_DETAILS2, FILE_COUNT
];

export default class TenderAnalysisViewer extends LightningElement {

    @api recordId;

    _record;
    _error;
    // @track _expandedRows = new Set();

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this._record = data;
            this._error = null;
        } else if (error) {
            this._error = error;
            this._record = null;
        }
    }

    // ── Status helpers ──────────────────────────────────────
    get aiStatus() {
        if (!this._record) return '';
        return getFieldValue(this._record, AI_STATUS) || '';
    }

    get isPending() { return this.aiStatus === 'Pending'; }
    get isProcessing() { return this.aiStatus === 'Processing'; }
    get isFailed() { return this.aiStatus === 'Failed'; }
    get isCompleted() { return this.aiStatus === 'Completed'; }

    // ── Basic fields ────────────────────────────────────────
    get uploadedFileCount() {
        return getFieldValue(this._record, FILE_COUNT) || 0;
    }

    get matchedDepartment() {
        return getFieldValue(this._record, MATCHED_DEPT) || '—';
    }

    get errorMessage() {
        return getFieldValue(this._record, ERROR_MESSAGE);
    }

    // ── Category result (parsed from AI_Response__c) ────────
    get _categoryResult() {
        try {
            const raw = getFieldValue(this._record, AI_RESPONSE);
            return raw ? JSON.parse(raw) : null;
        } catch (e) {
            return null;
        }
    }

    get matchedCategory() {
        const r = this._categoryResult;
        return r ? (r.matchedCategory || '—') : '—';
    }

    get summary() {
        const r = this._categoryResult;
        return r ? r.summary : null;
    }

    get relevanceLabel() {
        const r = this._categoryResult;
        if (!r) return '—';
        return r.isRelevant ? '✔ Relevant' : '✘ Not Relevant';
    }

    get exclusionLabel() {
        const r = this._categoryResult;
        if (!r) return '—';
        return r.isExcluded ? '✘ Excluded' : '✔ Not Excluded';
    }

    // ── Confidence ──────────────────────────────────────────
    get confidenceScore() {
        const score = getFieldValue(this._record, CONFIDENCE_SCORE);
        if (score === 1) return 'High';
        if (score === 0.5) return 'Medium';
        return 'Low';
    }

    get confidenceLower() {
        return this.confidenceScore.toLowerCase();
    }

    // REPLACE the matchedKeywords getter with this simplified version:
    get matchedKeywords() {
        try {
            const raw = getFieldValue(this._record, MATCHED_KEYWORDS);
            if (!raw) return [];
            const parsed = JSON.parse(raw);
            if (!Array.isArray(parsed)) return [];

            return parsed.map((item, index) => {
                // Split "FileName, page 5" → fileName + pageNum
                const rawPage = item.page || '';
                const commaIdx = rawPage.lastIndexOf(', page');
                const fileName = commaIdx > -1 ? rawPage.substring(0, commaIdx).trim() : rawPage;
                const pageNum = commaIdx > -1 ? rawPage.substring(commaIdx + 2).trim() : '';

                return {
                    ...item,
                    rowId: index,
                    uniqueKey: item.keyword + '_' + index,
                    fileName: fileName,
                    pageNum: pageNum
                };
            });
        } catch (e) {
            return [];
        }
    }

    get hasMatchedKeywords() {
        return this.matchedKeywords.length > 0;
    }

    // ── Toggle page cell expand/collapse ────────────────────
    // togglePageExpand(event) {
    //     const id = parseInt(event.currentTarget.dataset.rowid, 10);
    //     const updated = new Set(this._expandedRows);
    //     if (updated.has(id)) {
    //         updated.delete(id);
    //     } else {
    //         updated.add(id);
    //     }
    //     this._expandedRows = updated;
    // }

    // ── PQC Items ───────────────────────────────────────────
    get _pqcRaw() {
        const p1 = getFieldValue(this._record, PQC_DETAILS1) || '';
        const p2 = getFieldValue(this._record, PQC_DETAILS2) || '';
        return p1 + p2;
    }

    get pqcItems() {
        try {
            if (!this._pqcRaw) return [];
            const parsed = JSON.parse(this._pqcRaw);
            const items = parsed.pqcAnalysis || [];
            return items.map(item => {
                const status = (item.status || '').trim();
                const isFound = status === 'Found';
                const isPartial = status === 'Partial';

                return {
                    ...item,
                    cardClass: 'pqc-card pqc-card-' + (isFound ? 'found' : isPartial ? 'partial' : 'notfound'),
                    statusClass: 'pqc-status-badge ' + (isFound ? 'badge-found' : isPartial ? 'badge-partial' : 'badge-notfound'),
                    statusDotClass: 'pqc-status-dot ' + (isFound ? 'dot-found' : isPartial ? 'dot-partial' : 'dot-notfound'),
                    pageReference: item.pageReference !== 'N/A' ? item.pageReference : null
                };
            });
        } catch (e) {
            return [];
        }
    }

    get hasPQC() {
        return this.pqcItems.length > 0;
    }
}