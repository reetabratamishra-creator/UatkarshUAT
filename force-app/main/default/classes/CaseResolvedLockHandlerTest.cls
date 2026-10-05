@isTest
private class CaseResolvedLockHandlerTest {

    private static final String RESOLVED_STATUS = 'Resolved';

    // ------------------------------------------------------------------
    // Test data helpers
    // ------------------------------------------------------------------

    /**
     * Creates and inserts a test User with the given Profile name.
     * Falls back gracefully with an assertion failure message if the
     * profile does not exist in this org, rather than an opaque DML error.
     */
    private static User createUserWithProfile(String profileName, String uniqueKey) {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        System.assert(!profiles.isEmpty(), 'Expected a Profile named "' + profileName + '" to exist in this org.');

        String alias = ('t' + uniqueKey).length() > 8 ? ('t' + uniqueKey).substring(0, 8) : ('t' + uniqueKey);

        User u = new User(
            FirstName = 'Test',
            LastName = 'User_' + uniqueKey,
            Alias = alias,
            Email = 'test.' + uniqueKey + '@example.com.invalid',
            Username = 'test.' + uniqueKey + System.currentTimeMillis() + '@example.com.invalid',
            ProfileId = profiles[0].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        return u;
    }

    /**
     * Inserts a Case with the given Status and returns it (with Id populated).
     */
    private static Case createCase(String status) {
        Case c = new Case(
            Status = status,
            Subject = 'Test Case - ' + status,
            Origin = 'Web'
        );
        insert c;
        return c;
    }

    // ------------------------------------------------------------------
    // Guard clause: null / empty inputs should exit quietly, no exception
    // ------------------------------------------------------------------

    @isTest
    static void testHandleBeforeUpdate_NullAndEmptyInputs_NoException() {
        Test.startTest();
        // null newCases
        CaseResolvedLockHandler.handleBeforeUpdate(null, new Map<Id, Case>());
        // empty newCases
        CaseResolvedLockHandler.handleBeforeUpdate(new List<Case>(), new Map<Id, Case>());
        // null oldCasesById
        Case dummy = new Case(Status = 'New');
        CaseResolvedLockHandler.handleBeforeUpdate(new List<Case>{ dummy }, null);
        Test.stopTest();

        System.assert(!dummy.hasErrors(), 'No error should be added when guard clauses short-circuit.');
    }

    // ------------------------------------------------------------------
    // Non-admin editing a previously Resolved case -> should be BLOCKED
    // ------------------------------------------------------------------

    @isTest
    static void testBlocksEdit_WhenPreviouslyResolved_AndNotAdmin() {
        Case c = createCase(RESOLVED_STATUS);

        // Snapshot representing the "old" version (previously Resolved)
        Map<Id, Case> oldMap = new Map<Id, Case>{
            c.Id => new Case(Id = c.Id, Status = RESOLVED_STATUS)
        };

        // "new" version attempting to change Status away from Resolved
        Case newVersion = new Case(Id = c.Id, Status = 'Closed');
        List<Case> newList = new List<Case>{ newVersion };

        User standardUser = createUserWithProfile('Standard User', 'std1');

        Test.startTest();
        System.runAs(standardUser) {
            CaseResolvedLockHandler.handleBeforeUpdate(newList, oldMap);
        }
        Test.stopTest();

        System.assert(newVersion.hasErrors(), 'Expected an error on a Case that was previously Resolved, edited by a non-admin.');
    }

    // ------------------------------------------------------------------
    // Admin editing a previously Resolved case -> should be ALLOWED
    // ------------------------------------------------------------------

    @isTest
    static void testAllowsEdit_WhenPreviouslyResolved_AndAdminProfile() {
        Case c = createCase(RESOLVED_STATUS);

        Map<Id, Case> oldMap = new Map<Id, Case>{
            c.Id => new Case(Id = c.Id, Status = RESOLVED_STATUS)
        };

        Case newVersion = new Case(Id = c.Id, Status = 'Closed');
        List<Case> newList = new List<Case>{ newVersion };

        User adminUser = createUserWithProfile('System Administrator', 'adm1');

        Test.startTest();
        System.runAs(adminUser) {
            CaseResolvedLockHandler.handleBeforeUpdate(newList, oldMap);
        }
        Test.stopTest();

        System.assert(!newVersion.hasErrors(), 'System Administrator should be exempt from the resolved-case lock.');
    }

    // ------------------------------------------------------------------
    // Non-admin editing a case that was NOT previously Resolved -> ALLOWED
    // ------------------------------------------------------------------

    @isTest
    static void testAllowsEdit_WhenNotPreviouslyResolved() {
        Case c = createCase('New');

        Map<Id, Case> oldMap = new Map<Id, Case>{
            c.Id => new Case(Id = c.Id, Status = 'New')
        };

        Case newVersion = new Case(Id = c.Id, Status = 'Working');
        List<Case> newList = new List<Case>{ newVersion };

        User standardUser = createUserWithProfile('Standard User', 'std2');

        Test.startTest();
        System.runAs(standardUser) {
            CaseResolvedLockHandler.handleBeforeUpdate(newList, oldMap);
        }
        Test.stopTest();

        System.assert(!newVersion.hasErrors(), 'Case not previously Resolved should be editable by a non-admin.');
    }

    // ------------------------------------------------------------------
    // Case Id not present in oldCasesById -> previous is null -> ALLOWED
    // ------------------------------------------------------------------

    @isTest
    static void testAllowsEdit_WhenPreviousVersionIsNull() {
        Case c = createCase('New');

        // Intentionally empty map so oldCasesById.get(c.Id) returns null
        Map<Id, Case> oldMap = new Map<Id, Case>();

        Case newVersion = new Case(Id = c.Id, Status = 'Working');
        List<Case> newList = new List<Case>{ newVersion };

        User standardUser = createUserWithProfile('Standard User', 'std3');

        Test.startTest();
        System.runAs(standardUser) {
            CaseResolvedLockHandler.handleBeforeUpdate(newList, oldMap);
        }
        Test.stopTest();

        System.assert(!newVersion.hasErrors(), 'A null previous version should not trigger the lock.');
    }

    // ------------------------------------------------------------------
    // Bulk test: mix of blocked and allowed records in a single call
    // ------------------------------------------------------------------

    @isTest
    static void testBulk_MixOfResolvedAndOpenCases() {
        Case resolvedCase = createCase(RESOLVED_STATUS);
        Case openCase = createCase('New');

        Map<Id, Case> oldMap = new Map<Id, Case>{
            resolvedCase.Id => new Case(Id = resolvedCase.Id, Status = RESOLVED_STATUS),
            openCase.Id => new Case(Id = openCase.Id, Status = 'New')
        };

        Case newResolved = new Case(Id = resolvedCase.Id, Status = 'Closed');
        Case newOpen = new Case(Id = openCase.Id, Status = 'Working');
        List<Case> newList = new List<Case>{ newResolved, newOpen };

        User standardUser = createUserWithProfile('Standard User', 'std4');

        Test.startTest();
        System.runAs(standardUser) {
            CaseResolvedLockHandler.handleBeforeUpdate(newList, oldMap);
        }
        Test.stopTest();

        System.assert(newResolved.hasErrors(), 'Previously Resolved case should be blocked for a non-admin.');
        System.assert(!newOpen.hasErrors(), 'Previously open case should remain editable.');
    }
}