// ============================================================
// CLASS — Job2_AnalyzeCategoryQueueable.cls
// ─────────────────────────────────────────────────────────────
// PURPOSE:
//   Second job in the Tender Analysis async chain.
//   Loads category keyword metadata from custom metadata,
//   builds the category prompt, calls Gemini for category
//   matching analysis, then chains to Job3.
//
// TRIGGER POINT:
//   Chained automatically from Job1_UploadFilesQueueable
//   after all files are successfully uploaded to Gemini.
//

// STEPS:
//   1. Validates fileUris and fileExtensions are not empty
//   2. Loads all records from Tender_Key_words_Final__mdt
//   3. Builds category metadata prompt
//   4. Calls Gemini analyzeCategory() with file URIs + prompt
//   5. Validates Gemini response is not blank or error
//   6. Chains to Job3_AnalyzePQCQueueable with category result

//
// DEPENDS ON:
//   GeminiService          — analyzeCategory() API call
//   TenderMetadataService  — metadata loading + prompt build
//   OCRDocResultSaver      — failure logging to OCR_DOC__c
// ============================================================
public with sharing class Job2_AnalyzeCategoryQueueable implements Queueable, Database.AllowsCallouts {

    private String       recordId;
    private List<String> fileUris;
    private List<String> fileExtensions;
    private String       combinedFileNames;

    public Job2_AnalyzeCategoryQueueable(
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

        // ─────────────────────────────────────────────────────
        // GUARD: validate inputs passed from Job1
        // FIX: empty fileUris/fileExtensions caught early
        // ─────────────────────────────────────────────────────
        if (fileUris == null || fileUris.isEmpty()) {
            System.debug('ERROR: fileUris is null or empty. Aborting Job2.');
            OCRDocResultSaver.markFailed(recordId, 'Job2 received empty fileUris from Job1.');
            return;
        }
        if (fileExtensions == null || fileExtensions.isEmpty()) {
            System.debug('ERROR: fileExtensions is null or empty. Aborting Job2.');
            OCRDocResultSaver.markFailed(recordId, 'Job2 received empty fileExtensions from Job1.');
            return;
        }

        try {
            // ─────────────────────────────────────────────────
            // STEP 1: Load category metadata
            // ─────────────────────────────────────────────────
            List<TenderMetadataService.CategoryConfig> categories =
                TenderMetadataService.getAllCategories();

            if (categories.isEmpty()) {
                System.debug('ERROR: No records found in Tender_Key_words_Final__mdt.');
                OCRDocResultSaver.markFailed(recordId, 'No records found in Tender_Key_words_Final__mdt.');
                return;
            }

            String metadataPrompt = TenderMetadataService.buildMetadataPrompt(categories);
            System.debug('Metadata prompt built. Length: ' + metadataPrompt.length());
            System.debug('File extensions : ' + fileExtensions);
            System.debug('Combined file names : ' + combinedFileNames);
            System.debug('File URIs : ' + fileUris);
            //System.debug('Metadata prompt preview: ' + metadataPrompt);
            
            // FIX: blank prompt guard — prevents garbage Gemini result
            if (String.isBlank(metadataPrompt)) {
                System.debug('ERROR: Metadata prompt is blank.');
                OCRDocResultSaver.markFailed(recordId, 'Metadata prompt is blank. Check Tender_Key_words_Final__mdt records.');
                return;
            }

            // ─────────────────────────────────────────────────
            // STEP 2: Call Gemini — Category analysis
            // ─────────────────────────────────────────────────
            String categoryRawResponse = GeminiService.analyzeCategory(
                fileUris,
                fileExtensions,
                combinedFileNames,
                metadataPrompt
            );

            // FIX: null/blank response guard — prevents NPE on .length() call
            if (String.isBlank(categoryRawResponse)) {
                System.debug('ERROR: Category analysis returned null or blank response.');
                OCRDocResultSaver.markFailed(recordId, 'Category analysis returned null or blank response.');
                return;
            }

            System.debug('Category response received. Length: ' + categoryRawResponse.length());

            // FIX: error JSON guard — prevents broken response reaching Job3
            if (categoryRawResponse.contains('"error"')) {
                System.debug('ERROR: Gemini returned error in category response: ' + categoryRawResponse);
                OCRDocResultSaver.markFailed(recordId, 'Category analysis failed: ' + categoryRawResponse.left(500));
                return;
            }

            // ─────────────────────────────────────────────────
            // STEP 3: Chain to Job3 — pass everything forward
            // FIX: enqueueJob wrapped in try-catch
            // ─────────────────────────────────────────────────
            try {
                System.enqueueJob(new Job3_AnalyzePQCQueueable(
                    recordId,
                    fileUris,
                    fileExtensions,
                    combinedFileNames,
                    categoryRawResponse
                ));
                System.debug('===== Job2_AnalyzeCategoryQueueable END — Chained to Job3 =====');
            } catch (Exception e) {
                System.debug('ERROR: Failed to enqueue Job3 — ' + e.getMessage());
                OCRDocResultSaver.markFailed(recordId, 'Job3 enqueue failed: ' + e.getMessage());
            }

        } catch (Exception e) {
            System.debug('ERROR in Job2: ' + e.getMessage() + ' | Line: ' + e.getLineNumber());
            OCRDocResultSaver.markFailed(recordId, 'Job2 Error: ' + e.getMessage());
        }
    }
}