// ============================================================
// CLASS — Job1_UploadFilesQueueable.cls
// ─────────────────────────────────────────────────────────────
// PURPOSE:
//   First job in the Tender Analysis async chain.
//   Fetches all files attached to an OCR_DOC__c record,
//   uploads each file to the Gemini File API, collects the
//   returned file URIs, then chains to Job2.
//
// TRIGGER POINT:
//   Called manually or from a trigger/flow by passing an
//   OCR_DOC__c record ID:
//   System.enqueueJob(new Job1_UploadFilesQueueable(recordId));
//

// STEPS:
//   1. Validates recordId is not null/blank
//   2. Fetches all ContentVersion files linked to the record
//   3. Uploads each file to Gemini File API via GeminiService
//   4. Collects file URIs and file extensions for each upload
//   5. Chains to Job2_AnalyzeCategoryQueueable with the URIs
//

// ============================================================

public with sharing class Job1_UploadFilesQueueable implements Queueable, Database.AllowsCallouts {

    private String recordId;

    public Job1_UploadFilesQueueable(String recordId) {
        this.recordId = recordId;
    }

    public void execute(QueueableContext ctx) {
        System.debug('===== Job1_UploadFilesQueueable START | Record: ' + recordId + ' =====');

        // ─────────────────────────────────────────────────────
        // GUARD: null or blank recordId
        // ─────────────────────────────────────────────────────
        if (String.isBlank(recordId)) {
            System.debug('ERROR: recordId is null or blank. Aborting Job1.');
            return;
        }

        // These are set outside try so markFailed can be called
        // after all callouts are done — avoids DML + callout error
        String  failureMessage   = null;
        Boolean allCalloutsAdone = false;

        List<String> fileUris       = new List<String>();
        List<String> fileExtensions = new List<String>();
        String       combinedFileNames = '';

        try {
            // ─────────────────────────────────────────────────
            // STEP 1: Fetch all files for this record
            // ─────────────────────────────────────────────────
            List<ContentVersion> files = GeminiService.getFiles(recordId);

            if (files.isEmpty()) {
                System.debug('ERROR: No files found for record: ' + recordId);
                // No callouts happened yet — safe to DML here
                OCRDocResultSaver.markFailed(recordId, 'No files found on OCR_DOC__c record.');
                return;
            }

            System.debug('Total files to upload: ' + files.size());

            // ─────────────────────────────────────────────────
            // STEP 2: Upload each file to Gemini — collect URIs
            // ─────────────────────────────────────────────────
            for (ContentVersion cv : files) {
                System.debug('Uploading: ' + cv.Title + ' | Size: ' + cv.ContentSize);

                String uri = GeminiService.uploadToGeminiFileApi(cv);

                if (String.isBlank(uri)) {
                    System.debug('ERROR: Upload failed for: ' + cv.Title);
                    // Mark failure message — DML done AFTER loop (post-callout safe)
                    failureMessage = 'File upload failed for: ' + cv.Title;
                    break;
                }

                fileUris.add(uri);

                // FIX: null FileExtension guard — default to 'pdf'
                fileExtensions.add(String.isBlank(cv.FileExtension) ? 'pdf' : cv.FileExtension);

                // FIX: cap combinedFileNames to avoid heap bloat on 100-file tenders
                if (combinedFileNames.length() < 500) {
                    combinedFileNames += cv.Title + ', ';
                }

                System.debug('Uploaded → URI: ' + uri);
            }

            // All callouts done — now safe to DML
            allCalloutsAdone = true;

        } catch (Exception e) {
            System.debug('ERROR in Job1 (callout phase): ' + e.getMessage() + 
                         ' | Line: ' + e.getLineNumber());
            failureMessage = 'Job1 Error: ' + e.getMessage();
            allCalloutsAdone = true; // callouts are done (crashed out)
        }

        // ─────────────────────────────────────────────────────
        // POST-CALLOUT: DML and enqueue — safe zone
        // ─────────────────────────────────────────────────────
        if (failureMessage != null) {
            OCRDocResultSaver.markFailed(recordId, failureMessage);
            return;
        }

        if (fileUris.isEmpty()) {
            OCRDocResultSaver.markFailed(recordId, 'No file URIs collected. All uploads may have failed.');
            return;
        }

        combinedFileNames = combinedFileNames.removeEnd(', ');
        System.debug('All files uploaded. Total URIs: ' + fileUris.size());
        System.debug('Combined file names: ' + combinedFileNames);

        // ─────────────────────────────────────────────────────
        // STEP 3: Chain to Job2 — wrapped in try-catch
        // FIX: enqueueJob silent failure now logged + markFailed
        // ─────────────────────────────────────────────────────
        try {
            System.enqueueJob(new Job2_AnalyzeCategoryQueueable(
                recordId,
                fileUris,
                fileExtensions,
                combinedFileNames
            ));
            System.debug('===== Job1_UploadFilesQueueable END — Chained to Job2 =====');
        } catch (Exception e) {
            System.debug('ERROR: Failed to enqueue Job2 — ' + e.getMessage());
            OCRDocResultSaver.markFailed(recordId, 'Job2 enqueue failed: ' + e.getMessage());
        }
    }
}