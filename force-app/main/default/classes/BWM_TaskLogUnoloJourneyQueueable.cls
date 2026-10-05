/**
 * @description   Queueable job that sends the Unolo client visit journey for Task Logs.
 * @author        Anshita Chanda
 * @date          2026-08-13
 */
public without sharing class BWM_TaskLogUnoloJourneyQueueable implements Queueable, Database.AllowsCallouts {
  private final List<Id> taskLogIds;

  public BWM_TaskLogUnoloJourneyQueueable(List<Id> taskLogIds) {
    this.taskLogIds = taskLogIds == null
      ? new List<Id>()
      : new List<Id>(taskLogIds);
  }

  public void execute(QueueableContext context) {
    // Journey callout must run before email DML in the same transaction.
    BWM_TaskLogUnoloJourneyService.sendForTaskLogIds(taskLogIds);
    // Email is independent of WhatsApp/journey success.
    BWM_TaskLogUnoloEmailService.sendForTaskLogIds(taskLogIds);
  }
}