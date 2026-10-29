public with sharing class CaseContactsListController {

    
    private static final Integer MAX_RECORDS = 200;

    public class CaseContactWrapper {
        @AuraEnabled public Id recordId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String email { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<CaseContactWrapper> getCaseContacts(Id caseId) {
        List<CaseContactWrapper> result = new List<CaseContactWrapper>();
        if (caseId == null) {
            return result;
        }

      
        for (Case_Contacts__c cc : [
            SELECT Id, Name, Phone__c, Email__c
            FROM Case_Contacts__c
            WHERE Case__c = :caseId
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT :MAX_RECORDS
        ]) {
            CaseContactWrapper w = new CaseContactWrapper();
            w.recordId = cc.Id;
            w.name = cc.Name;
            w.phone = cc.Phone__c;
            w.email = cc.Email__c;
            result.add(w);
        }
        return result;
    }
}