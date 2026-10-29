public with sharing class RecordFilesListController {

    public class FileWrapper {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public Integer contentSize;
        @AuraEnabled public Datetime lastModified;
    }

    public class FileResult {
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public List<FileWrapper> files;
    }

    @AuraEnabled(cacheable=true)
    public static FileResult getFiles(Id recordId, Integer maxRows) {
        Integer lim = (maxRows == null || maxRows < 1) ? 6 : Math.min(maxRows, 200);

        FileResult result = new FileResult();
        result.files = new List<FileWrapper>();
        result.totalCount = [
            SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :recordId
        ];

        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileExtension,
                   ContentDocument.ContentSize,
                   ContentDocument.LastModifiedDate
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            ORDER BY ContentDocument.LastModifiedDate DESC
            LIMIT :lim
        ]) {
            FileWrapper f = new FileWrapper();
            f.contentDocumentId = cdl.ContentDocumentId;
            f.title = cdl.ContentDocument.Title;
            f.fileExtension = cdl.ContentDocument.FileExtension;
            f.contentSize = cdl.ContentDocument.ContentSize;
            f.lastModified = cdl.ContentDocument.LastModifiedDate;
            result.files.add(f);
        }
        return result;
    }
}