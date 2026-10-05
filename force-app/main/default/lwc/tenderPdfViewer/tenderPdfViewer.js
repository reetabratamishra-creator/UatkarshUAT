import { LightningElement, api, wire, track } from 'lwc';
import { loadScript }     from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import JSPDF_LIB           from '@salesforce/resourceUrl/jspdf';
import getTenderData       from '@salesforce/apex/TenderPdfController.getTenderData';
import saveToFiles         from '@salesforce/apex/TenderPdfController.saveToFiles';


// HTML stripper -

function stripHtml(html) {
    if (!html) return '—';
    return html
        .replace(/<br\s*\/?>/gi, '\n')
        .replace(/<\/p>/gi, '\n\n')
        .replace(/<\/tr>/gi, '\n')
        .replace(/<\/th>/gi, '   ')
        .replace(/<\/td>/gi, '   ')
        .replace(/<li>/gi, '\n  • ')
        .replace(/<\/li>/gi, '')
        .replace(/<b>/gi, '').replace(/<\/b>/gi, '')
        .replace(/<[^>]+>/g, '')
        .replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&nbsp;/g, ' ')
        .replace(/[ \t]+\n/g, '\n')
        .replace(/\n{3,}/g, '\n\n')
        .trim();
}

// FULL STATIC DATA — 
const RAW_JSON = {
    Tender_Id: "99724498",
    Bid_End_Date_Time: "For Sr. No. 2 & 10: 14.05.2026 15:30<br/>For Sr. No. 01 & 03 to 09: 25.05.2026 15:30",
    Bid_Opening_Date_Time: "Bid Opening Date (Technical) for Sr. No. 2 & 10: 15.05.2026 15:30<br/>Bid Opening Date (Financial) for Sr. No. 2 & 10: To be intimated later on<br/>Bid Opening Date (Technical) for Sr. No. 01 & 03 to 09: 26.05.2026 15:30<br/>Bid Opening Date (Financial) for Sr. No. 01 & 03 to 09: To be intimated later on",
    Department_Name: "MADHYA PRADESH ROAD DEVELOPMENT CORPORATION LIMITED",
    Site_location: "Matkuli – Pachmarhi road between km. 10 to 24 (SH 41A), Naramdapuram, Madhya Pradesh",
    Emd_Instrument_Type: "No",
    Completion_Period: "06 months (Including rainy season)",
    Category: "Providing and Erection of Single Roller Crash Barrier and road safety work on Matkuli – Pachmarhi road between km. 10 to 24 (SH 41A) (2nd Call)",
    Location: "45-A, Arera Hills, Bhopal – 462 011, Madhya Pradesh",
    Products: "<ul><li>Road Restraint System i.e. Single Roller Crash Barrier System...</li><li>Metal Beam Crash Barrier Type A, W...</li><li>Retro-reflectorised Traffic signs...</li><li>Road Delineators...</li><li>Road Markers/Road Stud with Lens Reflector...</li><li>PCC Grade M20...</li><li>Road Marking with Hot Applied Thermoplastic Compound...</li></ul>",
    State: "Madhya Pradesh",
    Estimated_Cost: "824.30 Lacs",
    EMD_Value: "8.24 Lakh",
    Emd_Mode_Type: "EMD to be paid online.",
    Document_Fees: "23,600/-",
    Pre_Bid_Meeting: "30:04:2026 15:30",
    Joint_Venture_OR_Consortium_OR_JV: "No",
    Performance_Bank_Guarantee: "5% of accepted contract amount",
    Payment_terms: "<p>Payment to the contractor for construction work:<br/>(a) The Contractor shall submit to the Engineer monthly statements of the value of the work executed less the cumulative amount certified previously, supported with detailed measurement of the items of work executed.<br/>(b) The Engineer shall check the Contractor's monthly statement and certify the amount to be paid to the Contractor.<br/>(c) The value of work executed shall be determined, based on the measurements approved by the Engineer/ Engineer-in-charge.<br/>(d) The value of work executed shall comprise the value of the quantities of the items in the Bill of Quantities completed.<br/>(e) The value of work executed shall also include the valuation of Variations and Compensation Events.<br/>(f) All payments shall be adjusted for deductions for advance payment, security deposit, other recoveries in terms of contract and taxes at source as applicable under the law.<br/>(g) The Engineer may exclude any item certified in a previous certificate or reduce the proportion of any item previously certified in any certificate in the light of later information.<br/>(h) Payment of intermediate certificate shall be regarded as payments by way of advance against the final payment and not as payments for work actually done and completed.<br/>(i) Intermediate payment shall not preclude the requiring of bad, unsound and imperfect or unskilled work to be removed and taken away and reconstructed or be considered as an admission of the due performance of the contractor any part thereof, in any respect or the occurring of any claim.<br/>(j) The payment of final bill shall be governed by the provisions of clause 36 of GCC.</p><p>Recovery of Mobilization and/or Construction Machinery advance shall commence when 10% of the Contract Amount is executed and recovery of total advance shall be done on pro-rata basis and shall be completed by the time work equivalent to 80% of the Contract Amount is executed. In addition to the recovery of principal amount, recovery of interest shall be carried out as calculated on the outstanding amount of principal at the close of each month. The interest shall be accrue from the day of payment of advance and the recovery of interest shall commence when 10% of the Contract Amount is executed and shall be completed by the time work equivalent to 80% of the Contract Amount is executed.</p><p>The advance for Secured Advance shall be repaid from each succeeding monthly payments to the extent materials for which advance was previously paid have been incorporated into the Works.</p>",
    Levy_of_Penalty: "<p>Penalty Shall include</p><ul><li>Security deposit as per clause 30 of General Conditions of Contract and percentage to apply to the value of work not completed representing the Employer's additional cost for completing the works shall be 20 Percent.</li><li>Liquidated Damages imposed as per clause 15 or Performance Security (Guarantee) including Additional Performance Security (Guarantee), if any, as per clause 29 of General Conditions of Contract, whichever is higher.</li></ul>",
    Defect_Liability_Period: "<p>The performance security shall be in the shape of bank guarantee (e-BG) of any nationalized / schedule commercial bank valid up to three months after the expiry of defects liability period.</p>",
    Affidavit_notarized_documents: "<p>Yes, the tender requires the submission of an affidavit as per Annexure - B. This affidavit must be duly notarized and included in Envelope A. A scanned copy of the affidavit should be uploaded online, and the original affidavit will be submitted by the successful bidder at the time of signing the Contract.</p>",
    Mandatory_Pre_bid_Meeting: "Yes",
    Site_Visit_Requirement: "The bidder is advised to visit and inspect the Site of Works and its surroundings and obtain for itself on its own responsibility all information that may be necessary for preparing the bid and entering into a contract for construction of the work. All costs in this respect shall have to be borne by the bidder.",
    Eligibility_Criteria: "<p><b>General Eligibility:</b> Online percentage rate bids are invited from registered contractors and firms of repute fulfilling registration criteria. The bidder can be an individual entity only. Joint Venture (JV)/consortium participation is not permitted for this tender. No bidder shall be entitled to submit more than one bid. Bidders must have valid registration with the Government of Madhya Pradesh at the time of bid submission.</p><p><b>Financial Qualifications:</b> Minimum Average Annual Turnover not less than 50% of estimated cost in any one financial year during the last five financial years (only when PAC > Rs. 2.00 Crore). Turnover certified by Chartered Accountant based on audited financial statements.</p><p><b>Past Performance / Similar Work Experience:</b> Similar Work Definition: 'Providing and Fixing Single Roller Crash Barrier'. Bidder must complete either 3 similar works (20% value each), 2 similar works (30% value each), or 1 similar work (50% value) in last 5 financial years.</p><p><b>Manpower Requirements:</b> Project Manager (B.E. Civil, 10 yrs exp), Material Engineer (B.E. Civil, 7 yrs), Site/Field Engineer, Plants & Equipment Engineer, Quality Control & Testing Engineer, Quantity Surveyor — each with specified experience.</p><p><b>Mandatory Certifications:</b> MP PWD Registration (active), GST Registration, GSTIN, crash test certification (FHWA/AASHTO MASH TL-4 or EN-1317-5 CE B-grade or SB4/SB5 Korean Standard), hot dip galvanized steel per KSD 8308/9521.</p><p><b>EMD/Bid Security:</b> Rs. 8.24 Lakhs, online payment only. EMD of all bidders except L-1 released after financial bid opening.</p><p><b>Other Conditions:</b> Defect Liability Period 3 years; Retro Reflection Sheeting warranty 10 years; Subcontracting permitted up to 25%; Rate Contract validity 3 years for Madhya Pradesh.</p>",
    Checklist: "1. Duly notarized Affidavit\n2. M.P. PWD Registration (active on bid submission due date)\n3. Proof of application for registration with MPPWD\n4. Duly filled Organization Details\n5. Copy of partnership deed (certified & notarized, if partnership firm)\n6. Articles of Association (AOA)\n7. Memorandum of Association (MOA)\n8. Registration certificate of the company\n9. Board Resolution and power of attorney\n10. MoU and JV agreement (if applicable)\n11. Power of attorney of JV partners (if applicable)\n12. Financial Experience: Table-1 (Similar Works)\n13. Experience certificates for Table-1\n14. Physical Qualifications: Table-3 (Similar items)\n15. Experience certificates for Table-3\n16. Existing commitments: Table-2\n17. Annual Turnover: Annexure-I (Format I-2)\n18. Chartered Accountant Certificate\n19. Audited Balance Sheet FY 2025-26\n20. Audited Balance Sheet FY 2024-25\n21. Audited Balance Sheet FY 2023-24\n22. Audited Balance Sheet FY 2022-23\n23. Audited Balance Sheet FY 2021-22\n24. List of Technical Personnel\n25. List of Key equipment/machines for quality control labs\n26. List of Key equipment/machines for construction works\n27. Documents under Special Eligibility Criteria\n28. Duly filled and signed Annexure J (Financial Bid)\n29. Duly filled Bill of Quantities (BOQ)"
};

export default class TenderPdfViewer extends LightningElement {

    @api recordId;

    @track tender         = null;
    @track isLoading      = true;
    @track isGenerating   = false;
    @track generatingLabel = '';
    @track hasError       = false;
    @track errorMessage   = '';
    @track uploadSuccess  = false;
    @track fileUrl        = '';

    _jsPdfReady = false;

    connectedCallback() {
        loadScript(this, JSPDF_LIB)
            .then(() => { this._jsPdfReady = true; })
            .catch(e => this._showError('Could not load PDF library: ' + e.message));
    }

    @wire(getTenderData, { tenderId: '$recordId' })
    wiredTender({ data, error }) {
        if (data) {
            this.tender = {
                name: data.name,
                tenderId:              RAW_JSON.Tender_Id,
                departmentName:        RAW_JSON.Department_Name,
                category:              RAW_JSON.Category,
                location:              RAW_JSON.Location,
                siteLocation:          RAW_JSON.Site_location,
                state:                 RAW_JSON.State,
                estimatedCost:         RAW_JSON.Estimated_Cost,
                emdValue:              RAW_JSON.EMD_Value,
                emdMode:               RAW_JSON.Emd_Mode_Type,
                documentFees:          RAW_JSON.Document_Fees,
                completionPeriod:      RAW_JSON.Completion_Period,
                performanceGuarantee:  RAW_JSON.Performance_Bank_Guarantee,
                preBidMeeting:         RAW_JSON.Pre_Bid_Meeting,
                mandatoryPreBid:       RAW_JSON.Mandatory_Pre_bid_Meeting,
                bidEndDate:            stripHtml(RAW_JSON.Bid_End_Date_Time),
                bidOpeningDate:        stripHtml(RAW_JSON.Bid_Opening_Date_Time),
                jointVenture:          RAW_JSON.Joint_Venture_OR_Consortium_OR_JV,
                emdInstrumentType:     RAW_JSON.Emd_Instrument_Type,
                products:              stripHtml(RAW_JSON.Products),
                eligibility:           stripHtml(RAW_JSON.Eligibility_Criteria),
                paymentTerms:          stripHtml(RAW_JSON.Payment_terms),
                penalty:               stripHtml(RAW_JSON.Levy_of_Penalty),
                defectLiability:       stripHtml(RAW_JSON.Defect_Liability_Period),
                affidavit:             stripHtml(RAW_JSON.Affidavit_notarized_documents),
                siteVisit:             RAW_JSON.Site_Visit_Requirement,
                checklist:             RAW_JSON.Checklist
            };
            this.isLoading = false;
        } else if (error) {
            this._showError(error.body?.message || 'Failed to load tender data.');
            this.isLoading = false;
        }
    }

    get keyFields() {
        if (!this.tender) return [];
        const t = this.tender;
        return [
            { label: 'Tender ID',            value: t.tenderId },
            { label: 'Department',           value: t.departmentName },
            { label: 'State',                value: t.state },
            { label: 'Category',             value: t.category },
            { label: 'Office Location',      value: t.location },
            { label: 'Site Location',        value: t.siteLocation },
            { label: 'Estimated Cost',       value: 'Rs. ' + t.estimatedCost },
            { label: 'EMD Value',            value: 'Rs. ' + t.emdValue },
            { label: 'EMD Mode',             value: t.emdMode },
            { label: 'EMD Instrument Type',  value: t.emdInstrumentType },
            { label: 'Document Fees',        value: 'Rs. ' + t.documentFees },
            { label: 'Completion Period',    value: t.completionPeriod },
            { label: 'Perf. Bank Guarantee', value: t.performanceGuarantee },
            { label: 'Pre-Bid Meeting',      value: t.preBidMeeting },
            { label: 'Mandatory Pre-Bid',    value: t.mandatoryPreBid },
            { label: 'Joint Venture',        value: t.jointVenture }
        ];
    }

    get isActionDisabled() {
        return this.isLoading || !this.tender || this.isGenerating;
    }

    async handleDownload() {
        if (!this._jsPdfReady) { this._showError('PDF library not loaded yet.'); return; }
        this.isGenerating = true;
        this.generatingLabel = 'Building PDF…';
        this.uploadSuccess = false;
        try {
            const doc = this._buildPdf();
            doc.save(`Tender_${this.tender.tenderId || this.recordId}.pdf`);
        } catch (e) {
            this._showError('PDF generation failed: ' + e.message);
        } finally {
            this.isGenerating = false;
        }
    }

    async handleSaveToFiles() {
        if (!this._jsPdfReady) { this._showError('PDF library not loaded yet.'); return; }
        this.isGenerating = true;
        this.generatingLabel = 'Generating PDF…';
        this.uploadSuccess = false;
        try {
            const doc = this._buildPdf();
            const dataUri = doc.output('datauristring');
            const base64 = dataUri.split(',')[1];
            const fileName = `Tender_${this.tender.tenderId || this.recordId}`;

            this.generatingLabel = 'Uploading to Files…';
            const contentDocId = await saveToFiles({
                tenderId: this.recordId,
                base64Data: base64,
                fileName: fileName
            });

            this.fileUrl = `/lightning/r/ContentDocument/${contentDocId}/view`;
            this.uploadSuccess = true;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success', message: 'PDF saved to Files on this record.', variant: 'success'
            }));
        } catch (e) {
            this._showError('Upload failed: ' + (e.body?.message || e.message));
        } finally {
            this.isGenerating = false;
        }
    }

    _buildPdf() {
        const { jsPDF } = window.jspdf;
        const doc = new jsPDF({ orientation: 'p', unit: 'mm', format: 'a4' });
        const t = this.tender;

        const MARGIN = 16, PW = 210, CW = PW - MARGIN * 2;
        const ACCENT = [26, 54, 96], LIGHT = [238, 243, 251], ALT = [245, 248, 253], BORDER = [200, 216, 238];
        let y = 16;

        const newPage = () => { doc.addPage(); y = 16; };
        const checkY = (needed) => { if (y + needed > 280) newPage(); };

        const sectionHeader = (title) => {
            checkY(10);
            doc.setFillColor(...ACCENT);
            doc.rect(MARGIN, y, CW, 8, 'F');
            doc.setFont('helvetica', 'bold');
            doc.setFontSize(9);
            doc.setTextColor(255, 255, 255);
            doc.text(title, MARGIN + 3, y + 5.5);
            y += 8;
        };

        const drawBorder = (x, fy, w, h) => {
            doc.setDrawColor(...BORDER);
            doc.setLineWidth(0.2);
            doc.rect(x, fy, w, h);
        };

        const fieldRow = (label, value, shade, rowH = 7) => {
            checkY(rowH);
            const lw = CW * 0.35, vw = CW * 0.65;
            doc.setFillColor(...LIGHT);
            doc.rect(MARGIN, y, lw, rowH, 'F');
            doc.setFillColor(...(shade ? ALT : [255, 255, 255]));
            doc.rect(MARGIN + lw, y, vw, rowH, 'F');
            drawBorder(MARGIN, y, CW, rowH);
            doc.setFont('helvetica', 'bold');
            doc.setFontSize(7.5);
            doc.setTextColor(80, 80, 80);
            doc.text(label, MARGIN + 2, y + rowH / 2 + 1);
            doc.setFont('helvetica', 'normal');
            doc.setFontSize(8);
            doc.setTextColor(20, 20, 20);
            const lines = doc.splitTextToSize(value || '—', vw - 4);
            if (lines.length > 1) {
                const tall = lines.length * 5;
                doc.setFillColor(...LIGHT);
                doc.rect(MARGIN, y, lw, tall, 'F');
                doc.setFillColor(...(shade ? ALT : [255, 255, 255]));
                doc.rect(MARGIN + lw, y, vw, tall, 'F');
                drawBorder(MARGIN, y, CW, tall);
                doc.setFont('helvetica', 'bold');
                doc.setFontSize(7.5);
                doc.setTextColor(80, 80, 80);
                doc.text(label, MARGIN + 2, y + 4);
                doc.setFont('helvetica', 'normal');
                doc.setFontSize(8);
                doc.setTextColor(20, 20, 20);
                doc.text(lines, MARGIN + lw + 2, y + 4);
                y += tall;
            } else {
                doc.text(lines[0] || '—', MARGIN + lw + 2, y + rowH / 2 + 1);
                y += rowH;
            }
        };

        const richBlock = (text) => {
            const plain = (text || '—').trim();
            doc.setFont('helvetica', 'normal');
            doc.setFontSize(8);
            doc.setTextColor(30, 30, 30);
            const paragraphs = plain.split('\n');
            paragraphs.forEach(para => {
                if (!para.trim()) { y += 2; return; }
                const lines = doc.splitTextToSize(para, CW - 4);
                lines.forEach(line => {
                    checkY(5);
                    doc.text(line, MARGIN + 2, y + 4);
                    y += 5;
                });
            });
            y += 2;
        };

        // Header
        doc.setFillColor(...ACCENT);
        doc.rect(0, 0, 210, 28, 'F');
        doc.setFont('helvetica', 'bold');
        doc.setFontSize(13);
        doc.setTextColor(255, 255, 255);
        doc.text(t.departmentName || 'TENDER DOCUMENT', 105, 11, { align: 'center' });
        doc.setFontSize(8);
        doc.setFont('helvetica', 'normal');
        doc.text(`Tender ID: ${t.tenderId || ''}   |   ${t.state || ''}`, 105, 19, { align: 'center' });
        doc.setFontSize(8.5);
        doc.setFont('helvetica', 'italic');
        const catLines = doc.splitTextToSize(t.category || '', 170);
        catLines.forEach((l, i) => doc.text(l, 105, 24 + i * 4.5, { align: 'center' }));
        y = 34;

        sectionHeader('KEY TENDER INFORMATION');
        this.keyFields.forEach((f, i) => fieldRow(f.label, f.value, i % 2 === 1));
        y += 3;

        sectionHeader('BID DATES');
        fieldRow('Bid End Date & Time', t.bidEndDate, false);
        fieldRow('Bid Opening Date & Time', t.bidOpeningDate, true);
        y += 3;

        sectionHeader('PRODUCTS / SCOPE OF WORK'); richBlock(t.products); y += 2;
        sectionHeader('ELIGIBILITY CRITERIA');     richBlock(t.eligibility); y += 2;
        sectionHeader('PAYMENT TERMS');            richBlock(t.paymentTerms); y += 2;
        sectionHeader('LEVY OF PENALTY');          richBlock(t.penalty); y += 2;
        sectionHeader('DEFECT LIABILITY PERIOD');  richBlock(t.defectLiability); y += 2;
        sectionHeader('AFFIDAVIT / NOTARIZED DOCUMENTS'); richBlock(t.affidavit); y += 2;
        sectionHeader('SITE VISIT REQUIREMENT');   richBlock(t.siteVisit); y += 2;
        sectionHeader('CHECKLIST');                richBlock(t.checklist);

        const totalPages = doc.getNumberOfPages();
        for (let p = 1; p <= totalPages; p++) {
            doc.setPage(p);
            doc.setFont('helvetica', 'normal');
            doc.setFontSize(7);
            doc.setTextColor(150, 150, 150);
            doc.text(`Generated from Salesforce | Tender ID: ${t.tenderId || ''} | Page ${p} of ${totalPages}`, 105, 292, { align: 'center' });
        }

        return doc;
    }

    _showError(msg) {
        this.hasError = true;
        this.errorMessage = msg;
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
    }
}