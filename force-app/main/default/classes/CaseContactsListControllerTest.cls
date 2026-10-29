@IsTest
private class CaseContactsListControllerTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(LastName = 'Tester', AccountId = acc.Id, Email = 'tester@example.com');
        insert con;

        Case c = new Case(Subject = 'Test Case', Status = 'New', Origin = 'Email');
        insert c;

        List<Case_Contacts__c> junctions = new List<Case_Contacts__c>();
        for (Integer i = 0; i < 5; i++) {
            junctions.add(new Case_Contacts__c(Case__c = c.Id, Contact__c = con.Id));
        }
        insert junctions;
    }

    @IsTest
    static void returnsAllContactsForCase() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        List<CaseContactsListController.CaseContactWrapper> result =
            CaseContactsListController.getCaseContacts(c.Id);
        Test.stopTest();

        Assert.areEqual(5, result.size(), 'All case contacts should be returned');
        Assert.isNotNull(result[0].recordId, 'Record Id should be populated');
        Assert.isNotNull(result[0].name, 'Name should be populated');
    }

    @IsTest
    static void returnsEmptyListWhenCaseIdIsNull() {
        Test.startTest();
        List<CaseContactsListController.CaseContactWrapper> result =
            CaseContactsListController.getCaseContacts(null);
        Test.stopTest();

        Assert.isTrue(result.isEmpty(), 'Null Case Id should return an empty list');
    }
}