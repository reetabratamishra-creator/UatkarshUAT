public without sharing class BWM_EmailEnqueueService {
  public static void enqueue(List<BWM_EmailRequest> requests) {
    if (requests == null || requests.isEmpty()) {
      return;
    }

    if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
      System.debug(
        LoggingLevel.WARN,
        'BWM email skipped: queueable limit reached in this transaction.'
      );
      return;
    }

    System.enqueueJob(new BWM_EmailQueueable(requests));
  }

  public static void enqueueLeadCreate(List<Id> leadIds) {
    List<BWM_EmailRequest> requests = new List<BWM_EmailRequest>();
    for (Id leadId : leadIds) {
      requests.add(
        new BWM_EmailRequest(leadId, BWM_EmailConstants.TRIGGER_LEAD_CREATE)
      );
    }
    enqueue(requests);
  }

  public static void enqueue(Id recordId, String triggerPoint) {
    enqueue(
      new List<BWM_EmailRequest>{
        new BWM_EmailRequest(recordId, triggerPoint)
      }
    );
  }
}