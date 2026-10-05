// ============================================================
// CLASS 9 — Job2_AnalyzeCategoryQueueable.cls
// ─────────────────────────────────────────────────────────────
// Job 2 of 4 in the Queueable chain
// Responsibilities:
//   - Load category metadata from TenderMetadataService
//   - Call GeminiService.analyzeCategory() with all fileUris
//   - Pass categoryRawResponse forward to Job3
// ─────────────────────────────────────────────────────────────
// Uses:
//   TenderMetadataService.getAllCategories()
//   TenderMetadataService.buildMetadataPrompt()
//   GeminiService.analyzeCategory()
//   OCRDocResultSaver.markFailed()
// ============================================================
public with sharing class Job2_AnalyzeCategoryQueueable_Batch implements Queueable, Database.AllowsCallouts {

    private String       recordId;
    private List<String> fileUris;
    private List<String> fileExtensions;
    private String       combinedFileNames;

    // Constructor
    public Job2_AnalyzeCategoryQueueable_Batch(
        String       recordId,
        List<String> fileUris,
        List<String> fileExtensions,
        String       combinedFileNames
    ) {
        this.recordId          = recordId;
        this.fileUris          = fileUris;
        this.fileExtensions    = fileExtensions;
        this.combinedFileNames = combinedFileNames;
    }

    public void execute(QueueableContext ctx) {
        System.debug('===== Job2_AnalyzeCategoryQueueable START | Record: ' + recordId + ' =====');

        try {
            // ─────────────────────────────────────────────────
            // STEP 1: Load category metadata
            // ─────────────────────────────────────────────────
            List<TenderMetadataService.CategoryConfig> categories =
                TenderMetadataService.getAllCategories();

            if (categories.isEmpty()) {
                OCRDocResultSaver.markFailed(recordId, 'No records found in Tender_Key_words_Final__mdt.');
                return;
            }

            String metadataPrompt = TenderMetadataService.buildMetadataPrompt(categories);
            System.debug('Metadata prompt built. Length: ' + metadataPrompt.length());

            // ─────────────────────────────────────────────────
            // STEP 2: Call Gemini — Category analysis
            // ─────────────────────────────────────────────────
            String categoryRawResponse = GeminiService.analyzeCategory(
                fileUris,
                fileExtensions,
                combinedFileNames,
                metadataPrompt
            );

            System.debug('Category Response received. Length: ' + categoryRawResponse.length());

            // ─────────────────────────────────────────────────
            // STEP 3: Chain to Job3 — pass everything forward
            // ─────────────────────────────────────────────────
            System.enqueueJob(new Job3_AnalyzePQCQueueable_Batch(
                recordId,
                fileUris,
                fileExtensions,
                combinedFileNames,
                categoryRawResponse
            ));

            System.debug('===== Job2_AnalyzeCategoryQueueable END — Chained to Job3 =====');

        } catch (Exception e) {
            System.debug('ERROR in Job2: ' + e.getMessage());
            OCRDocResultSaver.markFailed(recordId, 'Job2 Error: ' + e.getMessage());
        }
    }
}