public with sharing class PolymerHDPEGeminiService {

    private static final String STAGE_NAME = 'PolymerHDPEFileCheck';

    // Result of analyzing ONE file against the Polymer/HDPE keyword configs.
    public class MatchResult {
        public String  matchedDepartment = null;   // "Polymer" / "HDPE" / null (no match)
        public String  reasoning         = '';
        public Boolean hadError          = false;
        public String  errorMessage      = '';
    }

    // ----------------------------------------------------------------------
    // METHOD: checkFile
    // Sends one downloaded file (as Blob) to Gemini along with a prompt built
    // from the Polymer and HDPE "Relevant" keyword configs, asks it to decide
    // which department (if any) the file belongs to, parses the JSON result,
    // and logs the outcome via IntegrationLogger before returning to caller.
    // tenderId is required purely for logging/traceability - it plays no
    // role in the actual Gemini call itself.
    // ----------------------------------------------------------------------
    public static MatchResult checkFile(
        Blob   fileBytes,
        String mimeType,
        String fileName,
        Id     tenderId,
        PolymerHDPEKeywordService.KeywordConfig polymerCfg,
        PolymerHDPEKeywordService.KeywordConfig hdpeCfg
    ) {
        MatchResult result = new MatchResult();
        Integer statusCode = null;
        String  rawResponseForLog = null;

        try {
            String prompt     = buildPrompt(fileName, polymerCfg, hdpeCfg);
            String base64Data = EncodingUtil.base64Encode(fileBytes);

            List<Object> parts = new List<Object>();
            parts.add(new Map<String, Object>{ 'text' => prompt });
            parts.add(new Map<String, Object>{
                'inline_data' => new Map<String, Object>{
                    'mime_type' => mimeType,
                    'data'      => base64Data
                }
            });

            Map<String, Object> body = new Map<String, Object>{
                'contents' => new List<Object>{
                    new Map<String, Object>{ 'parts' => parts }
                },
                'generationConfig' => new Map<String, Object>{
                    'temperature'      => 0.1,
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
            statusCode = res.getStatusCode();
            rawResponseForLog = res.getBody();

            System.debug('[PolymerHDPEGeminiService] status=' + statusCode + ' file=' + fileName);

            if (statusCode != 200) {
                result.hadError     = true;
                result.errorMessage = 'Gemini call failed - Status: ' + statusCode
                    + ' | Body: ' + (res.getBody() != null ? res.getBody().left(300) : '');

                IntegrationLogger.log(STAGE_NAME, result.errorMessage != null ? 'Gemini' : 'Gemini',
                    'gemini-2.5-flash:generateContent', prompt, rawResponseForLog,
                    statusCode, false, result.errorMessage, tenderId);
                return result;
            }

            String text = extractText(res.getBody());
            if (String.isBlank(text)) {
                result.hadError     = true;
                result.errorMessage = 'Empty/unreadable Gemini response for file: ' + fileName;

                IntegrationLogger.log(STAGE_NAME, 'Gemini', 'gemini-2.5-flash:generateContent',
                    prompt, rawResponseForLog, statusCode, false, result.errorMessage, tenderId);
                return result;
            }

            Map<String, Object> parsed;
            try {
                parsed = (Map<String, Object>) JSON.deserializeUntyped(text);
            } catch (Exception pe) {
                result.hadError     = true;
                result.errorMessage = 'Could not parse Gemini JSON for file "' + fileName + '": ' + pe.getMessage();

                IntegrationLogger.log(STAGE_NAME, 'Gemini', 'gemini-2.5-flash:generateContent',
                    prompt, rawResponseForLog, statusCode, false, result.errorMessage, tenderId);
                return result;
            }

            // matchedDepartment is expected to be "Polymer", "HDPE", or "None".
            String dept = parsed.containsKey('matchedDepartment')
                ? String.valueOf(parsed.get('matchedDepartment'))
                : null;

            if (dept == 'Polymer' || dept == 'HDPE') {
                result.matchedDepartment = dept;
            }
            result.reasoning = parsed.containsKey('reasoning') ? String.valueOf(parsed.get('reasoning')) : '';

            // Successful call - log it as success regardless of whether a
            // department was actually matched (a clean "None" is still a
            // successful, well-formed callout - only actual errors are
            // logged as failures).
            IntegrationLogger.log(STAGE_NAME, 'Gemini', 'gemini-2.5-flash:generateContent',
                prompt, rawResponseForLog, statusCode, true,
                (result.matchedDepartment == null ? 'No department matched for file: ' + fileName : null),
                tenderId);

        } catch (Exception e) {
            result.hadError     = true;
            result.errorMessage = 'Exception in checkFile for "' + fileName + '": ' + e.getMessage();
            System.debug('[PolymerHDPEGeminiService] ERROR: ' + e.getMessage() + ' | ' + e.getStackTraceString());

            IntegrationLogger.log(STAGE_NAME, 'Gemini', 'gemini-2.5-flash:generateContent',
                null, rawResponseForLog, statusCode, false, result.errorMessage, tenderId);
        }

        return result;
    }

    // ----------------------------------------------------------------------
    // METHOD: buildPrompt
    // Builds the Gemini prompt text for a single file. Checks Polymer
    // keywords FIRST (matching the same priority used in the Step 1 Prompt
    // Builder template) - only if Polymer does not match does it consider
    // HDPE. No "Excluded" criteria exist anymore.
    // ----------------------------------------------------------------------
    private static String buildPrompt(
        String fileName,
        PolymerHDPEKeywordService.KeywordConfig polymerCfg,
        PolymerHDPEKeywordService.KeywordConfig hdpeCfg
    ) {
        String prompt = 'You are a Tender Document Analyzer. Your ONLY task is to decide whether this document belongs to the "Polymer" department or the "HDPE" department, or neither.\n\n';
        prompt += 'File being analyzed: ' + fileName + '\n\n';

        prompt += '--- STEP 1: Check POLYMER keywords FIRST ---\n';
        if (polymerCfg != null && String.isNotBlank(polymerCfg.positiveKeywords)) {
            prompt += 'If ANY of these keywords/phrases are present in the document, matchedDepartment = "Polymer" and STOP (do not check HDPE): '
                + polymerCfg.positiveKeywords + '\n';
            if (String.isNotBlank(polymerCfg.schemaPrompt)) {
                prompt += 'Additional instruction: ' + polymerCfg.schemaPrompt + '\n';
            }
        } else {
            prompt += '(No Polymer keyword configuration available)\n';
        }

        prompt += '\n--- STEP 2: Only if Polymer did NOT match, check HDPE keywords ---\n';
        if (hdpeCfg != null && String.isNotBlank(hdpeCfg.positiveKeywords)) {
            prompt += 'If ANY of these keywords/phrases are present in the document, matchedDepartment = "HDPE": '
                + hdpeCfg.positiveKeywords + '\n';
            if (String.isNotBlank(hdpeCfg.schemaPrompt)) {
                prompt += 'Additional instruction: ' + hdpeCfg.schemaPrompt + '\n';
            }
        } else {
            prompt += '(No HDPE keyword configuration available)\n';
        }

        prompt += '\n--- STEP 3: If neither matched ---\n';
        prompt += 'Set matchedDepartment = "None".\n';

        prompt += '\nReturn ONLY a valid JSON object. No markdown. No explanation outside the JSON.\n\n';
        prompt += '{\n';
        prompt += '  "matchedDepartment": "Polymer" | "HDPE" | "None",\n';
        prompt += '  "reasoning": "<brief explanation - which specific keyword(s) or content led to this decision, or why neither matched>"\n';
        prompt += '}';

        return prompt;
    }

    // ----------------------------------------------------------------------
    // METHOD: extractText
    // Pulls the plain text out of Gemini's raw response envelope
    // (candidates[0].content.parts[0].text). Unchanged from before.
    // ----------------------------------------------------------------------
    private static String extractText(String responseBody) {
        try {
            Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> candidates  = (List<Object>) resp.get('candidates');
            if (candidates == null || candidates.isEmpty()) return null;

            Map<String, Object> firstCandidate = (Map<String, Object>) candidates[0];
            if (firstCandidate == null) return null;

            Map<String, Object> content = (Map<String, Object>) firstCandidate.get('content');
            if (content == null) return null;

            List<Object> parts = (List<Object>) content.get('parts');
            if (parts == null || parts.isEmpty()) return null;

            Map<String, Object> firstPart = (Map<String, Object>) parts[0];
            if (firstPart == null) return null;

            return (String) firstPart.get('text');

        } catch (Exception e) {
            System.debug('[PolymerHDPEGeminiService] extractText error: ' + e.getMessage());
            return null;
        }
    }
}