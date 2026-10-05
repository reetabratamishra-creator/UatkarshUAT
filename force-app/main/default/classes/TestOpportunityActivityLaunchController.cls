@isTest
private class TestOpportunityActivityLaunchController {

    private static final String FALLBACK_DEPT = 'High Mast';

    /* ---------- picklist helpers (org-value independent) ---------- */
    private static String firstPicklistValue(Schema.SObjectField f) {
        for (Schema.PicklistEntry pe : f.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                return pe.getValue();
            }
        }
        return null;
    }

    private static String oppDeptValue() {
        String v = firstPicklistValue(Opportunity.Department_Name__c);
        return String.isBlank(v) ? FALLBACK_DEPT : v;
    }

    private static String userMultiDeptValue() {
        return firstPicklistValue(User.Departments__c); // null if not a picklist / no values
    }

    /* ---------- fetch helpers ---------- */
    private static User userByAlias(String alias) {
        return [SELECT Id, Name, Department, Departments__c FROM User WHERE Alias = :alias LIMIT 1];
    }

    private static Opportunity theOpp() {
        return [SELECT Id, Department_Name__c FROM Opportunity WHERE Name = 'OALC Test Opp' LIMIT 1];
    }

    private static Set<Id> idsOf(List<OpportunityActivityLauncherController.UserOption> opts) {
        Set<Id> ids = new Set<Id>();
        for (OpportunityActivityLauncherController.UserOption o : opts) {
            ids.add(o.id);
        }
        return ids;
    }

    @testSetup
    static void setup() {
        Account a = new Account(Name = 'OALC Test Acc');
        insert a;

        Opportunity o = new Opportunity(
            Name               = 'OALC Test Opp',
            StageName          = 'Prospecting',
            CloseDate          = Date.today().addDays(30),
            AccountId          = a.Id,
            Department_Name__c = oppDeptValue()
        );
        insert o;

        // User is a setup object -> insert inside runAs to avoid MIXED_DML_OPERATION
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile adminP = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
            Profile stdP   = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

            String dept      = oppDeptValue();
            String multiDept = userMultiDeptValue();

            List<User> users = new List<User>();

            // 1. Admin profile, no Departments__c  -> fallback branch
            users.add(buildUser(adminP.Id, 'oalcadm', 'admin@oalc.test', null, null));

            // 2. Non-admin, no Departments__c      -> fallback branch
            users.add(buildUser(stdP.Id, 'oalcnod', 'nodept@oalc.test', dept, null));

            // 3. Non-admin, has Departments__c     -> default (INCLUDES) branch
            users.add(buildUser(stdP.Id, 'oalcdep', 'dept@oalc.test', dept, multiDept));

            // 4. Target user for the fallback list (User.Department = Opp department)
            users.add(buildUser(stdP.Id, 'oalctgt', 'target@oalc.test', dept, multiDept));

            insert users;
        }
    }

    private static User buildUser(Id profileId, String alias, String email,
                                  String department, String multiDept) {
        User u = new User(
            ProfileId         = profileId,
            Alias             = alias,
            Email             = email,
            Username          = email + '.oalc' + System.currentTimeMillis(),
            LastName          = alias,
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'Asia/Kolkata',
            IsActive          = true,
            Department        = department
        );
        if (String.isNotBlank(multiDept)) {
            u.put('Departments__c', multiDept);
        }
        return u;
    }

    /* =====================================================================
     *  getAssignableUsers
     * ===================================================================== */

    @isTest
    static void testAdminProfileFallsBackToOpportunityDepartment() {
        Opportunity o = theOpp();
        User admin    = userByAlias('oalcadm');
        User target   = userByAlias('oalctgt');

        Test.startTest();
        List<OpportunityActivityLauncherController.UserOption> opts;
        System.runAs(admin) {
            opts = OpportunityActivityLauncherController.getAssignableUsers(o.Id);
        }
        Test.stopTest();

        Set<Id> ids = idsOf(opts);
        System.assert(ids.contains(target.Id),
            'Admin should see users whose User.Department matches the Opportunity department');
        System.assert(ids.contains(admin.Id), 'Running user must always be present');
    }

    @isTest
    static void testUserWithoutDepartmentFallsBackToOpportunityDepartment() {
        Opportunity o = theOpp();
        User noDept   = userByAlias('oalcnod');
        User target   = userByAlias('oalctgt');

        Test.startTest();
        List<OpportunityActivityLauncherController.UserOption> opts;
        System.runAs(noDept) {
            opts = OpportunityActivityLauncherController.getAssignableUsers(o.Id);
        }
        Test.stopTest();

        Set<Id> ids = idsOf(opts);
        System.assert(ids.contains(target.Id),
            'User without Departments__c should get the Opportunity-department list');
        System.assert(ids.contains(noDept.Id), 'Running user must always be present');
    }

    @isTest
    static void testDepartmentUserUsesIncludesBranch() {
        Opportunity o = theOpp();
        User deptUser = userByAlias('oalcdep');

        Test.startTest();
        List<OpportunityActivityLauncherController.UserOption> opts;
        System.runAs(deptUser) {
            opts = OpportunityActivityLauncherController.getAssignableUsers(o.Id);
        }
        Test.stopTest();

        System.assert(!opts.isEmpty(), 'Assignable list should never be empty');
        System.assert(idsOf(opts).contains(deptUser.Id), 'Running user must always be present');
    }

    @isTest
    static void testBlankOpportunityDepartmentReturnsOnlyRunningUser() {
        User admin = userByAlias('oalcadm');

        Opportunity blank = new Opportunity(
            Name      = 'OALC Blank Dept Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        insert blank;

        Test.startTest();
        List<OpportunityActivityLauncherController.UserOption> opts;
        System.runAs(admin) {
            opts = OpportunityActivityLauncherController.getAssignableUsers(blank.Id);
        }
        Test.stopTest();

        System.assertEquals(1, opts.size(), 'Only the running user should come back');
        System.assertEquals(admin.Id, opts[0].id, 'Running user expected');
    }

    @isTest
    static void testNullOpportunityIdIsSafe() {
        User admin = userByAlias('oalcadm');

        Test.startTest();
        List<OpportunityActivityLauncherController.UserOption> opts;
        System.runAs(admin) {
            opts = OpportunityActivityLauncherController.getAssignableUsers(null);
        }
        Test.stopTest();

        System.assertEquals(1, opts.size(), 'Null Opportunity Id should degrade to running user only');
    }

    /* =====================================================================
     *  Call
     * ===================================================================== */

    @isTest
    static void testCreateCallAndDuplicateBlock() {
        Opportunity o = theOpp();

        Test.startTest();
        Id taskId = OpportunityActivityLauncherController.createCall(
            o.Id, 'Follow up call', Datetime.now().addDays(1), 'Discuss offer', UserInfo.getUserId());

        String err;
        try {
            OpportunityActivityLauncherController.createCall(
                o.Id, 'Second call', Datetime.now().addDays(2), null, UserInfo.getUserId());
        } catch (AuraHandledException e) {
            err = e.getMessage();
        }
        Test.stopTest();

        Task t = [SELECT Id, Status, TaskSubtype, WhatId, OwnerId FROM Task WHERE Id = :taskId];
        System.assertEquals('Open', t.Status);
        System.assertEquals('Call', t.TaskSubtype);
        System.assertEquals(o.Id, t.WhatId);
        System.assert(err != null && err.contains('open Call'), 'Duplicate open Call must be blocked');
    }

    @isTest
    static void testCreateCallRejectsPastDate() {
        Opportunity o = theOpp();

        Test.startTest();
        String err;
        try {
            OpportunityActivityLauncherController.createCall(
                o.Id, 'Past call', Datetime.now().addDays(-1), null, null);
        } catch (AuraHandledException e) {
            err = e.getMessage();
        }
        Test.stopTest();

        System.assert(err != null && err.contains('past'), 'Past follow-up date must be rejected');
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :o.Id]);
    }

    /* =====================================================================
     *  Event
     * ===================================================================== */

    @isTest
    static void testCreateEventAndDuplicateBlock() {
        Opportunity o = theOpp();
        Datetime st   = Datetime.now().addDays(1);

        Test.startTest();
        Id eventId = OpportunityActivityLauncherController.createEvent(
            o.Id, 'Client meeting', 'Agenda', st, st.addHours(1), UserInfo.getUserId());

        String err;
        try {
            OpportunityActivityLauncherController.createEvent(
                o.Id, 'Second meeting', null, st.addDays(1), st.addDays(1).addHours(1), null);
        } catch (AuraHandledException e) {
            err = e.getMessage();
        }
        Test.stopTest();

        Event e = [SELECT Id, WhatId, Type, IsReminderSet FROM Event WHERE Id = :eventId];
        System.assertEquals(o.Id, e.WhatId);
        System.assertEquals('Meeting', e.Type);
        System.assert(e.IsReminderSet, 'Reminder should be set');
        System.assert(err != null && err.contains('open Event'), 'Duplicate open Event must be blocked');
    }

    @isTest
    static void testCreateEventRejectsPastStart() {
        Opportunity o = theOpp();

        Test.startTest();
        String err;
        try {
            OpportunityActivityLauncherController.createEvent(
                o.Id, 'Past meeting', null, Datetime.now().addDays(-2),
                Datetime.now().addDays(-2).addHours(1), null);
        } catch (AuraHandledException e) {
            err = e.getMessage();
        }
        Test.stopTest();

        System.assert(err != null && err.contains('past'), 'Past Event start must be rejected');
    }

    /* =====================================================================
     *  Visit
     * ===================================================================== */

    @isTest
    static void testCreateVisitAndDuplicateBlock() {
        Opportunity o  = theOpp();
        String visitTp = firstPicklistValue(Task_Log__c.Visit_Type__c);
        String reason  = firstPicklistValue(Task_Log__c.Reason_for_Visit__c);

        Test.startTest();
        Id visitId = OpportunityActivityLauncherController.createVisit(
            o.Id, visitTp, reason, Date.today().addDays(3), UserInfo.getUserId());

        String err;
        try {
            OpportunityActivityLauncherController.createVisit(
                o.Id, visitTp, reason, Date.today().addDays(4), null);
        } catch (AuraHandledException e) {
            err = e.getMessage();
        }
        Test.stopTest();

        Task_Log__c v = [
            SELECT Id, Opportunity__c, Is_schedule__c, Logged_At__c, Schedule_Date__c
            FROM Task_Log__c WHERE Id = :visitId
        ];
        System.assertEquals(o.Id, v.Opportunity__c);
        System.assert(v.Is_schedule__c, 'Visit should be flagged as scheduled');
        System.assertEquals(null, v.Logged_At__c, 'A new visit must stay open');
        System.assert(err != null && err.contains('open Visit'), 'Duplicate open Visit must be blocked');
    }

    @isTest
    static void testCreateVisitRejectsPastDate() {
        Opportunity o  = theOpp();
        String visitTp = firstPicklistValue(Task_Log__c.Visit_Type__c);
        String reason  = firstPicklistValue(Task_Log__c.Reason_for_Visit__c);

        Test.startTest();
        String err;
        try {
            OpportunityActivityLauncherController.createVisit(
                o.Id, visitTp, reason, Date.today().addDays(-1), null);
        } catch (AuraHandledException e) {
            err = e.getMessage();
        }
        Test.stopTest();

        System.assert(err != null && err.contains('past'), 'Past Schedule Date must be rejected');
    }

    /* =====================================================================
     *  getOpenStatus
     * ===================================================================== */

    @isTest
    static void testGetOpenStatus() {
        Opportunity o  = theOpp();
        String visitTp = firstPicklistValue(Task_Log__c.Visit_Type__c);
        String reason  = firstPicklistValue(Task_Log__c.Reason_for_Visit__c);

        OpportunityActivityLauncherController.OpenStatus before =
            OpportunityActivityLauncherController.getOpenStatus(o.Id);
        System.assert(!before.callOpen && !before.eventOpen && !before.visitOpen,
            'Nothing should be open initially');

        Test.startTest();
        OpportunityActivityLauncherController.createCall(
            o.Id, 'Call', Datetime.now().addDays(1), null, null);
        OpportunityActivityLauncherController.createEvent(
            o.Id, 'Event', null, Datetime.now().addDays(1), Datetime.now().addDays(1).addHours(1), null);
        OpportunityActivityLauncherController.createVisit(
            o.Id, visitTp, reason, Date.today().addDays(2), null);

        OpportunityActivityLauncherController.OpenStatus after =
            OpportunityActivityLauncherController.getOpenStatus(o.Id);
        Test.stopTest();

        System.assert(after.callOpen,  'Call should be open');
        System.assert(after.eventOpen, 'Event should be open');
        System.assert(after.visitOpen, 'Visit should be open');
    }
}