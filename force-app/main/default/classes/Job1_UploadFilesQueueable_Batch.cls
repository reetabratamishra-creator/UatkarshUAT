// ============================================================
// CLASS 8 — Job1_UploadFilesQueueable.cls
// ─────────────────────────────────────────────────────────────
// Job 1 of 4 in the Queueable chain
// Responsibilities:
//   - Fetch all files attached to OCR_DOC__c record
//   - Upload each file to Gemini File API
//   - Collect fileUris + fileExtensions
//   - Build combinedFileNames string
//   - Chain to Job2
// ─────────────────────────────────────────────────────────────
// Uses:
//   GeminiService.getFiles(recordId)  — fetch files
//   GeminiService.uploadToGeminiFileApi() — upload each file
//   OCRDocResultSaver.markFailed()        — on error
// ============================================================
public with sharing class Job1_UploadFilesQueueable_Batch implements Queueable, Database.AllowsCallouts {

    private String recordId;

    // Constructor — receives OCR_DOC__c record ID
    public Job1_UploadFilesQueueable_Batch(String recordId) {
        this.recordId = recordId;
    }

    public void execute(QueueableContext ctx) {
        System.debug('===== Job1_UploadFilesQueueable START | Record: ' + recordId + ' =====');

        try {
            // ─────────────────────────────────────────────────
            // STEP 1: Fetch all files for this record
            // ─────────────────────────────────────────────────
            List<ContentVersion> files = GeminiService.getFiles(recordId);

            if (files.isEmpty()) {
                System.debug('ERROR: No files found for record: ' + recordId);
                OCRDocResultSaver.markFailed(recordId, 'No files found on OCR_DOC__c record.');
                return;
            }

            System.debug('Total files to upload: ' + files.size());

            // ─────────────────────────────────────────────────
            // STEP 2: Upload each file to Gemini — collect URIs
            // ─────────────────────────────────────────────────
            List<String> fileUris       = new List<String>();
            List<String> fileExtensions = new List<String>();
            String combinedFileNames    = '';

            for (ContentVersion cv : files) {
                System.debug('Uploading: ' + cv.Title);

                String uri = GeminiService.uploadToGeminiFileApi(cv);

                if (String.isBlank(uri)) {
                    System.debug('ERROR: Upload failed for: ' + cv.Title);
                    OCRDocResultSaver.markFailed(recordId, 'File upload failed for: ' + cv.Title);
                    return;
                }

                fileUris.add(uri);
                fileExtensions.add(cv.FileExtension);
                combinedFileNames += cv.Title + ', ';
                System.debug('Uploaded → URI: ' + uri);
            }

            combinedFileNames = combinedFileNames.removeEnd(', ');
            System.debug('All files uploaded. URIs: ' + fileUris.size());

            // ─────────────────────────────────────────────────
            // STEP 3: Chain to Job2 — pass fileUris forward
            // ─────────────────────────────────────────────────
            System.enqueueJob(new Job2_AnalyzeCategoryQueueable_Batch(
                recordId,
                fileUris,
                fileExtensions,
                combinedFileNames
            ));

            System.debug('===== Job1_UploadFilesQueueable END — Chained to Job2 =====');

        } catch (Exception e) {
            System.debug('ERROR in Job1: ' + e.getMessage());
            OCRDocResultSaver.markFailed(recordId, 'Job1 Error: ' + e.getMessage());
        }
    }
}

//System.enqueueJob(new Job1_UploadFilesQueueable('a0LC200000ARCCDMA5'));