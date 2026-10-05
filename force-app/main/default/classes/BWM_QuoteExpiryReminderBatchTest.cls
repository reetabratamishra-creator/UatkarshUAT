/**
 * @description   Test class for BWM_QuoteExpiryReminderBatch quote-expiry reminder
 *                enqueue paths.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
@IsTest
private class BWM_QuoteExpiryReminderBatchTest {
  /**
   * Scenario: Opportunity with Quotation_Date tomorrow is enqueued for reminder.
   */
  @IsTest
  static void testExecute_MatchingQuotationDate_EnqueuesReminder() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    User ownerUser = [
      SELECT Id, Phone, MobilePhone
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    String originalPhone = ownerUser.Phone;
    String originalMobile = ownerUser.MobilePhone;
    ownerUser.Phone = null;
    ownerUser.MobilePhone = '6290459144';
    update ownerUser;

    Account accountRecord = new Account(Name = 'Quote Expiry Batch Account', Phone = '6290459145');
    insert accountRecord;

    Contact contactRecord = new Contact(
      LastName = 'Quote Expiry',
      FirstName = 'Batch',
      AccountId = accountRecord.Id
    );
    insert contactRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Quote Expiry Batch Opp',
      AccountId = accountRecord.Id,
      ContactId = contactRecord.Id,
      StageName = BWM_MessagingConstants.STAGE_NURTURE,
      CloseDate = Date.today().addDays(30),
      Quotation_Date__c = System.today().addDays(1)
    );
    insert opportunityRecord;

    Test.startTest();
    new BWM_QuoteExpiryReminderBatch()
      .execute(null, new List<Opportunity>{ opportunityRecord });
    new BWM_QuoteExpiryReminderBatch().execute(null);
    Test.stopTest();

    Integer queueableJobs = [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE JobType = 'Queueable' AND Status = 'Completed'
    ];
    System.assert(queueableJobs >= 1, 'Batch should enqueue messaging work.');

    ownerUser.Phone = originalPhone;
    ownerUser.MobilePhone = originalMobile;
    update ownerUser;
  }

  /**
   * Scenario: Batch start query locator returns without error for tomorrow's date filter.
   */
  @IsTest
  static void testStart_ReturnsQueryLocator() {
    Test.startTest();
    Database.QueryLocator locator = new BWM_QuoteExpiryReminderBatch().start(null);
    Test.stopTest();

    System.assertNotEquals(null, locator);
  }
}