@isTest
private class CaseTriggerTest {
    @isTest
    static void testCreatorSharing() {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name LIKE 'Standard User%'
            LIMIT 1
        ];
        String uniqueToken = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User testOwner = new User(
            Alias = ('to' + uniqueToken).left(8),
            Email = 'testowner+' + uniqueToken + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestingOwner ' + uniqueToken,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testownerCaseShare' + uniqueToken + '@example.com'
        );
        insert as system testOwner;

        Case c = new Case(
            Subject = 'Test Case Creator Share ' + uniqueToken,
            Status = 'Open',
            OwnerId = testOwner.Id,
            RecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
                .get('Case')
                .getRecordTypeId()
        );
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.assignmentRuleHeader.useDefaultRule = false;
        dmlOptions.DuplicateRuleHeader.AllowSave = true;
        c.setOptions(dmlOptions);

        Test.startTest();
        insert as system c;
        Test.stopTest();

        c = [SELECT Id, OwnerId, CreatedById FROM Case WHERE Id = :c.Id];
        System.assertNotEquals(null, c.Id);

        List<CaseShare> shares = [
            SELECT UserOrGroupId, CaseAccessLevel, RowCause
            FROM CaseShare
            WHERE CaseId = :c.Id AND UserOrGroupId = :c.CreatedById
        ];

        String caseSharingModel = [
            SELECT InternalSharingModel
            FROM EntityDefinition
            WHERE QualifiedApiName = 'Case'
            LIMIT 1
        ]
        .InternalSharingModel;

        Boolean defaultAccessAlreadyEdit =
            caseSharingModel == 'ReadWrite' || caseSharingModel == 'FullAccess';

        if (c.OwnerId != c.CreatedById && !defaultAccessAlreadyEdit) {
            System.assert(
                !shares.isEmpty(),
                'A CaseShare record should have been created for the creator'
            );
            System.assertEquals(
                'Edit',
                shares[0].CaseAccessLevel,
                'The CaseShare access level should be Edit'
            );
        } else {
            System.assertNotEquals(null, c.OwnerId);
        }
    }
}