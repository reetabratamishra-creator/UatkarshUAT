// ============================================================
// CLASS — Job4_SaveResultsQueueable.cls
// ─────────────────────────────────────────────────────────────
// PURPOSE:
//   Final job in the Tender Analysis async chain.
//   Pure DML only — no callouts. Receives both Gemini results
//   from Job3 and saves them to the OCR_DOC__c record via
//   OCRDocResultSaver.saveResults().
//

// STEPS:
//   1. Validates all inputs are not null/blank
//   2. Calls OCRDocResultSaver.saveResults() for full DML save
//   3. Marks record as Completed or Failed based on result
//

//
// DEPENDS ON:
//   OCRDocResultSaver — full result save + failure logging
// ============================================================
public with sharing class Job4_SaveResultsQueueable implements Queueable {

    private String  recordId;
    private String  categoryRawResponse;
    private String  pqcRawResponse;
    private Integer uploadedFileCount;

    public Job4_SaveResultsQueueable(
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

        // ─────────────────────────────────────────────────────
        // GUARD: recordId must be valid before any DML
        // FIX: blank recordId would cause DML error deep inside
        //      saveResults() with confusing error message
        // ─────────────────────────────────────────────────────
        if (String.isBlank(recordId)) {
            System.debug('ERROR: recordId is null or blank. Cannot save results. Aborting Job4.');
            return;
        }

        // ─────────────────────────────────────────────────────
        // GUARD: categoryRawResponse must not be null/blank
        // FIX: saveResults() calls JSON.deserializeUntyped()
        //      on this — null input causes immediate NPE crash
        // ─────────────────────────────────────────────────────
        if (String.isBlank(categoryRawResponse)) {
            System.debug('ERROR: categoryRawResponse is null or blank.');
            OCRDocResultSaver.markFailed(recordId, 'Job4: categoryRawResponse is null or blank.');
            return;
        }

        // ─────────────────────────────────────────────────────
        // GUARD: pqcRawResponse must not be null/blank
        // FIX: default to empty PQC JSON instead of crashing
        //      PQC is non-critical — category result must save
        // ─────────────────────────────────────────────────────
        if (String.isBlank(pqcRawResponse)) {
            System.debug('WARNING: pqcRawResponse is null or blank. Defaulting to empty PQC result.');
            pqcRawResponse = '{"pqcAnalysis":[]}';
        }

        // ─────────────────────────────────────────────────────
        // GUARD: uploadedFileCount null safety
        // FIX: null Integer saves null to field silently
        // ─────────────────────────────────────────────────────
        if (uploadedFileCount == null) {
            System.debug('WARNING: uploadedFileCount is null. Defaulting to 0.');
            uploadedFileCount = 0;
        }

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
            System.debug('ERROR in Job4: ' + e.getMessage() + ' | Line: ' + e.getLineNumber());

            // ─────────────────────────────────────────────────
            // FIX: markFailed wrapped in its own try-catch
            //      if recordId is somehow bad, this DML also
            //      throws — without this it is swallowed silently
            // ─────────────────────────────────────────────────
            try {
                OCRDocResultSaver.markFailed(recordId, 'Job4 Error: ' + e.getMessage());
            } catch (Exception exc) {
                System.debug('ERROR: markFailed also failed in Job4: ' + exc.getMessage());
            }
        }
    }
}