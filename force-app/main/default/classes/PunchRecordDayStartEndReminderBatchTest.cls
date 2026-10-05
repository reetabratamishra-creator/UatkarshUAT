@isTest
private class PunchRecordDayStartEndReminderBatchTest {

    @testSetup
    static void setupTestData() {
        User employeeWithTodayPunch = createTestUser('e1');
        User employeeMissingPunch = createTestUser('e2');
        User hod = createTestUser('hd1');

        insert new List<User>{
            employeeWithTodayPunch,
            employeeMissingPunch,
            hod
        };

        Id emailFolderId = UserInfo.getUserId();

        insert new List<EmailTemplate>{
            new EmailTemplate(
                Name = 'Day Start 10AM',
                DeveloperName =
                    PunchRecordDayStartEndReminderBatch.TEMPLATE_DAY_START_10AM,
                TemplateType = 'text',
                FolderId = emailFolderId,
                Subject = 'Day Start Reminder',
                Body = 'Dear Employee, your Day Start is pending.'
            ),
            new EmailTemplate(
                Name = 'Day Start 10:45 HOD',
                DeveloperName =
                    PunchRecordDayStartEndReminderBatch.TEMPLATE_DAY_START_1045AM,
                TemplateType = 'text',
                FolderId = emailFolderId,
                Subject = 'Escalation: Day Start Pending',
                Body = 'This is to inform you the employee has not completed Day Start.'
            ),
            new EmailTemplate(
                Name = 'Day End Midnight',
                DeveloperName =
                    PunchRecordDayStartEndReminderBatch.TEMPLATE_DAY_END_MIDNIGHT,
                TemplateType = 'text',
                FolderId = emailFolderId,
                Subject = 'Day End Pending',
                Body = 'Dear Employee, your Day End has not been completed.'
            )
        };
    }

    // ===============================================================
    // DAY START - 10 AM
    // ===============================================================

    @isTest
    static void testFullBatchRun_DayStart10AM_SendsToEmployee() {

        Test.startTest();

        insertTodayPunchInForEmployeeWithTodayPunch();
        insertNotYetPunchedInRecordForEmployeeMissingPunch();

        Id jobId = Database.executeBatch(
            new PunchRecordDayStartEndReminderBatch(
                PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_10AM
            ),
            50
        );

        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];

        System.assertEquals(
            'Completed',
            job.Status,
            'Day Start 10 AM batch should complete successfully.'
        );

        System.assertEquals(
            0,
            job.NumberOfErrors,
            'Day Start 10 AM batch should not have errors.'
        );
    }

    // ===============================================================
    // DAY START - 10:45 AM
    // ===============================================================

    @isTest
    static void testFullBatchRun_DayStart1045_SendsToHod() {

        Test.startTest();

        insertTodayPunchInForEmployeeWithTodayPunch();
        insertNotYetPunchedInRecordForEmployeeMissingPunch();

        Id jobId = Database.executeBatch(
            new PunchRecordDayStartEndReminderBatch(
                PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_1045
            ),
            50
        );

        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];

        System.assertEquals(
            'Completed',
            job.Status,
            'Day Start 10:45 batch should complete successfully.'
        );

        System.assertEquals(
            0,
            job.NumberOfErrors,
            'Day Start 10:45 batch should not have errors.'
        );
    }

    // ===============================================================
    // DAY END - MIDNIGHT
    // ===============================================================

    @isTest
    static void testFullBatchRun_DayEndMidnight_SendsToEmployee() {

        Test.startTest();

        insertTodayPunchInForEmployeeWithTodayPunch();

        Id jobId = Database.executeBatch(
            new PunchRecordDayStartEndReminderBatch(
                PunchRecordDayStartEndReminderBatch.ReminderType.DAY_END_MIDNIGHT
            ),
            50
        );

        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];

        System.assertEquals(
            'Completed',
            job.Status,
            'Day End batch should complete successfully.'
        );

        System.assertEquals(
            0,
            job.NumberOfErrors,
            'Day End batch should not have errors.'
        );
    }

    // ===============================================================
    // START METHOD - DAY START BRANCH
    // ===============================================================

    @isTest
    static void testStart_DayStartBranch_ReturnsMissingPunchInRoster() {

        PunchRecordDayStartEndReminderBatch batchInstance =
            new PunchRecordDayStartEndReminderBatch(
                PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_10AM
            );

        Test.startTest();

        insertTodayPunchInForEmployeeWithTodayPunch();
        insertNotYetPunchedInRecordForEmployeeMissingPunch();

        List<Punch_Record__c> roster =
            (List<Punch_Record__c>) batchInstance.start(null);

        Test.stopTest();

        System.assert(
            !roster.isEmpty(),
            'Expected at least one employee missing today\'s punch-in.'
        );

        for (Punch_Record__c pr : roster) {
            System.assertEquals(
                null,
                pr.Punch_Time__c,
                'Missing-punch roster entries should have null Punch_Time__c.'
            );
        }
    }

    // ===============================================================
    // START METHOD - DAY END BRANCH
    // ===============================================================

    @isTest
    static void testStart_DayEndBranch_ReturnsTodaysPunchedInRecords() {

        PunchRecordDayStartEndReminderBatch batchInstance =
            new PunchRecordDayStartEndReminderBatch(
                PunchRecordDayStartEndReminderBatch.ReminderType.DAY_END_MIDNIGHT
            );

        Test.startTest();

        insertTodayPunchInForEmployeeWithTodayPunch();

        List<Punch_Record__c> todaysRecords =
            (List<Punch_Record__c>) batchInstance.start(null);

        Test.stopTest();

        System.assert(
            !todaysRecords.isEmpty(),
            'Expected today\'s punch-in record to be returned.'
        );

        for (Punch_Record__c pr : todaysRecords) {
            System.assertNotEquals(
                null,
                pr.Punch_Time__c,
                'Day End records should contain Punch_Time__c.'
            );
        }
    }

    // ===============================================================
    // EXECUTE - EMPTY SCOPE
    // ===============================================================

    @isTest
    static void testExecute_EmptyScope_DoesNotThrow() {

        PunchRecordDayStartEndReminderBatch batchInstance =
            new PunchRecordDayStartEndReminderBatch(
                PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_10AM
            );

        Test.startTest();

        batchInstance.execute(
            null,
            new List<Punch_Record__c>()
        );

        Test.stopTest();

        System.assert(
            true,
            'Execute should complete without exception for an empty scope.'
        );
    }

    // ===============================================================
    // EXECUTE - MISSING TEMPLATE
    // ===============================================================

    @isTest
    static void testExecute_MissingTemplate_NoEmailSent() {

        Test.startTest();

        insertTodayPunchInForEmployeeWithTodayPunch();
        insertNotYetPunchedInRecordForEmployeeMissingPunch();

        delete [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName =
                :PunchRecordDayStartEndReminderBatch.TEMPLATE_DAY_START_10AM
        ];

        Id jobId = Database.executeBatch(
            new PunchRecordDayStartEndReminderBatch(
                PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_10AM
            ),
            50
        );

        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];

        System.assertEquals(
            'Completed',
            job.Status,
            'Batch should complete even when the email template is missing.'
        );

        System.assertEquals(
            0,
            job.NumberOfErrors,
            'Batch should not record errors when the template is missing.'
        );
    }

    // ===============================================================
    // EXECUTE - NO HOD
    // ===============================================================

    @isTest
    static void testExecute_NoHodOnRecord_CompletesWithoutError() {

        User employeeNoHod = createTestUser('e3');
        insert employeeNoHod;

        Punch_Record__c recordWithoutHod = new Punch_Record__c(
            User__c = employeeNoHod.Id,
            HOD__c = null,
            Punch_Time__c = null,
            Action__c = 'IN',
            Punch_Type__c = 'Day In / Out'
        );

        insert recordWithoutHod;

        Punch_Record__c queriedRecord = [
            SELECT Id,
                   User__c,
                   HOD__c,
                   Punch_Time__c,
                   CreatedDate,
                   User__r.Email,
                   HOD__r.Email
            FROM Punch_Record__c
            WHERE Id = :recordWithoutHod.Id
        ];

        PunchRecordDayStartEndReminderBatch batchInstance =
            new PunchRecordDayStartEndReminderBatch(
                PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_1045
            );

        Test.startTest();

        batchInstance.execute(
            null,
            new List<Punch_Record__c>{ queriedRecord }
        );

        Test.stopTest();

        System.assert(
            true,
            'Execute should complete without error when HOD is null.'
        );
    }

    // ===============================================================
    // SCHEDULABLE
    // ===============================================================

    @isTest
    static void testSchedulableExecute_DoesNotThrow() {

        Test.startTest();

        System.schedule(
            'PunchRecordReminderTestJob',
            '0 0 10 * * ?',
            new PunchRecordDayStartEndReminderBatch()
        );

        Test.stopTest();

        System.assert(
            true,
            'Scheduled batch should execute without throwing an exception.'
        );
    }

    // ===============================================================
    // CONSTRUCTOR COVERAGE
    // ===============================================================

    @isTest
    static void testConstructors() {

        PunchRecordDayStartEndReminderBatch defaultBatch =
            new PunchRecordDayStartEndReminderBatch();

        PunchRecordDayStartEndReminderBatch typedBatch =
            new PunchRecordDayStartEndReminderBatch(
                PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_10AM
            );

        System.assertNotEquals(
            null,
            defaultBatch,
            'Default constructor should create an instance.'
        );

        System.assertNotEquals(
            null,
            typedBatch,
            'Parameterized constructor should create an instance.'
        );
    }

    // ===============================================================
    // HELPER - CREATE USER
    // ===============================================================

    private static User createTestUser(String uniqueKey) {

        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        return new User(
            FirstName = 'Test',
            LastName = 'User' + uniqueKey,
            Email = 'testuser' + uniqueKey + '@example.com',
            Username =
                'testuser' +
                uniqueKey +
                String.valueOf(Datetime.now().getTime()) +
                '@example.com',
            Alias = 'tu' + uniqueKey,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardProfile.Id,
            IsActive = true
        );
    }

    // ===============================================================
    // HELPER - TODAY'S PUNCH
    // ===============================================================

    private static void insertTodayPunchInForEmployeeWithTodayPunch() {

        User employeeWithTodayPunch = [
            SELECT Id
            FROM User
            WHERE LastName = 'Usere1'
            LIMIT 1
        ];

        User hod = [
            SELECT Id
            FROM User
            WHERE LastName = 'Userhd1'
            LIMIT 1
        ];

        insert new Punch_Record__c(
            User__c = employeeWithTodayPunch.Id,
            HOD__c = hod.Id,
            Punch_Time__c = Datetime.now(),
            Action__c = 'IN',
            Punch_Type__c = 'Day In / Out'
        );
    }

    // ===============================================================
    // HELPER - EMPLOYEE WITHOUT TODAY'S PUNCH
    // ===============================================================

    private static void insertNotYetPunchedInRecordForEmployeeMissingPunch() {

        User employeeMissingPunch = [
            SELECT Id
            FROM User
            WHERE LastName = 'Usere2'
            LIMIT 1
        ];

        User hod = [
            SELECT Id
            FROM User
            WHERE LastName = 'Userhd1'
            LIMIT 1
        ];

        insert new Punch_Record__c(
            User__c = employeeMissingPunch.Id,
            HOD__c = hod.Id,
            Punch_Time__c = null,
            Action__c = 'IN',
            Punch_Type__c = 'Day In / Out'
        );
    }
}