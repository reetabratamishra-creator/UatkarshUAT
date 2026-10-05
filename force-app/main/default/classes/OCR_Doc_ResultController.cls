public class OCR_Doc_ResultController {
    @AuraEnabled(cacheable=true)
    public static List<OCR_Doc_Result__c> getResults(Id ocrDocId) {
        return [
            SELECT File_Name__c,
                   Matched_Department__c,
                   Matched_Keywords__c,
                   Confidence_Score__c,
                   Is_Relevant__c,
                   Is_Excluded__c,
                   Status__c
            FROM OCR_Doc_Result__c
            WHERE OCR_Doc__c = :ocrDocId
            ORDER BY Confidence_Score__c DESC
        ];
    }
}