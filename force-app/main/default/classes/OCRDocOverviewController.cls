public with sharing class OCRDocOverviewController {
    
    public class DashboardWrapper {
        @AuraEnabled public Integer totalDocs;
        @AuraEnabled public Integer completedDocs;
        @AuraEnabled public Integer processingDocs;
        @AuraEnabled public Integer failedDocs;
        @AuraEnabled public List<OCR_DOC__c> recentDocs;
    }
    
    @AuraEnabled(cacheable=true)
    public static DashboardWrapper getDashboardData() {
        
        DashboardWrapper data = new DashboardWrapper();
        
        data.totalDocs = [
            SELECT COUNT()
            FROM OCR_DOC__c
        ];
        
        data.completedDocs = [
            SELECT COUNT()
            FROM OCR_DOC__c
            WHERE AI_Status__c = 'Completed'
        ];
        
        data.processingDocs = [
            SELECT COUNT()
            FROM OCR_DOC__c
            WHERE AI_Status__c = 'Processing'
        ];
        
        data.failedDocs = [
            SELECT COUNT()
            FROM OCR_DOC__c
            WHERE AI_Status__c = 'Failed'
        ];
        
        data.recentDocs = [
            SELECT Id,
                   Name,
                   AI_Status__c,
                   Confidence_Score__c,
                   CreatedDate
            FROM OCR_DOC__c
            ORDER BY CreatedDate DESC
        ];
        
        return data;
    }
    
    @AuraEnabled
    public static Id createOCRDocument(List<Id> contentDocumentIds) {
        OCR_DOC__c ocrDoc = new OCR_DOC__c();
        ocrDoc.AI_Status__c = 'Pending';
        insert ocrDoc;
        
        if (contentDocumentIds != null && !contentDocumentIds.isEmpty()) {
            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            for (Id docId : contentDocumentIds) {
                links.add(new ContentDocumentLink(
                    ContentDocumentId = docId,
                LinkedEntityId = ocrDoc.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
                    ));
            }
            insert links;
        }
        
        return ocrDoc.Id;
    }
}