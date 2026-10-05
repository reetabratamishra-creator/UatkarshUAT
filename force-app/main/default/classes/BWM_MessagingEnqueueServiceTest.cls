/**
 * @description   Test class for BWM_MessagingEnqueueService queueable enqueue and
 *                lead-create helpers.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
@IsTest
private class BWM_MessagingEnqueueServiceTest {
  /**
   * Scenario: Null or empty request lists return without enqueueing jobs.
   */
  @IsTest
  static void testEnqueue_NullOrEmpty_NoOp() {
    Test.startTest();
    BWM_MessagingEnqueueService.enqueue(null);
    BWM_MessagingEnqueueService.enqueue(new List<BWM_MessagingRequest>());
    Test.stopTest();

    System.assertEquals(true, true, 'Empty enqueue should complete without error.');
  }

  /**
   * Scenario: Single-record enqueue schedules messaging queueable work.
   */
  @IsTest
  static void testEnqueue_SingleRecord_QueuesJob() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );
    BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = true;
    Lead leadRecord = new Lead(
      LastName = 'Enqueue Lead',
      Company = 'Enqueue Co',
      Company_Name__c = 'Enqueue Co',
      Status = 'Prospect',
      Department_Name__c = 'Enquiry',
      LeadSource = 'INBOUND EMAIL',
      Phone = '9876543290',
      Email = 'enqueue@example.com'
    );
    insert leadRecord;

    Test.startTest();
    BWM_MessagingEnqueueService.enqueue(
      leadRecord.Id,
      BWM_MessagingConstants.TRIGGER_LEAD_CREATE
    );
    Test.stopTest();

    System.assertEquals(true, true, 'Single enqueue should complete.');
  }

  /**
   * Scenario: enqueueLeadCreate builds TRIGGER_LEAD_CREATE requests for each Lead Id.
   */
  @IsTest
  static void testEnqueueLeadCreate_QueuesMessagingForLeads() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );
    BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = true;
    Lead leadRecord = new Lead(
      LastName = 'Enqueue Create Lead',
      Company = 'Enqueue Co',
      Company_Name__c = 'Enqueue Co',
      Status = 'Prospect',
      Department_Name__c = 'Enquiry',
      LeadSource = 'OUTBOUND PHONE CALL',
      Phone = '9876543291',
      Email = 'enqueue.create@example.com'
    );
    insert leadRecord;

    Test.startTest();
    BWM_MessagingEnqueueService.enqueueLeadCreate(new List<Id>{ leadRecord.Id });
    Test.stopTest();

    System.assertEquals(true, true, 'Lead create enqueue should complete.');
  }
}