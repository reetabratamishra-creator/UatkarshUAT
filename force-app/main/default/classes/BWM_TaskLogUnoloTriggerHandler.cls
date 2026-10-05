/**
 * @description   Task Log handler that enqueues the Unolo client visit journey when
 *                MOM and checkout coordinates are populated.
 * @author        Anshita Chanda
 * @date          2026-08-13
 */
public without sharing class BWM_TaskLogUnoloTriggerHandler {
  @TestVisible
  private static Boolean skipForTests = false;

  @TestVisible
  private static Boolean forceExceptionForTests = false;

  @TestVisible
  private static Integer testEnqueueCount = 0;

  @TestVisible
  static void resetTestState() {
    skipForTests = false;
    forceExceptionForTests = false;
    testEnqueueCount = 0;
  }

  /**
   * @description Evaluates newly inserted Task Logs and enqueues Unolo journey sends
   *              when required fields are set.
   * @param newRecords Task Log records inserted in the trigger context.
   */
  public static void handleAfterInsert(List<Task_Log__c> newRecords) {
    processEligibleTaskLogs(newRecords);
  }

  /**
   * @description Evaluates updated Task Logs and enqueues Unolo journey sends when MOM
   *              and checkout coordinates become populated.
   * @param newRecords Task Log records in the after-update trigger context.
   * @param oldMap Prior Task Log versions keyed by Id.
   */
  public static void handleAfterUpdate(
    List<Task_Log__c> newRecords,
    Map<Id, Task_Log__c> oldMap
  ) {
    if (newRecords == null || newRecords.isEmpty() || oldMap == null) {
      return;
    }

    List<Task_Log__c> newlyEligibleRecords = new List<Task_Log__c>();
    for (Task_Log__c taskLogRecord : newRecords) {
      Task_Log__c priorRecord = oldMap.get(taskLogRecord.Id);
      if (
        hasRequiredUnoloFields(taskLogRecord) &&
        !hasRequiredUnoloFields(priorRecord)
      ) {
        newlyEligibleRecords.add(taskLogRecord);
      }
    }

    processEligibleTaskLogs(newlyEligibleRecords);
  }

  private static void processEligibleTaskLogs(List<Task_Log__c> candidateRecords) {
    if (Test.isRunningTest() && forceExceptionForTests) {
      throw new AuraHandledException('Forced test exception');
    }
    if (Test.isRunningTest() && skipForTests) {
      return;
    }
    if (candidateRecords == null || candidateRecords.isEmpty()) {
      return;
    }

    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    if (settings == null || settings.Is_Enabled__c != true) {
      return;
    }

    List<Id> taskLogIdsToSend = selectEligibleTaskLogIds(candidateRecords);
    if (taskLogIdsToSend.isEmpty()) {
      return;
    }

    enqueueSend(taskLogIdsToSend);
  }

  @TestVisible
  private static Boolean hasRequiredUnoloFields(Task_Log__c taskLogRecord) {
    return taskLogRecord != null &&
      String.isNotBlank(taskLogRecord.MOM__c) &&
      taskLogRecord.Checked_Out_Latitude__c != null &&
      taskLogRecord.Checked_Out_Longitude__c != null;
  }

  @TestVisible
  private static List<Id> selectEligibleTaskLogIds(List<Task_Log__c> taskLogRecords) {
    List<Id> taskLogIdsToSend = new List<Id>();

    for (Task_Log__c taskLogRecord : taskLogRecords) {
      if (
        taskLogRecord == null ||
        taskLogRecord.Id == null ||
        taskLogRecord.Account__c == null ||
        !hasRequiredUnoloFields(taskLogRecord)
      ) {
        continue;
      }

      taskLogIdsToSend.add(taskLogRecord.Id);
    }

    return taskLogIdsToSend;
  }

  private static void enqueueSend(List<Id> taskLogIdsToSend) {
    if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
      if (Test.isRunningTest()) {
        testEnqueueCount++;
      }
      System.enqueueJob(new BWM_TaskLogUnoloJourneyQueueable(taskLogIdsToSend));
      return;
    }
    // Journey callout must run before email DML in the same transaction.
    BWM_TaskLogUnoloJourneyService.sendForTaskLogIds(taskLogIdsToSend);
    // Email is independent of WhatsApp/journey success.
    BWM_TaskLogUnoloEmailService.sendForTaskLogIds(taskLogIdsToSend);
  }
}