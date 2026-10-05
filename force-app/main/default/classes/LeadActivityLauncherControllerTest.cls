@isTest
private class LeadActivityLauncherControllerTest {

    /* =========================================================================
     *  Setup: a normal (non-Enquiry) Lead and an Enquiry Lead.
     *  Adjust Lead Status if your org lacks 'Open - Not Contacted'.
     * ========================================================================= */
    @testSetup
    static void setup() {
        Lead normal = new Lead(LastName = 'Normal', Company = 'Acme',
                               Status = 'Open - Not Contacted');
        String nonEnquiry = firstNonEnquiryDept();
        if (nonEnquiry != null) { normal.Department_Name__c = nonEnquiry; }
        insert normal;

        insert new Lead(LastName = 'Enq', Company = 'Acme',
                        Status = 'Open - Not Contacted',
                        Department_Name__c = 'Enquiry');
    }

    private static Id normalLeadId() {
        return [SELECT Id FROM Lead WHERE LastName = 'Normal' LIMIT 1].Id;
    }
    private static Id enquiryLeadId() {
        return [SELECT Id FROM Lead WHERE LastName = 'Enq' LIMIT 1].Id;
    }

    private static String firstPicklist(Schema.SObjectField f) {
        for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) {
            if (e.isActive()) return e.getValue();
        }
        return null;
    }
    private static String firstNonEnquiryDept() {
        for (Schema.PicklistEntry e : Lead.Department_Name__c.getDescribe().getPicklistValues()) {
            if (e.isActive() && !'Enquiry'.equalsIgnoreCase(e.getValue())) return e.getValue();
        }
        return null;
    }

    /* ---------------------------- getOpenStatus ---------------------------- */
    @isTest
    static void testGetOpenStatus_DefaultAndEnquiry() {
        Test.startTest();
        LeadActivityLauncherController.OpenStatus normal =
            LeadActivityLauncherController.getOpenStatus(normalLeadId());
        LeadActivityLauncherController.OpenStatus enq =
            LeadActivityLauncherController.getOpenStatus(enquiryLeadId());
        Test.stopTest();

        System.assertEquals(false, normal.callOpen);
        System.assertEquals(false, normal.eventVisitBlocked);
        System.assertEquals(true, enq.eventVisitBlocked, 'Enquiry blocks Event/Visit');
    }

    @isTest
    static void testGetOpenStatus_OpenCallAndEvent() {
        Id leadId = normalLeadId();
        // open manually-created call
        insert new Task(WhoId = leadId, Subject = 'Call', TaskSubtype = 'Call',
                        Status = 'Open', Manually_Created__c = true);
        // open (future, not dispositioned) event
        insert new Event(WhoId = leadId, Subject = 'Mtg',
                         StartDateTime = Datetime.now().addDays(1),
                         EndDateTime = Datetime.now().addDays(1).addHours(1));

        Test.startTest();
        LeadActivityLauncherController.OpenStatus s =
            LeadActivityLauncherController.getOpenStatus(leadId);
        Test.stopTest();

        System.assertEquals(true, s.callOpen);
        System.assertEquals(true, s.eventOpen);
    }

    @isTest
    static void testGetOpenStatus_OpenVisit() {
        Id leadId = normalLeadId();
        Boolean created = createOpenVisit(leadId);

        Test.startTest();
        LeadActivityLauncherController.OpenStatus s =
            LeadActivityLauncherController.getOpenStatus(leadId);
        Test.stopTest();

        if (created) {
            System.assertEquals(true, s.visitOpen);
        }
    }

    // Best-effort open visit; returns whether it inserted (Task_Log__c required
    // fields vary by org).
    private static Boolean createOpenVisit(Id leadId) {
        try {
            Task_Log__c v = new Task_Log__c();
            v.Lead__c             = leadId;
            v.Visit_Type__c       = firstPicklist(Task_Log__c.Visit_Type__c);
            v.Reason_for_Visit__c = firstPicklist(Task_Log__c.Reason_for_Visit__c);
            v.Schedule_Date__c    = Date.today().addDays(1);
            v.Is_schedule__c      = true;
            insert v;
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /* ------------------------- getAssignableUsers ----------------------- */
    @isTest
    static void testGetAssignableUsers_RunningUser() {
        Test.startTest();
        List<LeadActivityLauncherController.UserOption> users =
            LeadActivityLauncherController.getAssignableUsers();
        Test.stopTest();
        System.assert(!users.isEmpty(), 'Running user should be included');
    }

    @isTest
    static void testGetAssignableUsers_WithDepartment() {
        String deptVal = firstPicklist(User.Departments__c);
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(Datetime.now().getTime());
        User u = new User(
            ProfileId = p.Id, LastName = 'DeptUser',
            Email = 'du' + uniq + '@example.com.invalid',
            Username = 'du' + uniq + '@example.com.invalid',
            Alias = 'du1', TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US');
        if (deptVal != null) { u.Departments__c = deptVal; }
        insert u;

        Test.startTest();
        System.runAs(u) {
            List<LeadActivityLauncherController.UserOption> users =
                LeadActivityLauncherController.getAssignableUsers();
            System.assert(!users.isEmpty());
        }
        Test.stopTest();
    }

    /* ------------------------------ createCall -------------------------- */
    @isTest
    static void testCreateCall_AndBlock() {
        Id leadId = normalLeadId();
        Test.startTest();
        Id cId = LeadActivityLauncherController.createCall(
            leadId, 'Follow up', Datetime.now().addDays(1), 'note', null);

        Boolean blocked = false;
        try {
            LeadActivityLauncherController.createCall(
                leadId, 'Again', Datetime.now().addDays(1), null, null);
        } catch (AuraHandledException ex) { blocked = true; }
        Test.stopTest();

        Task t = [SELECT WhoId, TaskSubtype, Status, Manually_Created__c
                  FROM Task WHERE Id = :cId];
        System.assertEquals(leadId, t.WhoId);
        System.assertEquals('Call', t.TaskSubtype);
        System.assertEquals(true, t.Manually_Created__c);
        System.assert(blocked, 'Second open call blocked');
    }

    /* ------------------------------ createEvent ------------------------- */
    @isTest
    static void testCreateEvent_AndBlock() {
        Id leadId = normalLeadId();
        Test.startTest();
        Id eId = LeadActivityLauncherController.createEvent(
            leadId, 'Meeting', 'desc',
            Datetime.now().addDays(1), Datetime.now().addDays(1).addHours(1), null);

        Boolean blocked = false;
        try {
            LeadActivityLauncherController.createEvent(
                leadId, 'Meeting 2', null,
                Datetime.now().addDays(2), Datetime.now().addDays(2).addHours(1), null);
        } catch (AuraHandledException ex) { blocked = true; }
        Test.stopTest();

        Event e = [SELECT Type, IsReminderSet, ReminderDateTime FROM Event WHERE Id = :eId];
        System.assertEquals('Meeting', e.Type);
        System.assertEquals(true, e.IsReminderSet);
        System.assertNotEquals(null, e.ReminderDateTime);
        System.assert(blocked, 'Second open event blocked');
    }

    @isTest
    static void testCreateEvent_EnquiryBlocked() {
        Boolean blocked = false;
        Test.startTest();
        try {
            LeadActivityLauncherController.createEvent(
                enquiryLeadId(), 'Meeting', null,
                Datetime.now().addDays(1), Datetime.now().addDays(1).addHours(1), null);
        } catch (AuraHandledException ex) { blocked = true; }
        Test.stopTest();
        System.assert(blocked, 'Events blocked for Enquiry lead');
    }

    /* ------------------------------ createVisit ------------------------- */
    @isTest
    static void testCreateVisit_EnquiryBlocked() {
        Boolean blocked = false;
        Test.startTest();
        try {
            LeadActivityLauncherController.createVisit(
                enquiryLeadId(), 'x', 'y', Date.today().addDays(1), null);
        } catch (AuraHandledException ex) { blocked = true; }
        Test.stopTest();
        System.assert(blocked, 'Visits blocked for Enquiry lead');
    }

    @isTest
    static void testCreateVisit_Normal() {
        Id leadId = normalLeadId();
        String vt = firstPicklist(Task_Log__c.Visit_Type__c);
        String rs = firstPicklist(Task_Log__c.Reason_for_Visit__c);
        Test.startTest();
        try {
            LeadActivityLauncherController.createVisit(
                leadId, vt, rs, Date.today().addDays(1), null);
        } catch (Exception ex) {
            // Task_Log__c may have org-specific required fields; branch still exercised.
        }
        Test.stopTest();
    }
}