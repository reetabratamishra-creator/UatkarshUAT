public with sharing class TenderAnalyzerController {

    public static void runAnalysis() {

        // TEMPORARILY DISABLED
        System.debug('========================================');
        System.debug('=== TenderAnalyzerController DISABLED ===');
        System.debug('========================================');

        return;

        /*
         * Existing code below remains untouched
         */

        // ... all your current code ...
    }

    @future
    public static void setProcessing(String recordId) {
        update new OCR_DOC__c(
            Id = recordId,
            AI_Status__c = 'Processing'
        );
    }
}