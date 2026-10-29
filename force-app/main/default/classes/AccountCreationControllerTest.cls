@isTest
private class AccountCreationControllerTest {

    private static User createAllowedUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniq = String.valueOf(Crypto.getRandomInteger()).right(6);
        User u = new User(
            FirstName = 'Test',
            LastName = 'AccountCreation' + uniq,
            Alias = 'tac' + uniq.left(3),
            Email = 'tac' + uniq + '@example.com.test',
            Username = 'tac' + uniq + '@example.com.test',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id,
            Departments__c = 'HDPE_Pipe_Department;Solar_Structure_Department'
        );
        insert u;
        return u;
    }

    @isTest
    static void testGetInitData_AllowedProfile() {
        User u = createAllowedUser();

        AccountCreationController.InitData result;
        System.runAs(u) {
            Test.startTest();
            result = AccountCreationController.getInitData();
            Test.stopTest();
        }

        System.assertEquals(true, result.isAllowed, 'System Administrator should be an allowed profile.');
        System.assertEquals(true, result.isAdmin, 'System Administrator should be treated as admin.');
        System.assert(!result.recordTypeOptions.isEmpty(), 'Record type options should not be empty.');
        System.assert(!result.accountSourceOptions.isEmpty(), 'Admin should get the full AccountSource picklist.');
        System.assert(!result.departmentOptions.isEmpty(), 'Admin should get the full Department picklist regardless of Departments__c.');
        System.assertNotEquals(null, result.dealerRecordTypeId, 'Dealer record type should resolve.');
    }

    @isTest
    static void testCreateAccount_NewContact_Success() {
        User u = createAllowedUser();
        Id accountRtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' LIMIT 1].Id;

        AccountCreationController.AccountCreationRequest req = new AccountCreationController.AccountCreationRequest();
        req.recordTypeId = accountRtId;
        req.accountName = 'Test Account Co';
        req.isChildAccount = false;
        req.accountSource = 'TENDER';
        req.industry = 'Manufacturing';
        req.departmentName = 'Steel Pipes';
        req.phone = '9876543210';
        req.email = 'account@example.com';
        req.website = 'www.example.com';
        req.pan = 'ABCDE1234F';
        req.gstin = '29ABCDE1234F1Z5';
        req.useExistingContact = false;
        req.contactFirstName = 'John';
        req.contactLastName = 'Doe';
        req.contactEmail = 'john.doe@example.com';
        req.contactPhone = '9988776655';

        AccountCreationController.AddressInput addr = new AccountCreationController.AddressInput();
        addr.street = '123 Main St';
        addr.city = 'Kolkata';
        addr.pin = '700001';
        addr.country = 'India';
        addr.state = 'West Bengal';
        addr.zone = 'East';
        req.primaryAddress = addr;
        req.additionalAddresses = new List<AccountCreationController.AddressInput>();

        AccountCreationController.CreationResult result;
        System.runAs(u) {
            Test.startTest();
            result = AccountCreationController.createAccount(req);
            Test.stopTest();
        }

        System.assertNotEquals(null, result.accountId);
        System.assertNotEquals(null, result.contactId);

        Account created = [SELECT Id, Name, Department_Name__c FROM Account WHERE Id = :result.accountId];
        System.assertEquals('Test Account Co', created.Name);
        System.assertEquals('Steel Pipes', created.Department_Name__c);

        Contact con = [SELECT Id, LastName, AccountId FROM Contact WHERE Id = :result.contactId];
        System.assertEquals('Doe', con.LastName);
        System.assertEquals(result.accountId, con.AccountId);

        List<Address_Book__c> addresses = [SELECT Id, Account__c FROM Address_Book__c WHERE Account__c = :result.accountId];
        System.assertEquals(1, addresses.size());
    }

    @isTest
    static void testCreateAccount_ExistingContact_And_AdditionalAddress() {
        User u = createAllowedUser();
        Id accountRtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' LIMIT 1].Id;

        Account seedAccount = new Account(Name = 'Seed Account');
        insert seedAccount;
        Contact existingContact = new Contact(FirstName = 'Jane', LastName = 'Existing', Email = 'jane@example.com', AccountId = seedAccount.Id);
        insert existingContact;

        AccountCreationController.AccountCreationRequest req = new AccountCreationController.AccountCreationRequest();
        req.recordTypeId = accountRtId;
        req.accountName = 'Another Test Account';
        req.isChildAccount = false;
        req.accountSource = 'TENDER';
        req.industry = 'Manufacturing';
        req.departmentName = 'HDPE';
        req.phone = '9876543210';
        req.email = 'account2@example.com';
        req.useExistingContact = true;
        req.existingContactId = existingContact.Id;

        AccountCreationController.AddressInput addr = new AccountCreationController.AddressInput();
        addr.street = '123 Main St';
        addr.city = 'Kolkata';
        addr.pin = '700001';
        addr.country = 'India';
        req.primaryAddress = addr;

        AccountCreationController.AddressInput addl = new AccountCreationController.AddressInput();
        addl.street = '456 Second St';
        addl.city = 'Howrah';
        addl.pin = '711101';
        addl.country = 'India';
        req.additionalAddresses = new List<AccountCreationController.AddressInput>{ addl };

        AccountCreationController.CreationResult result;
        System.runAs(u) {
            Test.startTest();
            result = AccountCreationController.createAccount(req);
            Test.stopTest();
        }

        Contact updatedContact = [SELECT Id, AccountId FROM Contact WHERE Id = :existingContact.Id];
        System.assertEquals(result.accountId, updatedContact.AccountId, 'Existing contact should be relinked to the new Account.');

        List<Address_Book__c> addresses = [SELECT Id FROM Address_Book__c WHERE Account__c = :result.accountId];
        System.assertEquals(2, addresses.size(), 'Both primary and additional address should be created.');
    }

    @isTest
    static void testCreateAccount_ValidationBranches() {
        User u = createAllowedUser();
        Id accountRtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' LIMIT 1].Id;

        AccountCreationController.AddressInput goodAddress = new AccountCreationController.AddressInput();
        goodAddress.street = '123 Main St';
        goodAddress.city = 'Kolkata';
        goodAddress.pin = '700001';
        goodAddress.country = 'India';

        System.runAs(u) {
            Test.startTest();

            // missing Record Type / Account Name
            try {
                AccountCreationController.createAccount(new AccountCreationController.AccountCreationRequest());
                System.assert(false, 'Expected exception for missing required fields.');
            } catch (AuraHandledException ex) { /* expected */ }

            // invalid PAN
            AccountCreationController.AccountCreationRequest reqPan = baseRequest(accountRtId, goodAddress);
            reqPan.pan = 'INVALID';
            try {
                AccountCreationController.createAccount(reqPan);
                System.assert(false, 'Expected exception for invalid PAN.');
            } catch (AuraHandledException ex) { /* expected */ }

            // invalid GSTIN
            AccountCreationController.AccountCreationRequest reqGstin = baseRequest(accountRtId, goodAddress);
            reqGstin.gstin = 'INVALID';
            try {
                AccountCreationController.createAccount(reqGstin);
                System.assert(false, 'Expected exception for invalid GSTIN.');
            } catch (AuraHandledException ex) { /* expected */ }

            // invalid website
            AccountCreationController.AccountCreationRequest reqWeb = baseRequest(accountRtId, goodAddress);
            reqWeb.website = 'not a url';
            try {
                AccountCreationController.createAccount(reqWeb);
                System.assert(false, 'Expected exception for invalid website.');
            } catch (AuraHandledException ex) { /* expected */ }

            // incomplete primary address
            AccountCreationController.AccountCreationRequest reqAddr = baseRequest(accountRtId, goodAddress);
            reqAddr.primaryAddress = new AccountCreationController.AddressInput();
            try {
                AccountCreationController.createAccount(reqAddr);
                System.assert(false, 'Expected exception for incomplete address.');
            } catch (AuraHandledException ex) { /* expected */ }

            // existing contact flag set but no Id supplied
            AccountCreationController.AccountCreationRequest reqNoContact = baseRequest(accountRtId, goodAddress);
            reqNoContact.useExistingContact = true;
            reqNoContact.existingContactId = null;
            try {
                AccountCreationController.createAccount(reqNoContact);
                System.assert(false, 'Expected exception for missing existing Contact selection.');
            } catch (AuraHandledException ex) { /* expected */ }

            // new contact missing required fields
            AccountCreationController.AccountCreationRequest reqNewContact = baseRequest(accountRtId, goodAddress);
            reqNewContact.useExistingContact = false;
            reqNewContact.contactLastName = null;
            reqNewContact.contactEmail = null;
            try {
                AccountCreationController.createAccount(reqNewContact);
                System.assert(false, 'Expected exception for missing new Contact fields.');
            } catch (AuraHandledException ex) { /* expected */ }

            Test.stopTest();
        }
    }

    private static AccountCreationController.AccountCreationRequest baseRequest(Id accountRtId, AccountCreationController.AddressInput address) {
        AccountCreationController.AccountCreationRequest req = new AccountCreationController.AccountCreationRequest();
        req.recordTypeId = accountRtId;
        req.accountName = 'Validation Test Co';
        req.accountSource = 'TENDER';
        req.industry = 'Manufacturing';
        req.departmentName = 'Steel Pipes';
        req.phone = '9876543210';
        req.email = 'valid@example.com';
        req.useExistingContact = false;
        req.contactLastName = 'Doe';
        req.contactEmail = 'john.doe@example.com';
        req.primaryAddress = address;
        return req;
    }

    @isTest
    static void testCreateAccount_InvalidEmail_Throws() {
        User u = createAllowedUser();
        Id accountRtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' LIMIT 1].Id;

        AccountCreationController.AccountCreationRequest req = new AccountCreationController.AccountCreationRequest();
        req.recordTypeId = accountRtId;
        req.accountName = 'Bad Email Co';
        req.email = 'not-an-email';
        req.useExistingContact = false;
        req.contactLastName = 'Doe';
        req.contactEmail = 'john.doe@example.com';

        AccountCreationController.AddressInput addr = new AccountCreationController.AddressInput();
        addr.street = '123 Main St';
        addr.city = 'Kolkata';
        addr.pin = '700001';
        addr.country = 'India';
        req.primaryAddress = addr;

        Boolean threw = false;
        System.runAs(u) {
            Test.startTest();
            try {
                AccountCreationController.createAccount(req);
            } catch (AuraHandledException ex) {
                threw = true;
            }
            Test.stopTest();
        }
        System.assertEquals(true, threw, 'Invalid email should raise an AuraHandledException.');
    }

    @isTest
    static void testCreateAccount_DealerMultiDepartment() {
        User u = createAllowedUser();
        List<RecordType> dealerRts = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Dealer' LIMIT 1];
        if (dealerRts.isEmpty()) {
            return; // Dealer record type not present in this org context
        }

        AccountCreationController.AccountCreationRequest req = new AccountCreationController.AccountCreationRequest();
        req.recordTypeId = dealerRts[0].Id;
        req.accountName = 'Dealer Account Co';
        req.accountSource = 'TENDER';
        req.industry = 'Manufacturing';
        req.departmentNameMultiSelect = 'HDPE;Solar Structure';
        req.phone = '9876543210';
        req.email = 'dealer@example.com';
        req.useExistingContact = false;
        req.contactLastName = 'DealerContact';
        req.contactEmail = 'dealer.contact@example.com';

        AccountCreationController.AddressInput addr = new AccountCreationController.AddressInput();
        addr.street = '123 Main St';
        addr.city = 'Kolkata';
        addr.pin = '700001';
        addr.country = 'India';
        req.primaryAddress = addr;

        AccountCreationController.CreationResult result;
        System.runAs(u) {
            Test.startTest();
            result = AccountCreationController.createAccount(req);
            Test.stopTest();
        }

        Account created = [SELECT Id, Department_Name_MultiSelect__c FROM Account WHERE Id = :result.accountId];
        System.assertEquals('HDPE;Solar Structure', created.Department_Name_MultiSelect__c);
    }
}