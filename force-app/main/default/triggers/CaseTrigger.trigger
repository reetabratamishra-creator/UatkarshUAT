trigger CaseTrigger on Case (after insert, after update) {
    if (!TriggerEnableService.isEnabled(TriggerEnableService.CASE_TRIGGER)) {
        return;
    }

    try {
        if (Trigger.isAfter && Trigger.isInsert) {
            CaseCreatorShareHandler.handleAfterInsert(Trigger.new);
        }
        if (Trigger.isAfter && Trigger.isUpdate) {
            CaseCreatorShareHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    } catch (Exception ex) {
        System.debug(
            LoggingLevel.ERROR,
            'CaseCreatorShareHandler failed: ' +
                ex.getMessage() +
                '\nStack Trace: ' +
                ex.getStackTraceString()
        );
    }

    try {
        if (Trigger.isAfter && Trigger.isInsert) {
            CaseNewAssignedOwnerHandler.handleAfterInsert(Trigger.new);
        }
        if (Trigger.isAfter && Trigger.isUpdate) {
            CaseNewAssignedOwnerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    } catch (Exception ex) {
        System.debug(
            LoggingLevel.ERROR,
            'CaseNewAssignedOwnerHandler failed: ' +
                ex.getMessage() +
                '\nStack Trace: ' +
                ex.getStackTraceString()
        );
    }

    try {
        if (Trigger.isAfter && Trigger.isInsert) {
            CasePushNotificationHandler.handleAfterInsert(Trigger.new);
        }
        if (Trigger.isAfter && Trigger.isUpdate) {
            CasePushNotificationHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    } catch (Exception ex) {
        System.debug(
            LoggingLevel.ERROR,
            'CasePushNotificationHandler failed: ' +
                ex.getMessage() +
                '\nStack Trace: ' +
                ex.getStackTraceString()
        );
    }
}