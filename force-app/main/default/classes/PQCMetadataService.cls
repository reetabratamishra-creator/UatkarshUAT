// ============================================================
// CLASS — PQCMetadataService.cls  (UPDATED)
// ─────────────────────────────────────────────────────────────
// PURPOSE:
//   Reads all PQC_Details__mdt custom metadata records and
//   builds the PQC checklist prompt string to send to Gemini
//   for Pre-Qualification Criteria analysis.
//
// METHODS:
//   getAllPQCs()
//     → Queries all PQC_Details__mdt records.
//       Returns list of PQCConfig objects.
//
//   buildPQCPrompt(pqcList)
//     → Builds a formatted prompt string from the PQC list.
//       Returns blank string if list is empty.

// ============================================================
public with sharing class PQCMetadataService {

    public class PQCConfig {
        public String label;
        public String detailsToCheck;
    }

    // ─────────────────────────────────────────────────────────
    // Fetch all PQC metadata records
    // ─────────────────────────────────────────────────────────
    public static List<PQCConfig> getAllPQCs() {

        List<PQCConfig> pqcList = new List<PQCConfig>();

        List<PQC_Details__mdt> metadataList = [
            SELECT  Label,
                    Details_to_Check__c
            FROM    PQC_Details__mdt
            ORDER BY Label ASC
        ];

        System.debug('Total PQC Records Found: ' + metadataList.size());

        for (PQC_Details__mdt pqc : metadataList) {
            PQCConfig pc      = new PQCConfig();
            pc.label          = pqc.Label;
            pc.detailsToCheck = pqc.Details_to_Check__c;
            pqcList.add(pc);

            System.debug('Loaded PQC: ' + pc.label);
        }

        return pqcList;
    }

    // ─────────────────────────────────────────────────────────
    // Build the full PQC prompt string to send to Gemini─────
    public static String buildPQCPrompt(List<PQCConfig> pqcList) {

        // FIX: empty list guard
        if (pqcList == null || pqcList.isEmpty()) {
            System.debug('WARNING: buildPQCPrompt called with empty list. Returning blank.');
            return '';
        }

        String prompt = '';

        for (PQCConfig pc : pqcList) {

            //skip record entirely if label is null — avoids
            //      "--- PQC ITEM: null ---" in Gemini prompt
            if (String.isBlank(pc.label)) {
                System.debug('WARNING: Skipping PQCConfig with blank label.');
                continue;
            }

            // skip record if detailsToCheck is also blank —
            //      a PQC item with no details gives Gemini nothing
            //      to check and wastes prompt space
            if (String.isBlank(pc.detailsToCheck)) {
                System.debug('WARNING: Skipping PQC "' + pc.label
                    + '" — detailsToCheck is blank.');
                continue;
            }

            prompt += '\n--- PQC ITEM: ' + pc.label + ' ---\n';
            prompt += 'Details to Check:\n' + pc.detailsToCheck + '\n';
        }

        // FIX: log warning if prompt is very large — heap safety indicator
        System.debug('Built PQC Prompt Length: ' + prompt.length() + ' chars');
        if (prompt.length() > 100000) {
            System.debug('WARNING: PQC prompt exceeds 100,000 chars. '
                + 'Risk of heap pressure or Gemini input limit.');
        }

        return prompt;
    }
}