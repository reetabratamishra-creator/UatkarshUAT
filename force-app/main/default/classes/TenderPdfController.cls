public with sharing class TenderPdfController {

    @AuraEnabled(cacheable=true)
    public static TenderWrapper getTenderData(Id tenderId) {
        Tender__c t = [
            SELECT Id, Name
            FROM Tender__c
            WHERE Id = :tenderId
            WITH USER_MODE
            LIMIT 1
        ];
        return new TenderWrapper(t);
    }

    @AuraEnabled
    public static String saveToFiles(Id tenderId, String base64Data, String fileName) {
        try {
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName + '.pdf';
            cv.VersionData = EncodingUtil.base64Decode(base64Data);
            cv.FirstPublishLocationId = tenderId;
            cv.IsMajorVersion = true;
            insert cv;

            ContentVersion inserted = [
                SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
            ];
            return inserted.ContentDocumentId;

        } catch (Exception e) {
            throw new AuraHandledException('File upload failed: ' + e.getMessage());
        }
    }

    public class TenderWrapper {
        @AuraEnabled public String recordId;
        @AuraEnabled public String name;

        public TenderWrapper(Tender__c t) {
            this.recordId = t.Id;
            this.name     = t.Name;
        }
    }
}