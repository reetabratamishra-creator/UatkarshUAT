// ============================================================
// CLASS 11 — Job4_SaveResultsQueueable_Batch.cls
// ─────────────────────────────────────────────────────────────
// Job 4 of 4 — FINAL job in the Queueable chain
// Responsibilities:
//   - Call OCRDocResultSaver.saveResults() — DML only
//   - No callouts here — pure Salesforce DML
//   - Marks record as Completed or Failed
// ─────────────────────────────────────────────────────────────
// Uses:
//   OCRDocResultSaver.saveResults()
// ============================================================
public with sharing class Job4_SaveResultsQueueable_Batch implements Queueable {

    private String  recordId;
    private String  categoryRawResponse;
    private String  pqcRawResponse;
    private Integer uploadedFileCount;

    // Constructor
    public Job4_SaveResultsQueueable_Batch(
        String  recordId,
        String  categoryRawResponse,
        String  pqcRawResponse,
        Integer uploadedFileCount
    ) {
        this.recordId            = recordId;
        this.categoryRawResponse = categoryRawResponse;
        this.pqcRawResponse      = pqcRawResponse;
        this.uploadedFileCount   = uploadedFileCount;
    }

    public void execute(QueueableContext ctx) {
        System.debug('===== Job4_SaveResultsQueueable START | Record: ' + recordId + ' =====');

        try {
            // ─────────────────────────────────────────────────
            // Save both results to OCR_DOC__c
            // OCRDocResultSaver handles all field mapping
            // ─────────────────────────────────────────────────
            OCRDocResultSaver.saveResults(
                recordId,
                categoryRawResponse,
                pqcRawResponse,
                uploadedFileCount
            );

            System.debug('===== Job4_SaveResultsQueueable END — Record saved successfully =====');

        } catch (Exception e) {
            System.debug('ERROR in Job4: ' + e.getMessage());
            OCRDocResultSaver.markFailed(recordId, 'Job4 Error: ' + e.getMessage());
        }
    }
}