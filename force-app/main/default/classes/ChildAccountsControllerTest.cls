@IsTest
private class ChildAccountsControllerTest {

    @TestSetup
    static void createTestData() {

        Account parentAccount = new Account(
            Name = 'Test Parent Account'
        );
        insert parentAccount;

        Account site1 = new Account(
            Name = 'Site A',
            ParentId = parentAccount.Id,
            Phone = '1111111111',
            Email__c = 'sitea@test.com'
        );

        Account site2 = new Account(
            Name = 'Site B',
            ParentId = parentAccount.Id,
            Phone = '2222222222',
            Email__c = 'siteb@test.com'
        );

        Account site3 = new Account(
            Name = 'Site C',
            ParentId = parentAccount.Id,
            Phone = '3333333333',
            Email__c = 'sitec@test.com'
        );

        Account unrelatedAccount = new Account(
            Name = 'Unrelated Account'
        );

        insert new List<Account>{
            site1,
            site2,
            site3,
            unrelatedAccount
        };
    }

    @IsTest
    static void testGetChildAccounts() {

        Account parentAccount = [
            SELECT Id, Name
            FROM Account
            WHERE Name = 'Test Parent Account'
            LIMIT 1
        ];

        Test.startTest();

        List<ChildAccountsController.ChildAccountWrapper> results =
            ChildAccountsController.getChildAccounts(parentAccount.Id);

        Test.stopTest();

        System.assertEquals(
            3,
            results.size(),
            'The parent Account should return exactly 3 child Sites.'
        );

        System.assertEquals(
            'Site A',
            results[0].name,
            'Sites should be returned in Name ascending order.'
        );

        System.assertEquals(
            'Site B',
            results[1].name,
            'Sites should be returned in Name ascending order.'
        );

        System.assertEquals(
            'Site C',
            results[2].name,
            'Sites should be returned in Name ascending order.'
        );

        System.assertEquals(
            'sitea@test.com',
            results[0].email
        );

        System.assertEquals(
            '1111111111',
            results[0].phone
        );

        System.assertNotEquals(
            parentAccount.Id,
            results[0].accountId,
            'The parent Account itself must not be returned.'
        );

        System.assertEquals(
            '/' + results[0].accountId,
            results[0].accountUrl,
            'Account URL should point to the Site record.'
        );
    }

    @IsTest
    static void testNoChildAccounts() {

        Account accountWithoutChildren = [
            SELECT Id
            FROM Account
            WHERE Name = 'Unrelated Account'
            LIMIT 1
        ];

        Test.startTest();

        List<ChildAccountsController.ChildAccountWrapper> results =
            ChildAccountsController.getChildAccounts(
                accountWithoutChildren.Id
            );

        Test.stopTest();

        System.assertEquals(
            0,
            results.size(),
            'An Account without child Sites should return an empty list.'
        );
    }

    @IsTest
    static void testNullRecordId() {

        Test.startTest();

        List<ChildAccountsController.ChildAccountWrapper> results =
            ChildAccountsController.getChildAccounts(null);

        Test.stopTest();

        System.assertEquals(
            0,
            results.size(),
            'Null recordId should return an empty list.'
        );
    }
}