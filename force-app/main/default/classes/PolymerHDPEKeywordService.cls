public with sharing class PolymerHDPEKeywordService {

    // Custom Metadata DeveloperNames (Custom Metadata Record Name) as seen in
    // Setup -> Custom Metadata Types -> Tender Key words For Polymer & HDPE.
    private static final String DEV_NAME_POLYMER = 'Polymer_Relevant';
    private static final String DEV_NAME_HDPE    = 'HDPE_Relevant';

    // Small data holder returned per keyword config record.
    public class KeywordConfig {
        public String  label;             // MasterLabel, e.g. "Polymer - Relevant" - for display/debug only
        public String  developerName;      // DeveloperName, e.g. "Polymer_Relevant"
        public String  department;         // Department__c - the actual value to write back, e.g. "Polymer" / "HDPE"
        public String  positiveKeywords;   // Matched_Positive_Keywords__c - used to build both the Prompt Builder input and the Gemini fallback prompt
        public String  negativeKeywords;   // Matched_Negative_Keywords__c - kept only for visibility/debug, NOT used in any matching logic anymore
        public String  schemaPrompt;       // Schema_Prompt__c - optional extra instruction text, still supported if populated
        public Boolean isRelevant;         // Is_Relevant__c - expected true for both records now
    }

    // ----------------------------------------------------------------------
    // METHOD: getPolymerKeywords
    // Loads the Polymer_Relevant and HDPE_Relevant custom metadata records
    // and returns them in a Map keyed by logical department name ("Polymer" /
    // "HDPE"), NOT by metadata Label. This is called ONCE per batch execution
    // (from PolymerHDPEBatch's constructor) and the resulting map is reused
    // for every Tender in every execute() chunk, to avoid repeated SOQL.
    // ----------------------------------------------------------------------
    public static Map<String, KeywordConfig> getPolymerKeywords() {
        Map<String, KeywordConfig> result = new Map<String, KeywordConfig>();

        List<Tender_Key_words_Final__mdt> mdtList = [
            SELECT Label, DeveloperName, Department__c,
                   Matched_Positive_Keywords__c, Matched_Negative_Keywords__c,
                   Schema_Prompt__c, Is_Excluded__c, Is_Relevant__c
            FROM Tender_Key_words_Final__mdt
            WHERE DeveloperName = :DEV_NAME_POLYMER
               OR DeveloperName = :DEV_NAME_HDPE
        ];

        for (Tender_Key_words_Final__mdt m : mdtList) {
            KeywordConfig kc     = new KeywordConfig();
            kc.label             = m.Label;
            kc.developerName     = m.DeveloperName;
            kc.department        = m.Department__c;
            kc.positiveKeywords  = m.Matched_Positive_Keywords__c;
            kc.negativeKeywords  = m.Matched_Negative_Keywords__c;
            kc.schemaPrompt      = m.Schema_Prompt__c;
            kc.isRelevant        = m.Is_Relevant__c;

            // Key the map by the ACTUAL department value from metadata
            // (falls back to DeveloperName-derived key only if Department__c
            // was left blank on the metadata record, so a config error never
            // silently disappears from the map).
            String mapKey = String.isNotBlank(m.Department__c)
                ? m.Department__c
                : m.DeveloperName;

            result.put(mapKey, kc);
        }

        System.debug('[PolymerHDPEKeywordService] Loaded ' + result.size()
                      + ' keyword config(s). Keys=' + result.keySet());
        return result;
    }
}