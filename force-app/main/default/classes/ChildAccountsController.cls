/**
 * ChildAccountsController
 * Server side for the childAccountsRelatedList LWC.
 *
 * Returns all child Accounts (Sites) whose ParentId is the Account
 * on which the component is placed.
 *
 * Read-only, so this runs WITH USER_MODE. Object permissions,
 * field-level security and sharing are enforced automatically.
 */
public with sharing class ChildAccountsController {

    public class ChildAccountWrapper {
        @AuraEnabled public Id accountId      { get; set; }
        @AuraEnabled public String name       { get; set; }
        @AuraEnabled public String email      { get; set; }
        @AuraEnabled public String phone      { get; set; }
        @AuraEnabled public String accountUrl { get; set; }
    }

    /**
     * @param recordId Id of the Parent Account on which the component
     *                 is placed.
     *
     * @return List of child Accounts (Sites).
     */
    @AuraEnabled(cacheable=true)
    public static List<ChildAccountWrapper> getChildAccounts(Id recordId) {

        List<ChildAccountWrapper> results = new List<ChildAccountWrapper>();

        if (recordId == null) {
            return results;
        }

        for (Account acc : [
            SELECT Id, Name, Email__c, Phone
            FROM Account
            WHERE ParentId = :recordId
            WITH USER_MODE
            ORDER BY Name
            LIMIT 2000
        ]) {
            ChildAccountWrapper wrapper = new ChildAccountWrapper();

            wrapper.accountId  = acc.Id;
            wrapper.name       = acc.Name;
            wrapper.email      = acc.Email__c;
            wrapper.phone      = acc.Phone;
            wrapper.accountUrl = '/' + acc.Id;

            results.add(wrapper);
        }

        return results;
    }
}