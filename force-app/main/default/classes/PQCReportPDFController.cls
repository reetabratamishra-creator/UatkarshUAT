// public with sharing class PQCReportPDFController {

//     public class PQCRow {
//         public String pqcLabel      { get; set; }
//         public String findings      { get; set; }
//         public String pageReference { get; set; }
//         public String status        { get; set; }
//         public String statusClass   { get; set; }
//         public String rowClass      { get; set; }
//     }

//     // Grouped lists for the three sections
//     public List<PQCRow> generalItems   { get; set; }
//     public List<PQCRow> technicalItems { get; set; }
//     public List<PQCRow> financialItems { get; set; }

//     public Boolean      hasError     { get; set; }
//     public String       errorMessage { get; set; }
//     public OCR_DOC__c   record       { get; set; }

//     // Which pqcLabel belongs to which section
//     private static final Set<String> GENERAL_LABELS = new Set<String>{
//         'What is the Categories of Product',
//         'Scope of the Tender',
//         'Which organisation published the Tender',
//         'Delivery Location',
//         'Estimated Bid Value'
//     };

//     private static final Set<String> FINANCIAL_LABELS = new Set<String>{
//         'Average Annual Turn over',
//         'Net Worth',
//         'Turn Over Certificate',
//         'Audited Balance Sheet',
//         'EMD Requirement',
//         'EPBG Requirement',
//         'Payment Terms',
//         'Input Tax Credit (ITC)'
//     };

//     public PQCReportPDFController(ApexPages.StandardController stdController) {
//         generalItems   = new List<PQCRow>();
//         technicalItems = new List<PQCRow>();
//         financialItems = new List<PQCRow>();
//         hasError       = false;

//         Id recordId = (Id) stdController.getId();

//         record = [
//             SELECT Id, Name, AI_Status__c, Matched_Department__c,
//                    PQCDetails1__c, PQCDetails2__c
//             FROM   OCR_DOC__c
//             WHERE  Id = :recordId
//             LIMIT  1
//         ];

//         String fullJson =
//             (record.PQCDetails1__c == null ? '' : record.PQCDetails1__c) +
//             (record.PQCDetails2__c == null ? '' : record.PQCDetails2__c);

//         if (String.isBlank(fullJson)) {
//             hasError     = true;
//             errorMessage = 'No PQC data available for this record.';
//             return;
//         }

//         try {
//             // Fix unescaped HTML entities before JSON parse
//             fullJson = fullJson.replace('&amp;',  '&')
//                                .replace('&lt;',   '<')
//                                .replace('&gt;',   '>')
//                                .replace('&quot;', '"')
//                                .replace('&#39;',  '\'');

//             Map<String, Object> parsed =
//                 (Map<String, Object>) JSON.deserializeUntyped(fullJson);

//             if (parsed.containsKey('error')) {
//                 hasError     = true;
//                 errorMessage = escapeForPdf(String.valueOf(parsed.get('error')));
//                 return;
//             }

//             List<Object> rawItems = (List<Object>) parsed.get('pqcAnalysis');
//             if (rawItems == null || rawItems.isEmpty()) {
//                 hasError     = true;
//                 errorMessage = 'No PQC items found in the data.';
//                 return;
//             }

//             Integer genIdx  = 0;
//             Integer techIdx = 0;
//             Integer finIdx  = 0;

//             for (Object o : rawItems) {
//                 Map<String, Object> m = (Map<String, Object>) o;
//                 PQCRow row        = new PQCRow();
//                 row.pqcLabel      = escapeForPdf((String) m.get('pqcLabel'));
//                 row.findings      = escapeForPdf((String) m.get('findings'));
//                 row.pageReference = escapeForPdf((String) m.get('pageReference'));
//                 row.status        = (String) m.get('status');
//                 row.statusClass   = 'status-' + mapStatusClass(row.status);

//                 String rawLabel = (String) m.get('pqcLabel');

//                 if (GENERAL_LABELS.contains(rawLabel)) {
//                     row.rowClass = Math.mod(genIdx, 2) == 0 ? 'row-even' : 'row-odd';
//                     generalItems.add(row);
//                     genIdx++;
//                 } else if (FINANCIAL_LABELS.contains(rawLabel)) {
//                     row.rowClass = Math.mod(finIdx, 2) == 0 ? 'row-even' : 'row-odd';
//                     financialItems.add(row);
//                     finIdx++;
//                 } else {
//                     row.rowClass = Math.mod(techIdx, 2) == 0 ? 'row-even' : 'row-odd';
//                     technicalItems.add(row);
//                     techIdx++;
//                 }
//             }

//         } catch (Exception e) {
//             hasError     = true;
//             errorMessage = escapeForPdf('Could not parse PQC data: ' + e.getMessage());
//         }
//     }

//     private String escapeForPdf(String val) {
//         if (String.isBlank(val)) return '';
//         val = val.replace('&',  '&amp;');
//         val = val.replace('<',  '&lt;');
//         val = val.replace('>',  '&gt;');
//         val = val.replace('"',  '&quot;');
//         val = val.replace('\'', '&#39;');
//         return val;
//     }

//     private String mapStatusClass(String status) {
//         if (String.isBlank(status)) return 'partial';
//         String s = status.toLowerCase();
//         if (s == 'found')     return 'found';
//         if (s == 'not found') return 'notfound';
//         return 'partial';
//     }
// }

public with sharing class PQCReportPDFController {

    public class PQCRow {
        public String pqcLabel      { get; set; }
        public String findings      { get; set; }
        public String pageReference { get; set; }
        public String status        { get; set; }
        public String statusClass   { get; set; }
        public String rowClass      { get; set; }
    }

    public List<PQCRow> generalItems   { get; set; }
    public List<PQCRow> technicalItems { get; set; }
    public List<PQCRow> financialItems { get; set; }

    public Boolean      hasError     { get; set; }
    public String       errorMessage { get; set; }
    public OCR_DOC__c   record       { get; set; }

    public PQCReportPDFController(ApexPages.StandardController stdController) {
        generalItems   = new List<PQCRow>();
        technicalItems = new List<PQCRow>();
        financialItems = new List<PQCRow>();
        hasError       = false;

        Id recordId = (Id) stdController.getId();

        record = [
            SELECT Id, Name, AI_Status__c, Matched_Department__c,
                   PQCDetails1__c, PQCDetails2__c
            FROM   OCR_DOC__c
            WHERE  Id = :recordId
            LIMIT  1
        ];

        // ── Load section mapping from Custom Metadata ──────────
        // Map: MasterLabel → Domain__c  (e.g. 'Delivery Location' → 'General')
        Map<String, String> labelToDomain = new Map<String, String>();
        for (PQC_Details__mdt mdt : [
            SELECT MasterLabel, Domain__c
            FROM   PQC_Details__mdt
        ]) {
            if (String.isNotBlank(mdt.MasterLabel) && String.isNotBlank(mdt.Domain__c)) {
                labelToDomain.put(mdt.MasterLabel.trim(), mdt.Domain__c.trim().toLowerCase());
            }
        }

        // ── Load and parse JSON ────────────────────────────────
        String fullJson =
            (record.PQCDetails1__c == null ? '' : record.PQCDetails1__c) +
            (record.PQCDetails2__c == null ? '' : record.PQCDetails2__c);

        if (String.isBlank(fullJson)) {
            hasError     = true;
            errorMessage = 'No PQC data available for this record.';
            return;
        }

        try {
            // Fix unescaped HTML entities before JSON parse
            fullJson = fullJson.replace('&amp;',  '&')
                               .replace('&lt;',   '<')
                               .replace('&gt;',   '>')
                               .replace('&quot;', '"')
                               .replace('&#39;',  '\'');

            Map<String, Object> parsed =
                (Map<String, Object>) JSON.deserializeUntyped(fullJson);

            if (parsed.containsKey('error')) {
                hasError     = true;
                errorMessage = escapeForPdf(String.valueOf(parsed.get('error')));
                return;
            }

            List<Object> rawItems = (List<Object>) parsed.get('pqcAnalysis');
            if (rawItems == null || rawItems.isEmpty()) {
                hasError     = true;
                errorMessage = 'No PQC items found in the data.';
                return;
            }

            Integer genIdx  = 0;
            Integer techIdx = 0;
            Integer finIdx  = 0;

            for (Object o : rawItems) {
                Map<String, Object> m = (Map<String, Object>) o;

                String rawLabel = (String) m.get('pqcLabel');

                PQCRow row        = new PQCRow();
                row.pqcLabel      = escapeForPdf(rawLabel);
                row.findings      = escapeForPdf((String) m.get('findings'));
                row.pageReference = escapeForPdf((String) m.get('pageReference'));
                row.status        = (String) m.get('status');
                row.statusClass   = 'status-' + mapStatusClass(row.status);

                // Look up domain from metadata; default to 'technical' if not found
                String domain = 'technical';
                if (String.isNotBlank(rawLabel) && labelToDomain.containsKey(rawLabel.trim())) {
                    domain = labelToDomain.get(rawLabel.trim());
                }

                if (domain == 'general') {
                    row.rowClass = Math.mod(genIdx, 2) == 0 ? 'row-even' : 'row-odd';
                    generalItems.add(row);
                    genIdx++;
                } else if (domain == 'financial') {
                    row.rowClass = Math.mod(finIdx, 2) == 0 ? 'row-even' : 'row-odd';
                    financialItems.add(row);
                    finIdx++;
                } else {
                    row.rowClass = Math.mod(techIdx, 2) == 0 ? 'row-even' : 'row-odd';
                    technicalItems.add(row);
                    techIdx++;
                }
            }

        } catch (Exception e) {
            hasError     = true;
            errorMessage = escapeForPdf('Could not parse PQC data: ' + e.getMessage());
        }
    }

    private String escapeForPdf(String val) {
        if (String.isBlank(val)) return '';
        val = val.replace('&',  '&amp;');
        val = val.replace('<',  '&lt;');
        val = val.replace('>',  '&gt;');
        val = val.replace('"',  '&quot;');
        val = val.replace('\'', '&#39;');
        return val;
    }

    private String mapStatusClass(String status) {
        if (String.isBlank(status)) return 'partial';
        String s = status.toLowerCase();
        if (s == 'found')     return 'found';
        if (s == 'not found') return 'notfound';
        return 'partial';
    }
}