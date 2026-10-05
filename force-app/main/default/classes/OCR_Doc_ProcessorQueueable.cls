public class OCR_Doc_ProcessorQueueable
    implements Queueable, Database.AllowsCallouts {

    private Id ocrDocId;

    private static final String API_ENDPOINT =
        'callout:DocumentAI_API/services/data/v66.0/' +
        'ssot/document-processing/actions/extract-data';

    private static final String ML_MODEL = 'VertexAIGemini25Flash';

    public OCR_Doc_ProcessorQueueable(Id ocrDocId) {
        this.ocrDocId = ocrDocId;
    }

    public void execute(QueueableContext qc) {
        System.debug('========================================');
        System.debug('OCR_Doc_ProcessorQueueable STARTED');
        System.debug('OCR Doc Id => ' + ocrDocId);
        System.debug('========================================');

        try {

            // Step 1 — Find all files attached to this OCR_DOC record
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :ocrDocId
            ];

            System.debug('STEP 1 — Total files found => ' + links.size());

            if (links.isEmpty()) {
                System.debug('STEP 1 — ABORT: No files attached to record');
                return;
            }

            // Step 2 — Load all active keyword metadata records
            List<Tender_Key_words_Final__mdt> allKeywords = [
                SELECT DeveloperName,
                       Department__c,
                       Matched_Positive_Keywords__c,
                       Matched_Negative_Keywords__c,
                       Schema_Prompt__c,
                       Is_Relevant__c,
                       Is_Excluded__c
                FROM Tender_Key_words_Final__mdt
                WHERE Is_Relevant__c = true
                  AND Is_Excluded__c = false
            ];

            System.debug('STEP 2 — Total keyword configs loaded => ' + allKeywords.size());

            if (allKeywords.isEmpty()) {
                System.debug('STEP 2 — ABORT: No active keyword metadata found');
                return;
            }

            for (Tender_Key_words_Final__mdt kw : allKeywords) {
                System.debug('STEP 2 — Loaded config: ' + kw.DeveloperName + ' | Dept: ' + kw.Department__c);
            }

            // Step 3 — Build dynamic schema from keywords
            System.debug('STEP 3 — Building dynamic schema...');
            String dynamicSchema = buildDynamicSchema(allKeywords);
            System.debug('STEP 3 — Schema built successfully');
            System.debug('STEP 3 — Schema length (chars) => ' + dynamicSchema.length());

            // Step 4 — Process each file one by one
            List<OCR_Doc_Result__c> resultsToInsert = new List<OCR_Doc_Result__c>();
            Integer fileIndex = 0;

            for (ContentDocumentLink link : links) {
                fileIndex++;
                System.debug('----------------------------------------');
                System.debug('STEP 4 — Processing file ' + fileIndex + ' of ' + links.size());
                System.debug('STEP 4 — ContentDocumentId => ' + link.ContentDocumentId);

                // Fetch latest version of this file
                List<ContentVersion> cvList = [
                    SELECT Id, Title, FileExtension, VersionData
                    FROM ContentVersion
                    WHERE ContentDocumentId = :link.ContentDocumentId
                    ORDER BY VersionNumber DESC
                    LIMIT 1
                ];

                if (cvList.isEmpty()) {
                    System.debug('STEP 4 — SKIP: ContentVersion not found for => ' + link.ContentDocumentId);
                    continue;
                }

                ContentVersion cv = cvList[0];
                System.debug('STEP 4 — File name => ' + cv.Title);
                System.debug('STEP 4 — File extension => ' + cv.FileExtension);
                System.debug('STEP 4 — File size (bytes) => ' + cv.VersionData.size());

                // Step 5 — Call Document AI API
                System.debug('STEP 5 — Calling Document AI for file => ' + cv.Title);
                String responseBody = callDocumentAI(cv, dynamicSchema);

                if (responseBody == null) {
                    System.debug('STEP 5 — FAILED: Document AI returned null for => ' + cv.Title);
                    resultsToInsert.add(new OCR_Doc_Result__c(
                        OCR_Doc__c             = ocrDocId,
                        File_Name__c           = cv.Title,
                        Status__c              = 'Failed',
                        Content_Document_Id__c = String.valueOf(link.ContentDocumentId)
                    ));
                    continue;
                }

                System.debug('STEP 5 — Document AI response received for => ' + cv.Title);

                // Step 6 — Parse the API response
                System.debug('STEP 6 — Parsing API response...');
                Map<String, Object> parsedResult = parseApiResponse(responseBody);

                if (parsedResult == null) {
                    System.debug('STEP 6 — SKIP: Could not parse response for => ' + cv.Title);
                    continue;
                }

                System.debug('STEP 6 — Parsed result keys => ' + parsedResult.keySet());
                System.debug('STEP 6 — Full parsed result => ' + JSON.serializePretty(parsedResult));

                // Step 7 — Find matching departments from parsed result
                System.debug('STEP 7 — Building result records for => ' + cv.Title);
                List<OCR_Doc_Result__c> fileResults = buildResults(
                    parsedResult,
                    allKeywords,
                    cv.Title,
                    link.ContentDocumentId
                );

                System.debug('STEP 7 — Results built => ' + fileResults.size() + ' record(s) for file: ' + cv.Title);

                for (OCR_Doc_Result__c r : fileResults) {
                    r.OCR_Doc__c = ocrDocId;
                    System.debug('STEP 7 — Result: Dept=' + r.Matched_Department__c
                        + ' | Relevant=' + r.Is_Relevant__c
                        + ' | Confidence=' + r.Confidence_Score__c
                        + ' | Keywords=' + r.Matched_Keywords__c);
                }

                resultsToInsert.addAll(fileResults);
            }

            System.debug('----------------------------------------');

            // Step 8 — Insert all results
            System.debug('STEP 8 — Total results to insert => ' + resultsToInsert.size());

            if (!resultsToInsert.isEmpty()) {
                insert resultsToInsert;
                System.debug('STEP 8 — Successfully inserted ' + resultsToInsert.size() + ' result(s)');
            } else {
                System.debug('STEP 8 — Nothing to insert');
            }

        } catch (Exception e) {
            System.debug('========================================');
            System.debug('FATAL ERROR => ' + e.getMessage());
            System.debug('ERROR TYPE  => ' + e.getTypeName());
            System.debug('ERROR LINE  => ' + e.getLineNumber());
            System.debug('STACK TRACE => ' + e.getStackTraceString());
            System.debug('========================================');
        }

        System.debug('========================================');
        System.debug('OCR_Doc_ProcessorQueueable FINISHED');
        System.debug('========================================');
    }

    // ─── Dynamic Schema Builder ───────────────────────────────────────────────

    private String buildDynamicSchema(List<Tender_Key_words_Final__mdt> keywords) {
        System.debug('buildDynamicSchema — Building for ' + keywords.size() + ' department(s)');

        Map<String, Object> properties = new Map<String, Object>();

        for (Tender_Key_words_Final__mdt kw : keywords) {

            String prompt = String.isNotBlank(kw.Schema_Prompt__c)
                ? kw.Schema_Prompt__c
                : buildDefaultPrompt(kw);

            System.debug('buildDynamicSchema — Dept: ' + kw.Department__c + ' | Prompt source: '
                + (String.isNotBlank(kw.Schema_Prompt__c) ? 'Custom' : 'Default'));

            Map<String, Object> deptSchema = new Map<String, Object>{
                'type'        => 'object',
                'description' => prompt,
                'properties'  => new Map<String, Object>{

                    'is_relevant' => new Map<String, Object>{
                        'type'        => 'boolean',
                        'description' =>
                            'true if document is relevant to ' + kw.Department__c +
                            '. Must find at least one of these positive keywords: ' +
                            kw.Matched_Positive_Keywords__c
                    },

                    'is_excluded' => new Map<String, Object>{
                        'type'        => 'boolean',
                        'description' =>
                            'true if document contains any negative/exclusion keywords: ' +
                            (String.isNotBlank(kw.Matched_Negative_Keywords__c)
                                ? kw.Matched_Negative_Keywords__c
                                : 'none')
                    },

                    'matched_positive_keywords' => new Map<String, Object>{
                        'type'        => 'string',
                        'description' =>
                            'Comma separated list of positive keywords actually ' +
                            'found in document from this list: ' +
                            kw.Matched_Positive_Keywords__c
                    },

                    'matched_negative_keywords' => new Map<String, Object>{
                        'type'        => 'string',
                        'description' =>
                            'Comma separated list of negative keywords found in document, if any'
                    },

                    'confidence_score' => new Map<String, Object>{
                        'type'        => 'number',
                        'description' =>
                            'Score 0-100. Higher means more positive keywords matched. 0 if not relevant.'
                    },

                    'reason' => new Map<String, Object>{
                        'type'        => 'string',
                        'description' =>
                            'Brief explanation of why this document is or is not relevant to ' +
                            kw.Department__c
                    }
                }
            };

            properties.put(kw.DeveloperName, deptSchema);
        }

        Map<String, Object> fullSchema = new Map<String, Object>{
            'type'       => 'object',
            'properties' => properties
        };

        return JSON.serialize(fullSchema);
    }

    private String buildDefaultPrompt(Tender_Key_words_Final__mdt kw) {
        String prompt = 'Analyze if this document is related to ' + kw.Department__c + '. ';

        if (String.isNotBlank(kw.Matched_Positive_Keywords__c)) {
            prompt += 'Look for these keywords: ' + kw.Matched_Positive_Keywords__c + '. ';
        }

        if (String.isNotBlank(kw.Matched_Negative_Keywords__c)) {
            prompt += 'Exclude if document contains: ' + kw.Matched_Negative_Keywords__c + '.';
        }

        return prompt;
    }

    // ─── Document AI HTTP Call ────────────────────────────────────────────────

    private String callDocumentAI(ContentVersion cv, String schema) {
        String fileName = cv.Title +
            (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '');

        String mimeType  = getMimeType(fileName);
        String base64Data = EncodingUtil.base64Encode(cv.VersionData);

        System.debug('callDocumentAI — File: ' + fileName + ' | MimeType: ' + mimeType);
        System.debug('callDocumentAI — Base64 length: ' + base64Data.length());
        System.debug('callDocumentAI — Endpoint: ' + API_ENDPOINT);
        System.debug('callDocumentAI — Model: ' + ML_MODEL);

        Map<String, Object> requestBody = new Map<String, Object>{
            'mlModel'      => ML_MODEL,
            'schemaConfig' => schema,
            'files'        => new List<Object>{
                new Map<String, Object>{
                    'mimeType' => mimeType,
                    'data'     => base64Data
                }
            }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(API_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setTimeout(120000);
        req.setBody(JSON.serialize(requestBody));

        System.debug('callDocumentAI — Sending HTTP request...');

        HttpResponse res = new Http().send(req);

        System.debug('callDocumentAI — HTTP Status Code => ' + res.getStatusCode());
        System.debug('callDocumentAI — HTTP Status      => ' + res.getStatus());
        System.debug('callDocumentAI — Response Body    => ' + res.getBody());

        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            System.debug('callDocumentAI — SUCCESS');
            return res.getBody();
        }

        System.debug('callDocumentAI — FAILED with status: ' + res.getStatusCode());
        return null;
    }

    // ─── API Response Parser ──────────────────────────────────────────────────

    private Map<String, Object> parseApiResponse(String body) {
        System.debug('parseApiResponse — Parsing response...');

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(body);

        List<Object> dataList = (List<Object>) response.get('data');

        if (dataList == null || dataList.isEmpty()) {
            System.debug('parseApiResponse — ABORT: data list is empty or null');
            return null;
        }

        System.debug('parseApiResponse — data list size => ' + dataList.size());

        Map<String, Object> firstData = (Map<String, Object>) dataList[0];
        String rawData = (String) firstData.get('data');

        System.debug('parseApiResponse — raw data before clean => ' + rawData);

        // Clean HTML entities
        rawData = rawData
            .replace('&quot;', '"')
            .replace('&amp;',  '&')
            .replace('&lt;',   '<')
            .replace('&gt;',   '>')
            .replace('&#39;',  '\'')
            .replace('\\n',    '\n');

        System.debug('parseApiResponse — raw data after clean => ' + rawData);

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(rawData);

        System.debug('parseApiResponse — parsed keys => ' + parsed.keySet());

        // Unwrap value wrapper if present
        Map<String, Object> unwrapped = new Map<String, Object>();

        for (String key : parsed.keySet()) {
            Object val = parsed.get(key);

            if (val instanceof Map<String, Object>) {
                Map<String, Object> fieldMap = (Map<String, Object>) val;

                if (fieldMap.containsKey('value')) {
                    Object innerVal = fieldMap.get('value');
                    unwrapped.put(key, innerVal);
                    System.debug('parseApiResponse — Unwrapped key: ' + key + ' => ' + innerVal);
                } else {
                    unwrapped.put(key, val);
                    System.debug('parseApiResponse — Kept as-is key: ' + key);
                }
            } else {
                unwrapped.put(key, val);
                System.debug('parseApiResponse — Primitive key: ' + key + ' => ' + val);
            }
        }

        System.debug('parseApiResponse — Final unwrapped keys => ' + unwrapped.keySet());
        return unwrapped;
    }

    // ─── Result Builder ───────────────────────────────────────────────────────

    private List<OCR_Doc_Result__c> buildResults(
        Map<String, Object> aiResult,
        List<Tender_Key_words_Final__mdt> keywords,
        String fileName,
        Id contentDocumentId
    ) {
        System.debug('buildResults — Building results for file: ' + fileName);

        List<OCR_Doc_Result__c> results = new List<OCR_Doc_Result__c>();

        for (Tender_Key_words_Final__mdt kw : keywords) {
            System.debug('buildResults — Checking dept: ' + kw.Department__c
                + ' | Key: ' + kw.DeveloperName);

            Object deptObj = aiResult.get(kw.DeveloperName);

            if (deptObj == null) {
                System.debug('buildResults — SKIP: No AI result found for key: ' + kw.DeveloperName);
                continue;
            }

            Map<String, Object> deptResult = (Map<String, Object>) deptObj;

            Boolean isRelevant  = getBooleanValue(deptResult, 'is_relevant');
            Boolean isExcluded  = getBooleanValue(deptResult, 'is_excluded');
            Decimal confidence  = getDecimalValue(deptResult, 'confidence_score');
            String  matchedPos  = getStringValue(deptResult, 'matched_positive_keywords');
            String  matchedNeg  = getStringValue(deptResult, 'matched_negative_keywords');
            String  reason      = getStringValue(deptResult, 'reason');

            System.debug('buildResults — Dept: ' + kw.Department__c
                + ' | isRelevant: ' + isRelevant
                + ' | isExcluded: ' + isExcluded
                + ' | Confidence: ' + confidence
                + ' | MatchedPos: ' + matchedPos
                + ' | Reason: ' + reason);

            if (isRelevant == true && isExcluded == false) {
                System.debug('buildResults — MATCH FOUND for dept: ' + kw.Department__c);

                results.add(new OCR_Doc_Result__c(
                    File_Name__c           = fileName,
                    Matched_Department__c  = kw.Department__c,
                    Matched_Keywords__c    = matchedPos,
                    Confidence_Score__c    = confidence,
                    Is_Relevant__c         = true,
                    Is_Excluded__c         = false,
                    Status__c              = 'Processed',
                    Content_Document_Id__c = String.valueOf(contentDocumentId)
                ));
            } else {
                System.debug('buildResults — NO MATCH for dept: ' + kw.Department__c
                    + ' | isRelevant=' + isRelevant
                    + ' | isExcluded=' + isExcluded);
            }
        }

        // No match found — store as unmatched
        if (results.isEmpty()) {
            System.debug('buildResults — No departments matched. Storing as No Match Found.');
            results.add(new OCR_Doc_Result__c(
                File_Name__c           = fileName,
                Matched_Department__c  = 'No Match Found',
                Is_Relevant__c         = false,
                Is_Excluded__c         = false,
                Status__c              = 'Processed',
                Confidence_Score__c    = 0,
                Content_Document_Id__c = String.valueOf(contentDocumentId)
            ));
        }

        System.debug('buildResults — Returning ' + results.size() + ' result(s)');
        return results;
    }

    // ─── Helper Methods ───────────────────────────────────────────────────────

    // private Boolean getBooleanValue(Map<String, Object> data, String key) {
    //     try {
    //         Object val = data.get(key);
    //         if (val == null) return false;
    //         if (val instanceof Boolean) return (Boolean) val;
    //         return Boolean.valueOf(String.valueOf(val));
    //     } catch (Exception e) {
    //         System.debug('getBooleanValue — ERROR for key: ' + key + ' => ' + e.getMessage());
    //         return false;
    //     }
    // }
    private Boolean getBooleanValue(Map<String, Object> data, String key) {

    Object val = data.get(key);

    if(val == null){
        return false;
    }

    if(val instanceof Map<String,Object>){

        Map<String,Object> wrapper =
            (Map<String,Object>)val;

        val = wrapper.get('value');
    }

    if(val == null){
        return false;
    }

    return Boolean.valueOf(String.valueOf(val));
}

    private Decimal getDecimalValue(Map<String, Object> data, String key) {
        try {
            Object val = data.get(key);
            if (val == null) return 0;
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            System.debug('getDecimalValue — ERROR for key: ' + key + ' => ' + e.getMessage());
            return 0;
        }
    }

    private String getStringValue(Map<String, Object> data, String key) {
        try {
            Object val = data.get(key);
            return val == null ? '' : String.valueOf(val);
        } catch (Exception e) {
            System.debug('getStringValue — ERROR for key: ' + key + ' => ' + e.getMessage());
            return '';
        }
    }

    private String getMimeType(String name) {
        String lower = name.toLowerCase();
        if (lower.endsWith('.pdf'))                            return 'application/pdf';
        if (lower.endsWith('.png'))                            return 'image/png';
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
        return 'application/octet-stream';
    }
}