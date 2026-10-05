// ============================================================
// PQCViewerController.cls
// ─────────────────────────────────────────────────────────────
// Powers the pqcViewer LWC component.
//   - getPQCData()         → parses PQCDetails1__c + PQCDetails2__c
//                             JSON into a clean wrapper for the UI
//   - generateAndAttachPDF → renders the PQCReportPDF Visualforce
//                             page as PDF and attaches it to the
//                             OCR_DOC__c record as a ContentVersion
// ============================================================
public with sharing class PQCViewerController {
    
    // ── Wrapper for a single PQC line item ─────────────────────
    public class PQCItem {
        @AuraEnabled public String pqcLabel;
        @AuraEnabled public String findings;
        @AuraEnabled public String pageReference;
        @AuraEnabled public String status;
        @AuraEnabled public String statusVariant; // success / error / warning
    }
    
    // ── Wrapper for the full result returned to the LWC ────────
    public class PQCResult {
        @AuraEnabled public String  recordName;
        @AuraEnabled public String  aiStatus;
        @AuraEnabled public String  matchedDepartment;
        @AuraEnabled public Decimal confidenceScore;
        @AuraEnabled public List<PQCItem> items;
        @AuraEnabled public String  errorMessage;
    }
    
    // ─────────────────────────────────────────────────────────
    // Called by the LWC via @wire — returns parsed PQC data
    // ─────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static PQCResult getPQCData(Id recordId) {
        PQCResult result = new PQCResult();
        result.items = new List<PQCItem>();
        
        OCR_DOC__c doc = [
            SELECT Id, Name, AI_Status__c, Matched_Department__c,
                   Confidence_Score__c, PQCDetails1__c, PQCDetails2__c
            FROM   OCR_DOC__c
            WHERE  Id = :recordId
            LIMIT  1
        ];
        
        result.recordName        = doc.Name;
        result.aiStatus           = doc.AI_Status__c;
        result.matchedDepartment  = doc.Matched_Department__c;
        result.confidenceScore    = doc.Confidence_Score__c;
        
        String fullPqcJson =
            (doc.PQCDetails1__c == null ? '' : doc.PQCDetails1__c) +
            (doc.PQCDetails2__c == null ? '' : doc.PQCDetails2__c);
        
        fullPqcJson = fullPqcJson.trim();
        
        // Handle HTML encoded JSON
        fullPqcJson = fullPqcJson
            .replace('&quot;', '"')
            .replace('&amp;', '&')
            .replace('&lt;', '<')
            .replace('&gt;', '>');
        
        System.debug('PQC JSON: ' + fullPqcJson);
        
        Map<String, Object> parsed =
            (Map<String, Object>)JSON.deserializeUntyped(fullPqcJson);
        if (String.isBlank(fullPqcJson)) {
            result.errorMessage = 'No PQC data available for this record yet.';
            return result;
        }
        
        try {
            // Map<String, Object> parsed =
            //     (Map<String, Object>) JSON.deserializeUntyped(fullPqcJson);
            
            if (parsed.containsKey('error')) {
                result.errorMessage = String.valueOf(parsed.get('error'));
                return result;
            }
            
            List<Object> rawItems = (List<Object>) parsed.get('pqcAnalysis');
            if (rawItems != null) {
                for (Object o : rawItems) {
                    Map<String, Object> m = (Map<String, Object>) o;
                    PQCItem item        = new PQCItem();
                    item.pqcLabel       = (String) m.get('pqcLabel');
                    item.findings       = (String) m.get('findings');
                    item.pageReference  = (String) m.get('pageReference');
                    item.status         = (String) m.get('status');
                    item.statusVariant  = mapStatusToVariant(item.status);
                    result.items.add(item);
                }
            }
        } catch (Exception e) {
            result.errorMessage = 'Could not parse PQC data: ' + e.getMessage();
        }
        
        return result;
    }
    
    private static String mapStatusToVariant(String status) {
        if (String.isBlank(status)) return 'inverse';
        String s = status.toLowerCase();
        if (s == 'found')     return 'success';
        if (s == 'not found') return 'error';
        if (s == 'partial')   return 'warning';
        return 'inverse';
    }
    
    // ─────────────────────────────────────────────────────────
    // Called by the LWC's "Save as Attachment" button.
    // Renders PQCReportPDF.page as PDF and attaches it to the
    // OCR_DOC__c record via ContentVersion + ContentDocumentLink.
    // ─────────────────────────────────────────────────────────
    @AuraEnabled
    public static String generateAndAttachPDF(Id recordId) {
        try {
            PageReference pdfPage = Page.PQCReportPDF;
            pdfPage.getParameters().put('id', recordId);
            Blob pdfBlob = pdfPage.getContent();
            
            OCR_DOC__c doc = [SELECT Name FROM OCR_DOC__c WHERE Id = :recordId LIMIT 1];
            
            ContentVersion cv = new ContentVersion();
            cv.Title           = 'PQC_Report_' + doc.Name;
            cv.PathOnClient    = 'PQC_Report_' + doc.Name + '.pdf';
            cv.VersionData     = pdfBlob;
            cv.ContentLocation = 'S';
            insert cv;
            
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
            
            ContentDocumentLink link = new ContentDocumentLink();
            link.ContentDocumentId = cv.ContentDocumentId;
            link.LinkedEntityId    = recordId;
            link.ShareType         = 'V';
            link.Visibility        = 'AllUsers';
            insert link;
            
            return 'success';
        } catch (Exception e) {
            throw new AuraHandledException('Failed to generate PDF: ' + e.getMessage());
        }
    }
}