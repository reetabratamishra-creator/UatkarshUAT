// ============================================================
// CLASS 10 — Job3_AnalyzePQCQueueable.cls
// ─────────────────────────────────────────────────────────────
// Job 3 of 4 in the Queueable chain
// Responsibilities:
//   - Load PQC metadata from PQCMetadataService
//   - Call GeminiService.analyzePQC() with same fileUris
//   - Pass both categoryRawResponse + pqcRawResponse to Job4
// ─────────────────────────────────────────────────────────────
// Uses:
//   PQCMetadataService.getAllPQCs()
//   PQCMetadataService.buildPQCPrompt()
//   GeminiService.analyzePQC()
//   OCRDocResultSaver.markFailed()
// ============================================================
public with sharing class Job3_AnalyzePQCQueueable_Batch implements Queueable, Database.AllowsCallouts {

    private String       recordId;
    private List<String> fileUris;
    private List<String> fileExtensions;
    private String       combinedFileNames;
    private String       categoryRawResponse;

    // Constructor
    public Job3_AnalyzePQCQueueable_Batch(
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
                // STEP 2: Call Gemini — PQC analysis
                // Reuses same fileUris — no re-upload
                // ─────────────────────────────────────────────
                String pqcPrompt = PQCMetadataService.buildPQCPrompt(pqcList);

                pqcRawResponse = GeminiService.analyzePQC(
                    fileUris,
                    fileExtensions,
                    combinedFileNames,
                    pqcPrompt
                );

                System.debug('PQC Response received. Length: ' + pqcRawResponse.length());
            }

            // ─────────────────────────────────────────────────
            // STEP 3: Chain to Job4 — pass both results forward
            // ─────────────────────────────────────────────────
            System.enqueueJob(new Job4_SaveResultsQueueable_Batch(
                recordId,
                categoryRawResponse,
                pqcRawResponse,
                fileUris.size()
            ));

            System.debug('===== Job3_AnalyzePQCQueueable END — Chained to Job4 =====');

        } catch (Exception e) {
            System.debug('ERROR in Job3: ' + e.getMessage());
            OCRDocResultSaver.markFailed(recordId, 'Job3 Error: ' + e.getMessage());
        }
    }
}