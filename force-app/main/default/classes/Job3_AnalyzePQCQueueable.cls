// ============================================================
// CLASS — Job3_AnalyzePQCQueueable.cls
// ─────────────────────────────────────────────────────────────
// PURPOSE:
//   Third job in the Tender Analysis async chain.
//   Loads PQC checklist from custom metadata, builds the PQC
//   prompt, calls Gemini for PQC analysis by reusing the same
//   file URIs from Job1 (no re-upload needed), then chains
//   to Job4 with both category and PQC results.
//
// TRIGGER POINT:
//   Chained automatically from Job2_AnalyzeCategoryQueueable
//   after category analysis is successfully completed.
//

// STEPS:
//   1. Validates fileUris and fileExtensions are not empty
//   2. Loads all records from PQCs__mdt via PQCMetadataService
//   3. Builds PQC prompt from loaded records
//   4. Calls Gemini analyzePQC() reusing same file URIs
//   5. Validates Gemini response is not blank or error
//   6. Chains to Job4_SaveResultsQueueable with both results
//

// ============================================================
public with sharing class Job3_AnalyzePQCQueueable implements Queueable, Database.AllowsCallouts {

    private String       recordId;
    private List<String> fileUris;
    private List<String> fileExtensions;
    private String       combinedFileNames;
    private String       categoryRawResponse;

    public Job3_AnalyzePQCQueueable(
        String       recordId,
        List<String> fileUris,
        List<String> fileExtensions,
        String       combinedFileNames,
        String       categoryRawResponse
    ) {
        this.recordId            = recordId;
        this.fileUris            = fileUris;
        this.fileExtensions      = fileExtensions;
        this.combinedFileNames   = combinedFileNames;
        this.categoryRawResponse = categoryRawResponse;
    }

    public void execute(QueueableContext ctx) {
        System.debug('===== Job3_AnalyzePQCQueueable START | Record: ' + recordId + ' =====');

        // ─────────────────────────────────────────────────────
        // GUARD: validate inputs passed from Job2
        // FIX: empty fileUris/fileExtensions caught early
        // ─────────────────────────────────────────────────────
        if (fileUris == null || fileUris.isEmpty()) {
            System.debug('ERROR: fileUris is null or empty. Aborting Job3.');
            OCRDocResultSaver.markFailed(recordId, 'Job3 received empty fileUris from Job2.');
            return;
        }
        if (fileExtensions == null || fileExtensions.isEmpty()) {
            System.debug('ERROR: fileExtensions is null or empty. Aborting Job3.');
            OCRDocResultSaver.markFailed(recordId, 'Job3 received empty fileExtensions from Job2.');
            return;
        }

        try {
            // ─────────────────────────────────────────────────
            // STEP 1: Load PQC metadata
            // ─────────────────────────────────────────────────
            List<PQCMetadataService.PQCConfig> pqcList =
                PQCMetadataService.getAllPQCs();

            String pqcRawResponse = '{"pqcAnalysis":[]}';

            if (pqcList.isEmpty()) {
                System.debug('WARNING: No PQC records found. Skipping PQC analysis.');

            } else {
                // ─────────────────────────────────────────────
                // STEP 2: Build PQC prompt
                // ─────────────────────────────────────────────
                String pqcPrompt = PQCMetadataService.buildPQCPrompt(pqcList);

                // FIX: blank prompt guard — prevents garbage Gemini result
                if (String.isBlank(pqcPrompt)) {
                    System.debug('WARNING: PQC prompt is blank. Skipping PQC analysis.');
                } else {
                    // ─────────────────────────────────────────
                    // STEP 3: Call Gemini — PQC analysis
                    // Reuses same fileUris — no re-upload needed
                    // ─────────────────────────────────────────
                    pqcRawResponse = GeminiService.analyzePQC(
                        fileUris,
                        fileExtensions,
                        combinedFileNames,
                        pqcPrompt
                    );

                    // FIX: null/blank response guard
                    if (String.isBlank(pqcRawResponse)) {
                        System.debug('WARNING: PQC analysis returned null or blank. Using empty result.');
                        pqcRawResponse = '{"pqcAnalysis":[]}';
                    } else {
                        System.debug('PQC response received. Length: ' + pqcRawResponse.length());

                        // FIX: error JSON guard — log warning but don't fail
                        // PQC is non-critical — category result is still saved
                        if (pqcRawResponse.contains('"error"')) {
                            System.debug('WARNING: Gemini returned error in PQC response: '
                                + pqcRawResponse.left(500));
                            pqcRawResponse = '{"pqcAnalysis":[],"warning":"PQC analysis failed: '
                                + pqcRawResponse.left(200).replace('"', '\\"') + '"}';
                        }
                    }
                }
            }

            // ─────────────────────────────────────────────────
            // STEP 4: Chain to Job4 — pass both results forward
            // FIX: enqueueJob wrapped in try-catch
            // FIX: fileUris.size() guarded — null check done above
            // ─────────────────────────────────────────────────
            try {
                System.enqueueJob(new Job4_SaveResultsQueueable(
                    recordId,
                    categoryRawResponse,
                    pqcRawResponse,
                    fileUris.size()
                ));
                System.debug('===== Job3_AnalyzePQCQueueable END — Chained to Job4 =====');
            } catch (Exception e) {
                System.debug('ERROR: Failed to enqueue Job4 — ' + e.getMessage());
                OCRDocResultSaver.markFailed(recordId, 'Job4 enqueue failed: ' + e.getMessage());
            }

        } catch (Exception e) {
            System.debug('ERROR in Job3: ' + e.getMessage() + ' | Line: ' + e.getLineNumber());
            OCRDocResultSaver.markFailed(recordId, 'Job3 Error: ' + e.getMessage());
        }
    }
}