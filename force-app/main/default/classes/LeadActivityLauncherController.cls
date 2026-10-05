public with sharing class LeadActivityLauncherController {

    private static final String DEPT_ENQUIRY   = 'Enquiry';
    private static final String NOTIF_TYPE_DEV_NAME = 'Activity_Assignment';

    public class OpenStatus {
        @AuraEnabled public Boolean callOpen  = false;
        @AuraEnabled public Boolean eventOpen = false;
        @AuraEnabled public Boolean visitOpen = false;
        @AuraEnabled public Boolean eventVisitBlocked = false;
    }

    public class UserOption {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
    }

    @AuraEnabled(cacheable=true)
    public static OpenStatus getOpenStatus(Id leadId) {
        OpenStatus s = new OpenStatus();
        s.callOpen  = hasOpenCall(leadId);
        s.eventOpen = hasOpenEvent(leadId);
        s.visitOpen = hasOpenVisit(leadId);
        s.eventVisitBlocked = isEnquiry(leadId);
        return s;
    }

    /* =========================================================================
     *  READ:  assignable users, based on the RUNNING USER'S department.
     *  Returns only active users whose Departments__c matches any of the running
     *  user's Departments__c. The running user is always included so they can be
     *  defaulted in the picker.
     * ========================================================================= */
    @AuraEnabled(cacheable=true)
    public static List<UserOption> getAssignableUsers() {
        List<UserOption> options = new List<UserOption>();

        Id runningUserId = UserInfo.getUserId();
        List<String> depts = splitDepartments(runningUserDepartment(runningUserId));

        List<User> users;
        if (depts.isEmpty()) {
            // No department on the running user -> only the running user.
            users = [SELECT Id, Name FROM User WHERE Id = :runningUserId];
        } else {
            users = (List<User>) Database.query(buildIncludesSoql(depts));
        }

        Boolean runningIncluded = false;
        for (User u : users) {
            options.add(toOption(u));
            if (u.Id == runningUserId) {
                runningIncluded = true;
            }
        }
        // Guarantee the running user is present (so the default selection resolves).
        if (!runningIncluded) {
            options.add(0, toOption([SELECT Id, Name FROM User WHERE Id = :runningUserId WITH SYSTEM_MODE]));
        }
        return options;
    }

    private static String runningUserDepartment(Id userId) {
        return [SELECT Departments__c FROM User WHERE Id = :userId WITH SYSTEM_MODE].Departments__c;
    }

    private static List<String> splitDepartments(String multi) {
        List<String> result = new List<String>();
        if (String.isNotBlank(multi)) {
            for (String d : multi.split(';')) {
                if (String.isNotBlank(d)) {
                    result.add(d.trim());
                }
            }
        }
        return result;
    }

    private static String buildIncludesSoql(List<String> departments) {
        List<String> conditions = new List<String>();
        for (String dept : departments) {
            conditions.add('Departments__c INCLUDES (\'' + String.escapeSingleQuotes(dept) + '\')');
        }
        return 'SELECT Id, Name FROM User '
            + 'WHERE IsActive = true '
            + 'AND Profile.Name NOT IN (\'Utkarsh Admin\', \'System Administrator\') '
            + 'AND (' + String.join(conditions, ' OR ') + ') WITH SYSTEM_MODE ORDER BY Name';
    }

    private static UserOption toOption(User u) {
        UserOption opt = new UserOption();
        opt.id   = u.Id;
        opt.name = u.Name;
        return opt;
    }

    /* ---- OPEN definitions ---- */
    private static Boolean hasOpenCall(Id leadId) {
        return [
            SELECT COUNT()
            FROM Task
            WHERE WhoId = :leadId
              AND TaskSubtype = 'Call'
              AND Status = 'Open'
              AND Manually_Created__c = true
            WITH SYSTEM_MODE
        ] > 0;
    }

    private static Boolean hasOpenEvent(Id leadId) {
        Datetime nowDt = Datetime.now();
        return [
            SELECT COUNT()
            FROM Event
            WHERE WhoId = :leadId
              AND (Disposition__c = null
                   OR Disposition__c NOT IN ('Completed', 'Not Completed'))
              AND StartDateTime >= :nowDt
              AND (EndDateTime >= :nowDt OR EndDateTime = null)
        ] > 0;
    }

    private static Boolean hasOpenVisit(Id leadId) {
        return [
            SELECT COUNT()
            FROM Task_Log__c
            WHERE Lead__c = :leadId
              AND Is_schedule__c = true
              AND Logged_At__c = null
        ] > 0;
    }

    /* ---- CREATE: Call ---- */
    @AuraEnabled
    public static Id createCall(Id leadId, String subject, Datetime followUp,
                                String comments, Id assignedToId) {
        if (hasOpenCall(leadId)) {
            throw handled('An open Call already exists for this Lead. Complete it before creating a new one.');
        }
        Task t = new Task();
        t.WhoId                  = leadId;
        t.TaskSubtype            = 'Call';
        t.Subject                = subject;
        t.Status                 = 'Open';
        t.Manually_Created__c    = true;
        t.Follow_Up_Date_Time__c = followUp;
        if (followUp != null) {
            t.ActivityDate = followUp.date();
        }
        t.Description = comments;
        if (assignedToId != null) {
            t.OwnerId = assignedToId;
        }
        insert t;
        return t.Id;
    }

    /* ---- CREATE: Event ---- */
    @AuraEnabled
    public static Id createEvent(Id leadId, String subject, String comments,
                                 Datetime startDt, Datetime endDt, Id assignedToId) {
        if (isEnquiry(leadId)) {
            throw handled('Events cannot be created for a Lead in the Enquiry department.');
        }
        if (hasOpenEvent(leadId)) {
            throw handled('An open Event already exists for this Lead. Complete it before creating a new one.');
        }
        Event e = new Event();
        e.WhoId         = leadId;
        e.Subject       = subject;
        e.Description   = comments;
        e.StartDateTime = startDt;
        e.EndDateTime   = endDt;
        e.Type          = 'Meeting';
        e.Type          = 'Meeting';
        e.IsReminderSet = true;                       // "Reminder Set"
        if (startDt != null) {
            e.ReminderDateTime = startDt.addMinutes(-15); // 15 minutes before start
        }
        if (assignedToId != null) {
            e.OwnerId = assignedToId;
        }
        insert e;

        /*notifyOwner(effectiveOwner(assignedToId), e.Id,
            'New Event assigned',
            String.isBlank(subject) ? 'An event has been assigned to you.' : subject);*/
        return e.Id;
    }

    /* ---- CREATE: Visit ---- */
    @AuraEnabled
    public static Id createVisit(Id leadId, String visitType, String reason,
                                 Date scheduleDate, Id assignedToId) {
        if (isEnquiry(leadId)) {
            throw handled('Visits cannot be created for a Lead in the Enquiry department.');
        }
        if (hasOpenVisit(leadId)) {
            throw handled('An open Visit already exists for this Lead. Complete it before creating a new one.');
        }
        Task_Log__c v = new Task_Log__c();
        v.Lead__c             = leadId;
        v.Visit_Type__c       = visitType;
        v.Reason_for_Visit__c = reason;
        v.Schedule_Date__c    = scheduleDate;
        v.Is_schedule__c      = true;
        v.Manually_Created__c = true;
        if (assignedToId != null) {
            v.OwnerId = assignedToId;
        }
        insert v;

        String body = 'A visit has been assigned to you.';
        if (String.isNotBlank(visitType)) {
            body = 'Visit (' + visitType + ') has been assigned to you.';
        }
        //notifyOwner(effectiveOwner(assignedToId), v.Id, 'New Visit assigned', body);
        return v.Id;
    }

    /* =========================================================================
     *  PUSH / CUSTOM NOTIFICATION to the record owner (non-blocking).
     * ========================================================================= */
    private static Id effectiveOwner(Id assignedToId) {
        return assignedToId != null ? assignedToId : UserInfo.getUserId();
    }

    private static void notifyOwner(Id ownerId, Id targetRecordId, String title, String body) {
        if (ownerId == null) {
            return;
        }
        Id typeId = notificationTypeId();
        if (typeId == null) {
            return;
        }
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(title);
            notification.setBody(body);
            notification.setNotificationTypeId(typeId);
            notification.setTargetId(targetRecordId);
            notification.send(new Set<String>{ String.valueOf(ownerId) });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Owner notification failed: ' + e.getMessage());
        }
    }

    private static Id cachedNotifTypeId;
    private static Boolean notifTypeResolved = false;
    private static Id notificationTypeId() {
        if (!notifTypeResolved) {
            List<CustomNotificationType> types = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :NOTIF_TYPE_DEV_NAME WITH SYSTEM_MODE LIMIT 1
            ];
            cachedNotifTypeId = types.isEmpty() ? null : types[0].Id;
            notifTypeResolved = true;
        }
        return cachedNotifTypeId;
    }

    /* ---- shared ---- */
    private static Boolean isEnquiry(Id leadId) {
        String d = [SELECT Department_Name__c FROM Lead WHERE Id = :leadId WITH SYSTEM_MODE].Department_Name__c;
        return d != null && DEPT_ENQUIRY.equalsIgnoreCase(d.trim());
    }

    private static AuraHandledException handled(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }
}