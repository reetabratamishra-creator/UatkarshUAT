/**
 * @description   Test class for OpportunityQuoteController — quote send validation
 *                and AuraHandledException paths.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
@IsTest
private class OpportunityQuoteControllerTest {
  @TestSetup
  static void setupCommonData() {
    Account accountRecord = new Account(Name = 'Quote Controller Account');
    insert accountRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Quote Controller Opp',
      AccountId = accountRecord.Id,
      StageName = 'Nurture',
      CloseDate = Date.today().addDays(30),
      Department_Name__c = 'Crash Barrier',
      Customer_Journey__c = BWM_MessagingConstants.CUSTOMER_JOURNEY_REFER_DEALER
    );
    insert opportunityRecord;
  }

  /**
   * Scenario: sendQuoteToCustomer with a null Opportunity Id throws AuraHandledException.
   */
  @IsTest
  static void testSendQuoteToCustomer_NullId_ThrowsError() {
    Boolean threw = false;

    Test.startTest();
    try {
      OpportunityQuoteController.sendQuoteToCustomer(null);
    } catch (AuraHandledException ex) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw, 'Null Opportunity Id should throw.');
  }

  /**
   * Scenario: Opportunity without SyncedQuoteId cannot send quote to customer.
   */
  @IsTest
  static void testSendQuoteToCustomer_NoSyncedQuote_ThrowsError() {
    Opportunity opportunityRecord = [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'Quote Controller Opp'
      LIMIT 1
    ];
    Boolean threw = false;

    Test.startTest();
    try {
      OpportunityQuoteController.sendQuoteToCustomer(opportunityRecord.Id);
    } catch (AuraHandledException ex) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw, 'Missing SyncedQuote should throw.');
  }

  /**
   * Scenario: Non-Opportunity Id returns Opportunity not found from the journey service.
   */
  @IsTest
  static void testSendQuoteToCustomer_OpportunityNotFound_ThrowsError() {
    Account accountRecord = [SELECT Id FROM Account LIMIT 1];
    Boolean threw = false;

    Test.startTest();
    try {
      OpportunityQuoteController.sendQuoteToCustomer(accountRecord.Id);
    } catch (Exception ex) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw, 'Wrong Id type should throw Opportunity not found.');
  }

  @IsTest
  static void testSendQuoteToCustomer_HappyPathThroughController() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"WhatsApp message accepted."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Opportunity opportunityRecord = [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'Quote Controller Opp'
      LIMIT 1
    ];
    Quote quoteRecord = new Quote(
      Name = 'Controller Quote',
      OpportunityId = opportunityRecord.Id
    );
    insert quoteRecord;

    Contact contactRecord = new Contact(
      LastName = 'Quote Controller Contact',
      AccountId = [SELECT Id FROM Account LIMIT 1].Id,
      Phone = '9876543299',
      MobilePhone = '9876543299',
      Email = 'quote.controller@example.com'
    );
    insert contactRecord;
    insert new OpportunityContactRole(
      OpportunityId = opportunityRecord.Id,
      ContactId = contactRecord.Id,
      IsPrimary = true,
      Role = 'Decision Maker'
    );

    update new Opportunity(
      Id = opportunityRecord.Id,
      SyncedQuoteId = quoteRecord.Id,
      Quotation_Date__c = Date.today(),
      Quote_Number__c = 'QC-1001'
    );

    Test.startTest();
    DealerOpportunityWhatsAppService.SendWhatsAppResult result =
      OpportunityQuoteController.sendQuoteToCustomer(opportunityRecord.Id);
    Test.stopTest();

    System.assertEquals(1, result.sentCount);
  }

  @IsTest
  static void testSendQuoteToCustomer_SkippedResult_ThrowsWithMessage() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock('INVALID_JSON_BODY', 'INVALID_JSON_BODY')
    );

    Opportunity opportunityRecord = [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'Quote Controller Opp'
      LIMIT 1
    ];
    Quote quoteRecord = new Quote(
      Name = 'Skipped Controller Quote',
      OpportunityId = opportunityRecord.Id
    );
    insert quoteRecord;

    Contact contactRecord = new Contact(
      LastName = 'Skipped Controller Contact',
      AccountId = [SELECT Id FROM Account LIMIT 1].Id,
      Phone = '9876543288',
      MobilePhone = '9876543288',
      Email = 'skipped.controller@example.com'
    );
    insert contactRecord;
    insert new OpportunityContactRole(
      OpportunityId = opportunityRecord.Id,
      ContactId = contactRecord.Id,
      IsPrimary = true,
      Role = 'Decision Maker'
    );

    update new Opportunity(
      Id = opportunityRecord.Id,
      SyncedQuoteId = quoteRecord.Id,
      Quotation_Date__c = Date.today(),
      Quote_Number__c = 'QC-1002',
      Customer_Journey__c = BWM_MessagingConstants.CUSTOMER_JOURNEY_REFER_DEALER
    );

    Boolean threw = false;
    Test.startTest();
    try {
      OpportunityQuoteController.sendQuoteToCustomer(opportunityRecord.Id);
    } catch (AuraHandledException ex) {
      threw = true;
      System.assert(String.isNotBlank(ex.getMessage()));
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }
}