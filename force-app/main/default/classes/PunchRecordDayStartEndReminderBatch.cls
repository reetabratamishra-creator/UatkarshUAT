/**
 * @description Sends Day Start & Day End reminder emails based on reminder type.
 *              1. Day Start not done by 10:00 AM → Employee
 *              2. Day Start not done by 10:45 AM → HOD
 *              3. Day End not done by 12:00 Midnight → Employee
 * @author Rani Mate
 * @date 2026-08-14
 */
public without sharing class PunchRecordDayStartEndReminderBatch
    implements Database.Batchable<SObject>, Schedulable {

    public enum ReminderType {
        DAY_START_10AM,
        DAY_START_1045,
        DAY_START_NOON,
        DAY_END_MIDNIGHT
    }

    public static final String TEMPLATE_DAY_START_10AM =
        'Day_start_not_done_on_time_1786600176251';
    public static final String TEMPLATE_DAY_START_1045AM =
        'Day_start_not_done_within_10_45_AM_1786602337640';
    public static final String TEMPLATE_DAY_END_MIDNIGHT =
        'Day_end_not_done_by_12o_clock_midnight_1786603106530';
    public static final String NOTIFICATION_TYPE_API_NAME = 'Day_Start_Not_Done';

    public static final String ORG_WIDE_SENDER_EMAIL = 'noreply@utkarshindialimited.in';

    @TestVisible
    private ReminderType reminderType;

    public PunchRecordDayStartEndReminderBatch() {
        this(null);
    }

    public PunchRecordDayStartEndReminderBatch(ReminderType reminderType) {
        this.reminderType = reminderType;
    }

    public void execute(SchedulableContext sc) {
        ReminderType scheduledType = resolveReminderTypeFromScheduleTime();
        if (scheduledType == null) {
            return;
        }
        Database.executeBatch(
            new PunchRecordDayStartEndReminderBatch(scheduledType),
            50
        );
    }

    // CHANGED: return type is now Iterable<SObject> instead of Database.QueryLocator,
    // because for the Day Start reminders we now need to build the "who hasn't
    // punched in today" list in memory rather than run a single SOQL query.
    public Iterable<SObject> start(Database.BatchableContext bc) {
        ReminderType activeType = reminderType == null
            ? resolveReminderTypeFromScheduleTime()
            : reminderType;

        // NEW: for Day Start reminders, find users with NO punch-in today at all,
        // instead of only looking at Punch_Record__c rows that already exist.
        if (
            activeType == PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_10AM ||
            activeType == PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_1045 ||
            activeType == PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_NOON
        ) {
            return buildNotPunchedInTodayRoster();
        }

        // UNCHANGED: original query, still used for the Day End (midnight) reminder,
        // since that one legitimately needs an existing today's punch-in record.
        return [
            SELECT Id, User__c, HOD__c, Punch_Time__c, CreatedDate,
                   User__r.Email, HOD__r.Email, User__r.Profile.Name
            FROM Punch_Record__c
            WHERE CreatedDate = TODAY
                AND Action__c = 'IN'
                AND Punch_Type__c = 'Day In / Out'
        ];
    }

    // NEW: builds a list representing "each employee, and whether they've
    // punched in today." Uses each user's most recent past Punch_Record__c
    // just to get their User__c/HOD__c/email mapping, then keeps only the
    // ones who have NOT punched in today.
    private List<Punch_Record__c> buildNotPunchedInTodayRoster() {
        Set<Id> punchedInTodayUserIds = new Set<Id>();
        for (Punch_Record__c pr : [
            SELECT User__c
            FROM Punch_Record__c
            WHERE CreatedDate = TODAY
                AND Action__c = 'IN'
                AND Punch_Type__c = 'Day In / Out'
                AND Punch_Time__c != null
        ]) {
            punchedInTodayUserIds.add(pr.User__c);
        }

        Map<Id, Punch_Record__c> latestRecordByUser = new Map<Id, Punch_Record__c>();
        for (Punch_Record__c pr : [
            SELECT Id, User__c, HOD__c, Punch_Time__c, CreatedDate,
                   User__r.Email, HOD__r.Email, User__r.Profile.Name
            FROM Punch_Record__c
            WHERE Action__c = 'IN'
                AND Punch_Type__c = 'Day In / Out'
            ORDER BY CreatedDate DESC
        ]) {
            if (
                !punchedInTodayUserIds.contains(pr.User__c) &&
                !latestRecordByUser.containsKey(pr.User__c)
            ) {
                // Force Punch_Time__c to null on this in-memory copy so the
                // existing "isDayStartDone" check in execute() below still
                // works correctly — this record is from a past day, not today.
                pr.Punch_Time__c = null;
                latestRecordByUser.put(pr.User__c, pr);
            }
        }

        return latestRecordByUser.values();
    }

    public void execute(Database.BatchableContext bc, List<Punch_Record__c> scope) {
        ReminderType activeReminderType = reminderType == null
            ? resolveReminderTypeFromScheduleTime()
            : reminderType;
        if (activeReminderType == null || scope == null || scope.isEmpty()) {
            return;
        }

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();

        for (Punch_Record__c punchRecord : scope) {
            Boolean isDayStartDone = punchRecord.Punch_Time__c != null;

            if (
                activeReminderType ==
                    PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_10AM &&
                !isDayStartDone &&
                punchRecord.User__r.Email != null
            ) {
                Messaging.SingleEmailMessage mail = buildMessage(
                    TEMPLATE_DAY_START_10AM,
                    punchRecord.Id,
                    punchRecord.User__r.Email
                );
                if (mail != null) {
                    messages.add(mail);
                }
            } else if (
                activeReminderType ==
                    PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_1045 &&
                !isDayStartDone &&
                punchRecord.HOD__r.Email != null
            ) {
                Messaging.SingleEmailMessage mail = buildMessage(
                    TEMPLATE_DAY_START_1045AM,
                    punchRecord.Id,
                    punchRecord.HOD__r.Email
                );
                if (mail != null) {
                    messages.add(mail);
                }
            } else if (
                activeReminderType ==
                    PunchRecordDayStartEndReminderBatch.ReminderType.DAY_END_MIDNIGHT &&
                punchRecord.Punch_Time__c != null &&
                punchRecord.User__r.Email != null
            ) {
                Messaging.SingleEmailMessage mail = buildMessage(
                    TEMPLATE_DAY_END_MIDNIGHT,
                    punchRecord.Id,
                    punchRecord.User__r.Email
                );
                if (mail != null) {
                    messages.add(mail);
                }
            }

            // SEND CUSTOM NOTIFICATION TO SALES USER IF DAY NOT STARTED
            // BY 10 AM OR 12 NOON
            if (
                (activeReminderType == PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_10AM ||
                activeReminderType == PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_NOON) &&
                !isDayStartDone && punchRecord.User__r.Profile.Name == 'Utkarsh Sales' 
            ) {
                sendDayStartNotDoneNotification(punchRecord.User__c, punchRecord.Id);
            }
        }

        if (!messages.isEmpty()) {
            Messaging.sendEmail(messages);
        }
    }

    public void finish(Database.BatchableContext bc) {}

    @TestVisible
    private static ReminderType resolveReminderTypeFromScheduleTime() {
        Datetime now = System.now();
        Integer hour = now.hour();
        Integer minute = now.minute();

        if (hour == 0 && minute < 30) {
            return PunchRecordDayStartEndReminderBatch.ReminderType.DAY_END_MIDNIGHT;
        }
        if (hour == 10 && minute < 45) {
            return PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_10AM;
        }
        if (hour == 10 && minute >= 45) {
            return PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_1045;
        }
        if (hour == 12 && minute < 30) {
            return PunchRecordDayStartEndReminderBatch.ReminderType.DAY_START_NOON;
        }
        return null;
    }

    private static Messaging.SingleEmailMessage buildMessage(
        String templateDeveloperName,
        Id punchRecordId,
        String recipientEmail
    ) {
        Id templateId = resolveTemplateId(templateDeveloperName);
        if (templateId == null || String.isBlank(recipientEmail)) {
            return null;
        }

        Messaging.SingleEmailMessage message = Messaging.renderStoredEmailTemplate(
            templateId,
            null,
            punchRecordId
        );
        message.setToAddresses(new List<String>{ recipientEmail });
        message.setSaveAsActivity(false);
        message.setTreatTargetObjectAsRecipient(false);
        applyOrgWideSender(message);
        return message;
    }

    private static Id resolveTemplateId(String templateDeveloperName) {
        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :templateDeveloperName
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Id;
    }

    private static void applyOrgWideSender(Messaging.SingleEmailMessage message) {
        List<OrgWideEmailAddress> orgWideAddresses = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_SENDER_EMAIL
            LIMIT 1
        ];
        if (!orgWideAddresses.isEmpty()) {
            message.setOrgWideEmailAddressId(orgWideAddresses[0].Id);
        }
    }

    @TestVisible
    private static void sendDayStartNotDoneNotification(Id userId, Id punchRecordId) {
        if (userId == null) {
            return;
        }
        CustomNotificationType notifType = [
            SELECT Id FROM CustomNotificationType
            WHERE DeveloperName = :NOTIFICATION_TYPE_API_NAME
            LIMIT 1
        ];
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setTitle('Day Start not done');
        notification.setBody('Start your day! Please mark your attendance');
        notification.setNotificationTypeId(notifType.Id);
        notification.setTargetId(punchRecordId);
        try {
            notification.send(new Set<String>{ userId });
        } catch (Exception e) {
            System.debug('Custom notification send failed: ' + e.getMessage());
        }
    }
}