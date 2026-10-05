public with sharing class OCRDocController {

    @AuraEnabled
    public static Id initUpload(Integer fileCount) {
        OCR_DOC__c doc = new OCR_DOC__c(
            AI_Status__c = 'Uploading',
            Uploaded_File_Count__c = fileCount
        );
        insert doc;
        return doc.Id;
    }

    @AuraEnabled
    public static Id uploadChunk(
        Id docRecordId,
        String fileName,
        String base64Chunk,
        Integer chunkIndex,
        Integer totalChunks,
        Id contentVersionId
    ) {
        if (chunkIndex == 0) {
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = EncodingUtil.base64Decode(base64Chunk);
            cv.IsMajorVersion = false;
            insert cv;

            ContentVersion inserted = [
                SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
            ];
            insert new ContentDocumentLink(
                ContentDocumentId = inserted.ContentDocumentId,
                LinkedEntityId = docRecordId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );

            return cv.Id;

        } else {
            ContentVersion prev = [
                SELECT ContentDocumentId, VersionData
                FROM ContentVersion
                WHERE Id = :contentVersionId
            ];

            Blob combined = mergeBlobs(prev.VersionData, EncodingUtil.base64Decode(base64Chunk));

            ContentVersion newVersion = new ContentVersion();
            newVersion.ContentDocumentId = prev.ContentDocumentId;
            newVersion.Title = prev.Title; 
            newVersion.PathOnClient = prev.Title;
            newVersion.VersionData = combined;
            newVersion.IsMajorVersion = false;
            insert newVersion;

            return newVersion.Id;
        }
    }

    @AuraEnabled
    public static void finalizeUpload(Id docRecordId) {
        update new OCR_DOC__c(
            Id = docRecordId,
            AI_Status__c = 'Pending'
        );
        System.enqueueJob(new TenderAnalysisQueueable(docRecordId));
    }

    // Blob merge helper
    private static Blob mergeBlobs(Blob a, Blob b) {
        String combinedBase64 =
            EncodingUtil.base64Encode(a) +
            EncodingUtil.base64Encode(b);
        return EncodingUtil.base64Decode(combinedBase64);
    }
}