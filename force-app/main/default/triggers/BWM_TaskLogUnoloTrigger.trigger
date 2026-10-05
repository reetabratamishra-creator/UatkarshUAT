trigger BWM_TaskLogUnoloTrigger on Task_Log__c (after insert, after update) {
  if (!TriggerEnableService.isEnabled(TriggerEnableService.BWM_TASK_LOG_UNOLO)) {
    return;
  }

  try {
    if (Trigger.isInsert) {
      BWM_TaskLogUnoloTriggerHandler.handleAfterInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      BWM_TaskLogUnoloTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
  } catch (Exception ex) {
    System.debug(
      LoggingLevel.ERROR,
      'BWM_TaskLogUnoloTrigger failed: ' + ex.getMessage()
    );
  }
}