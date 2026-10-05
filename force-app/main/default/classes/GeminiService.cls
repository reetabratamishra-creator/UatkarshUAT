// ============================================================
    // CLASS — GeminiService.cls
    // ─────────────────────────────────────────────────────────────
    // PURPOSE:
    //   Central service class for all Gemini API interactions.
    //   Handles file fetching from Salesforce, file uploading to
    //   Gemini File API, category matching analysis, and PQC
    //   (Pre-Qualification Criteria) analysis.
    //
    // METHODS:
    //   getFiles(recordId)
    //     → Fetches all ContentVersion files attached to a given
    //       OCR_DOC__c record. Returns list ordered by CreatedDate.
    //
    //   uploadToGeminiFileApi(cv)
    //     → Uploads a single ContentVersion file to the Gemini
    //       File API. Returns the file URI string on success,
    //       null on failure.
    //
    //   analyzeCategory(fileUris, fileExtensions,
    //                   combinedFileNames, metadataPrompt)
    //     → Sends uploaded file URIs + category keyword metadata
    //       to Gemini. Returns matched category result as JSON
    //       string.
    //
    //   analyzePQC(fileUris, fileExtensions,
    //              combinedFileNames, pqcPrompt)
    //     → Sends uploaded file URIs + PQC checklist questions
    //       to Gemini. Returns PQC analysis result as JSON string.
    //
    // CALLED BY:
    //   Job1_UploadFilesQueueable  — getFiles(), uploadToGeminiFileApi()
    //   Job2_AnalyzeCategoryQueueable — analyzeCategory()
    //   Job3_AnalyzePQCQueueable      — analyzePQC()
    //
    // NAMED CREDENTIAL:
    //   Uses 'Gemini' named credential for all API endpoints.
    // ============================================================
    
    public with sharing class GeminiService {
        
        // ─────────────────────────────────────────────────────────
        // Fetch files for a given OCR_DOC__c record ID
        // FIX: added LIMIT 1000 on ContentDocumentLink query
        // ─────────────────────────────────────────────────────────
        public static List<ContentVersion> getFiles(String recordId) {
            System.debug('Fetching files for OCR_DOC__c ID: ' + recordId);
            
            List<OCR_DOC__c> ocrDocs = [
            SELECT Id, Name
            FROM OCR_DOC__c
            WHERE Id = :recordId
            LIMIT 1
        ];
            
            if (ocrDocs.isEmpty()) {
                System.debug('ERROR: OCR_DOC__c record not found: ' + recordId);
                return new List<ContentVersion>();
            }
            
            // FIX: added LIMIT 1000 — without this, records with
            // 50k+ links hit the SOQL row governor limit
            List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            LIMIT 100
        ];
            
            if (links.isEmpty()) {
                System.debug('ERROR: No files attached to record: ' + recordId);
                return new List<ContentVersion>();
            }
            
            Set<Id> contentDocIds = new Set<Id>();
            for (ContentDocumentLink link : links) {
                contentDocIds.add(link.ContentDocumentId);
            }
            
            return [
            SELECT
                Id,
                Title,
                FileExtension,
                ContentSize,
                VersionData,
                CreatedDate,
                CreatedBy.Name
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocIds AND IsLatest = TRUE
            ORDER BY CreatedDate ASC
        ];
        }
        
        // ─────────────────────────────────────────────────────────
        // Upload one file to Gemini File API
        // FIX: null VersionData guard added
        // FIX: response body now logged on failure
        // ─────────────────────────────────────────────────────────
        public static String uploadToGeminiFileApi(ContentVersion cv) {
            System.debug('===== GeminiService.uploadToGeminiFileApi START =====');
            System.debug('File: ' + cv.Title + ' | Size: ' + cv.ContentSize + ' bytes');
            
            // FIX: guard against null VersionData blob
            if (cv.VersionData == null) {
                System.debug('ERROR: VersionData is null for file: ' + cv.Title + '. Skipping upload.');
                return null;
            }
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Gemini/upload/v1beta/files?uploadType=media');
            req.setMethod('POST');
            req.setHeader('Content-Type', getMimeType(cv.FileExtension));
            req.setHeader('X-Goog-Upload-Protocol', 'raw');
            req.setHeader('X-Goog-Upload-Header-Content-Type', getMimeType(cv.FileExtension));
            req.setBodyAsBlob(cv.VersionData);
            req.setTimeout(120000);
            
            Http         http = new Http();
            HttpResponse res  = http.send(req);
            
            System.debug('Upload Status Code: ' + res.getStatusCode());
            
            if (res.getStatusCode() != 200) {
                // FIX: log response body to understand why upload failed
                System.debug('ERROR: File upload failed — Status: ' + res.getStatusCode()
                    + ' | Body: ' + res.getBody()?.left(500));
                return null;
            }
            
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> fileData    = (Map<String, Object>) responseMap.get('file');
            
            if (fileData == null) {
                System.debug('ERROR: "file" node missing in upload response. Body: ' + res.getBody()?.left(500));
                return null;
            }
            
            String fileUri = (String) fileData.get('uri');
            System.debug('fileUri received: ' + fileUri);
            System.debug('===== GeminiService.uploadToGeminiFileApi END =====');
            return fileUri;
        }
        
        // ─────────────────────────────────────────────────────────
        // Gemini Call 1 — Category matching
        // FIX: error response body now logged (first 500 chars)
        // ─────────────────────────────────────────────────────────
        public static String analyzeCategory(
            List<String> fileUris,
        List<String> fileExtensions,
        String       combinedFileNames,
        String       metadataPrompt
        ) {
            System.debug('===== GeminiService.analyzeCategory START =====');
            System.debug('Total files: ' + fileUris.size());
            
            List<Object> parts = new List<Object>();
            parts.add(new Map<String, Object>{
                'text' => buildCategoryPrompt(combinedFileNames, metadataPrompt)
            });
            for (Integer i = 0; i < fileUris.size(); i++) {
                parts.add(new Map<String, Object>{
                    'file_data' => new Map<String, Object>{
                        'mime_type' => getMimeType(fileExtensions[i]),
                        'file_uri'  => fileUris[i]
                    }
                });
            }
            
            System.debug('Metadata parts: ' + parts);
            
            Map<String, Object> body = new Map<String, Object>{
                'contents' => new List<Object>{
                    new Map<String, Object>{ 'parts' => parts }
                },
                'generationConfig' => new Map<String, Object>{
                    'temperature'      => 0.2,
                    'responseMimeType' => 'application/json'
                }
            };
            
            System.debug('Request body for Gemini Category Analysis: ' + JSON.serialize(body));
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Gemini/v1beta/models/gemini-2.5-flash:generateContent');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(120000);
            req.setBody(JSON.serialize(body));
            
            Http         http = new Http();
            HttpResponse res  = http.send(req);
            
            System.debug('analyzeCategory Status Code: ' + res.getStatusCode());
            // Log actual token usage from Gemini's response
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> usageMetadata = (Map<String, Object>) responseMap.get('usageMetadata');
            if (usageMetadata != null) {
                System.debug('=== GEMINI ACTUAL TOKEN USAGE ===');
                System.debug('Prompt Token Count    : ' + usageMetadata.get('promptTokenCount'));
                System.debug('Candidates Token Count: ' + usageMetadata.get('candidatesTokenCount'));
                System.debug('Total Token Count     : ' + usageMetadata.get('totalTokenCount'));
            }
            
            if (res.getStatusCode() != 200) {
                // FIX: log actual error body from Gemini for easier debugging
                System.debug('ERROR: analyzeCategory failed — Status: ' + res.getStatusCode()
                    + ' | Body: ' + res.getBody()?.left(500));
                return '{"error":"Gemini category analysis failed with status '
                    + res.getStatusCode() + '"}';
            }
            
            String result = extractTextFromGeminiResponse(res.getBody());
            System.debug('===== GeminiService.analyzeCategory END =====');
            return result;
        }
        
        // ─────────────────────────────────────────────────────────
        // Gemini Call 2 — PQC analysis
        // FIX: error response body now logged (first 500 chars)
        // ─────────────────────────────────────────────────────────
        public static String analyzePQC(
            List<String> fileUris,
        List<String> fileExtensions,
        String       combinedFileNames,
        String       pqcPrompt
        ) {
            System.debug('===== GeminiService.analyzePQC START =====');
            System.debug('Total files: ' + fileUris.size());
            
            List<Object> parts = new List<Object>();
            parts.add(new Map<String, Object>{
                'text' => buildPQCPrompt(combinedFileNames, pqcPrompt)
            });
            for (Integer i = 0; i < fileUris.size(); i++) {
                parts.add(new Map<String, Object>{
                    'file_data' => new Map<String, Object>{
                        'mime_type' => getMimeType(fileExtensions[i]),
                        'file_uri'  => fileUris[i]
                    }
                });
            }
            
            Map<String, Object> body = new Map<String, Object>{
                'contents' => new List<Object>{
                    new Map<String, Object>{ 'parts' => parts }
                },
                'generationConfig' => new Map<String, Object>{
                    'temperature'      => 0.2,
                    'responseMimeType' => 'application/json'
                }
            };
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Gemini/v1beta/models/gemini-2.5-flash:generateContent');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(120000);
            req.setBody(JSON.serialize(body));
            
            Http         http = new Http();
            HttpResponse res  = http.send(req);
            
            System.debug('analyzePQC Status Code: ' + res.getStatusCode());
            
            if (res.getStatusCode() != 200) {
                // FIX: log actual error body from Gemini for easier debugging
                System.debug('ERROR: analyzePQC failed — Status: ' + res.getStatusCode()
                    + ' | Body: ' + res.getBody()?.left(500));
                return '{"error":"Gemini PQC analysis failed with status '
                    + res.getStatusCode() + '"}';
            }
            
            String result = extractTextFromGeminiResponse(res.getBody());
            System.debug('===== GeminiService.analyzePQC END =====');
            return result;
        }
        
        // ─────────────────────────────────────────────────────────
        // Prompt builder — Category matching — UNCHANGED
        // ─────────────────────────────────────────────────────────
        private static String buildCategoryPrompt(String fileNames, String metadataPrompt) {
            return 'You are a Tender Document Analyzer.\n\n'
                + 'Files being analyzed: ' + fileNames + '\n\n'
                + '--- CATEGORIES AND KEYWORDS ---\n'
                + metadataPrompt
                + '\n\n--- INSTRUCTIONS ---\n'
                + 'Read ALL attached files carefully. They together form one tender document set.\n'
                + 'Check which category matches based on positive keywords present and negative keywords absent.\n'
                + 'Return ONLY a valid JSON object. No explanation. No markdown. No extra text.\n\n'
                + 'JSON format:\n'
                + '{\n'
                + '  "fileName": "' + fileNames + '",\n'
                + '  "matchedCategory": "<best matched category name>",\n'
                + '  "department": "<department name>",\n'
                + '  "summary": "<2-3 line summary of the document>",\n'
                + '  "isRelevant": true/false,\n'
                + '  "isExcluded": true/false,\n'
                + '  "confidenceScore": "<High/Medium/Low>",\n'
                + '  "matchedSections": [\n'
                + '    {\n'
                + '      "keyword": "<matched keyword>",\n'
                + '      "page": "<page number>",\n'
                + '      "section": "<section heading>",\n'
                + '      "matchedText": "<exact or near-exact text from document>"\n'
                + '    }\n'
                + '  ]\n'
                + '}';
        }
        
        // ─────────────────────────────────────────────────────────
        // Prompt builder — PQC checklist — UNCHANGED
        // ─────────────────────────────────────────────────────────
        private static String buildPQCPrompt(String fileNames, String pqcPrompt) {
            return 'You are a Tender Document PQC (Pre-Qualification Criteria) Analyzer.\n\n'
                + 'Files being analyzed: ' + fileNames + '\n\n'
                + '--- PQC CHECKLIST ---\n'
                + pqcPrompt
                + '\n\n--- INSTRUCTIONS ---\n'
                + 'Read ALL attached tender documents carefully. They together form one tender document set.\n'
                + 'For EACH PQC item listed above, find the relevant information across all files.\n'
                + 'If a PQC item is not mentioned in any document, mark status as "Not Found".\n'
                + 'Return ONLY a valid JSON object. No explanation. No markdown. No extra text.\n\n'
                + 'JSON format:\n'
                + '{\n'
                + '  "fileName": "' + fileNames + '",\n'
                + '  "pqcAnalysis": [\n'
                + '    {\n'
                + '      "pqcLabel": "<PQC item label>",\n'
                + '      "findings": "<what was found in the document>",\n'
                + '      "pageReference": "<page number or N/A>",\n'
                + '      "status": "<Found / Not Found / Partial>"\n'
                + '    }\n'
                + '  ]\n'
                + '}';
        }
        
        // ─────────────────────────────────────────────────────────
        // Extract text from Gemini response
        // FIX: full null guards on candidates / content / parts / text
        // ─────────────────────────────────────────────────────────
        private static String extractTextFromGeminiResponse(String responseBody) {
            try {
                Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
                
                List<Object> candidates = (List<Object>) resp.get('candidates');
                if (candidates == null || candidates.isEmpty()) {
                    System.debug('ERROR: No candidates in Gemini response');
                    return '{"error":"No candidates in Gemini response"}';
                }
                
                Map<String, Object> firstCandidate = (Map<String, Object>) candidates[0];
                if (firstCandidate == null) {
                    System.debug('ERROR: First candidate is null');
                    return '{"error":"First candidate is null"}';
                }
                
                Map<String, Object> content = (Map<String, Object>) firstCandidate.get('content');
                if (content == null) {
                    System.debug('ERROR: content node missing in Gemini candidate');
                    return '{"error":"No content in Gemini candidate"}';
                }
                
                List<Object> parts = (List<Object>) content.get('parts');
                if (parts == null || parts.isEmpty()) {
                    System.debug('ERROR: parts node missing or empty in Gemini content');
                    return '{"error":"No parts in Gemini content"}';
                }
                
                Map<String, Object> firstPart = (Map<String, Object>) parts[0];
                if (firstPart == null) {
                    System.debug('ERROR: First part is null');
                    return '{"error":"First part is null in Gemini response"}';
                }
                
                String text = (String) firstPart.get('text');
                if (String.isBlank(text)) {
                    System.debug('ERROR: text is blank in Gemini response');
                    return '{"error":"Empty text in Gemini response"}';
                }
                
                System.debug('Extracted Gemini Text: ' + text);
                return text;
                
            } catch (Exception e) {
                System.debug('ERROR extracting Gemini response: ' + e.getMessage());
            return '{"error":"Failed to parse Gemini response: ' + e.getMessage() + '"}';
        }
    }
    
    // ─────────────────────────────────────────────────────────
    // MIME type mapping
    // FIX: added csv, doc, zip, ppt, pptx
    // ─────────────────────────────────────────────────────────
    private static String getMimeType(String ext) {
        if (String.isBlank(ext)) return 'application/octet-stream';
        ext = ext.toLowerCase();
        if (ext == 'pdf')  return 'application/pdf';
        if (ext == 'xlsx') return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        if (ext == 'xls')  return 'application/vnd.ms-excel';
        if (ext == 'docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        if (ext == 'doc')  return 'application/msword';
        if (ext == 'pptx') return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
        if (ext == 'ppt')  return 'application/vnd.ms-powerpoint';
        if (ext == 'csv')  return 'text/csv';
        if (ext == 'json') return 'application/json';
        if (ext == 'html') return 'text/html';
        if (ext == 'txt')  return 'text/plain';
        if (ext == 'png')  return 'image/png';
        if (ext == 'jpg')  return 'image/jpeg';
        if (ext == 'jpeg') return 'image/jpeg';
        if (ext == 'zip')  return 'application/zip';
        return 'application/octet-stream';
    }
}