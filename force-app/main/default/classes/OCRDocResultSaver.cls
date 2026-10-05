// ============================================================
// CLASS 6 — OCRDocResultSaver.cls  (NEW)
// Saves Gemini analysis results back to OCR_DOC__c record
// Called from TenderAnalyzerController after Step 7
// ─────────────────────────────────────────────────────────────
// Field Mapping:
//   AI_Status__c          → "Completed" or "Failed"
//   AI_Response__c        → full category result JSON
//   Confidence_Score__c   → confidenceScore (High=1, Medium=0.5, Low=0)
//   Matched_Department__c → department from category result
//   Matched_Keywords__c   → matchedSections JSON
//   Error_Message__c      → error details if something failed
//   PQCDetails1__c        → PQC JSON (first 131072 chars)
//   PQCDetails2__c        → PQC JSON overflow (remaining chars)
//   Uploaded_File_Count__c→ number of files uploaded
// ============================================================
public with sharing class OCRDocResultSaver {

    // ─────────────────────────────────────────────────────────
    // Main method — call this from TenderAnalyzerController
    // after both Gemini calls are done
    // ─────────────────────────────────────────────────────────
    public static void saveResults(
        String       recordId,
        String       categoryRawResponse,
        String       pqcRawResponse,
        Integer      uploadedFileCount
    ) {
        System.debug('========================================');
        System.debug('=== OCRDocResultSaver.saveResults START ===');
        System.debug('========================================');
        System.debug('Record ID         : ' + recordId);
        System.debug('Uploaded File Count: ' + uploadedFileCount);

        OCR_DOC__c record = new OCR_DOC__c(Id = recordId);

        try {
            // ─────────────────────────────────────────────────
            // Parse category result
            // ─────────────────────────────────────────────────
            Map<String, Object> categoryResult =
                (Map<String, Object>) JSON.deserializeUntyped(categoryRawResponse);

            // Check if category result has an error
            if (categoryResult.containsKey('error')) {
                System.debug('ERROR in category result: ' + categoryResult.get('error'));
                record.AI_Status__c     = 'Failed';
                record.Error_Message__c = 'Category Analysis Error: '
                                        + (String) categoryResult.get('error');
                update record;
                return;
            }

            // ── AI_Response__c — full category JSON ──────────
            record.AI_Response__c = categoryRawResponse;

            // ── Matched_Department__c ─────────────────────────
            if (categoryResult.containsKey('department')) {
                record.Matched_Department__c =
                    String.valueOf(categoryResult.get('department')).left(255);
            }

            // ── Confidence_Score__c — High=1 / Medium=0.5 / Low=0
            if (categoryResult.containsKey('confidenceScore')) {
                String confidence =
                    String.valueOf(categoryResult.get('confidenceScore')).toLowerCase();
                if      (confidence == 'high')   record.Confidence_Score__c = 1.0;
                else if (confidence == 'medium') record.Confidence_Score__c = 0.5;
                else                             record.Confidence_Score__c = 0.0;
            }

            // ── Matched_Keywords__c — matchedSections JSON ────
            if (categoryResult.containsKey('matchedSections')) {
                Object matchedSections = categoryResult.get('matchedSections');
                record.Matched_Keywords__c = JSON.serialize(matchedSections);
            }

            // ─────────────────────────────────────────────────
            // Parse PQC result
            // ─────────────────────────────────────────────────
            Map<String, Object> pqcResult =
                (Map<String, Object>) JSON.deserializeUntyped(pqcRawResponse);

            Boolean pqcHasError = pqcResult.containsKey('error');

            if (pqcHasError) {
                System.debug('WARNING: PQC result has error — storing error in PQCDetails1__c');
                record.PQCDetails1__c = 'PQC Error: ' + (String) pqcResult.get('error');
            } else {
                // ── Split PQC JSON across PQCDetails1 + PQCDetails2
                String pqcJson = pqcRawResponse;
                Integer maxLen = 131072;

                if (pqcJson.length() <= maxLen) {
                    // Fits in PQCDetails1__c alone
                    record.PQCDetails1__c = pqcJson;
                    record.PQCDetails2__c = null;
                    System.debug('PQC JSON fits in PQCDetails1__c. Length: ' + pqcJson.length());
                } else {
                    // Split — first 131072 chars in PQCDetails1, rest in PQCDetails2
                    record.PQCDetails1__c = pqcJson.substring(0, maxLen);
                    record.PQCDetails2__c = pqcJson.substring(maxLen);
                    System.debug('PQC JSON split across both fields.');
                    System.debug('PQCDetails1__c length: ' + maxLen);
                    System.debug('PQCDetails2__c length: ' + (pqcJson.length() - maxLen));
                }
            }

            // ─────────────────────────────────────────────────
            // Final status + file count
            // ─────────────────────────────────────────────────
            record.AI_Status__c           = 'Completed';
            record.Uploaded_File_Count__c = uploadedFileCount;
            record.Error_Message__c       = null; // clear any previous error

            System.debug('AI_Status__c set to: Completed');

        } catch (Exception e) {
            // Something went wrong while parsing — mark as Failed
            System.debug('ERROR in saveResults: ' + e.getMessage());
            record.AI_Status__c     = 'Failed';
            record.Error_Message__c = 'Save Error: ' + e.getMessage();
        }

        // ── DML — update the record ───────────────────────────
        try {
            update record;
            System.debug('OCR_DOC__c record updated successfully: ' + recordId);
        } catch (DmlException de) {
            System.debug('DML ERROR updating OCR_DOC__c: ' + de.getMessage());
        }

        System.debug('========================================');
        System.debug('=== OCRDocResultSaver.saveResults END ===');
        System.debug('========================================');
    }

    // ─────────────────────────────────────────────────────────
    // Mark record as Failed — call this on any critical error
    // in TenderAnalyzerController before returning
    // ─────────────────────────────────────────────────────────
    public static void markFailed(String recordId, String errorMessage) {
        System.debug('OCRDocResultSaver.markFailed: ' + errorMessage);
        try {
            update new OCR_DOC__c(
                Id              = recordId,
                AI_Status__c    = 'Failed',
                Error_Message__c = errorMessage
            );
        } catch (DmlException de) {
            System.debug('DML ERROR in markFailed: ' + de.getMessage());
        }
    }
}