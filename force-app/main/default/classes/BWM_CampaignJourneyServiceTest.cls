/**
 * @description   Test class for BWM_CampaignJourneyService — campaign journey send
 *                scenarios.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
@IsTest
private class BWM_CampaignJourneyServiceTest {
  private static final String SUCCESS_BODY =
    '{"code":"200","message":"Journey message enqueued successfully."}';

  @IsTest
  static void sendToLeadsDispatchesCampaignJourneyPayload() {
    BWM_JourneyDefinitionService.clearCache();
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(SUCCESS_BODY, '{"code":"200","message":"unused"}')
    );

    Lead leadRecord = insertLead('9876543210');

    Test.startTest();
    BWM_JourneyDefinitionService.SendJourneyResult result =
      BWM_CampaignJourneyService.sendToLeads(
        new List<Id>{ leadRecord.Id },
        'prospect_not_resp'
      );
    Test.stopTest();

    System.assertEquals(1, result.sentCount);
    System.assertEquals(0, result.skippedCount);
  }

  @IsTest
  static void sendToOpportunitiesDispatchesCampaignJourneyPayload() {
    BWM_JourneyDefinitionService.clearCache();
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(SUCCESS_BODY, '{"code":"200","message":"unused"}')
    );

    Account accountRecord = new Account(Name = 'Campaign Opp Account');
    insert accountRecord;

    Contact contactRecord = new Contact(
      LastName = 'Campaign Opp Contact',
      AccountId = accountRecord.Id,
      Phone = '9876543211',
      MobilePhone = '9876543211'
    );
    insert contactRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Campaign Opp',
      StageName = 'Nurture',
      CloseDate = Date.today().addDays(30),
      AccountId = accountRecord.Id,
      Department_Name__c = 'Crash Barrier',
      Phone__c = '9876543211'
    );
    insert opportunityRecord;

    insert new OpportunityContactRole(
      OpportunityId = opportunityRecord.Id,
      ContactId = contactRecord.Id,
      IsPrimary = true,
      Role = 'Decision Maker'
    );

    Test.startTest();
    BWM_JourneyDefinitionService.SendJourneyResult result =
      BWM_CampaignJourneyService.sendToOpportunities(
        new List<Id>{ opportunityRecord.Id },
        'prospect_not_resp'
      );
    Test.stopTest();

    System.assertEquals(1, result.sentCount);
  }

  @IsTest
  static void sendToContactsDispatchesCampaignJourneyPayload() {
    BWM_JourneyDefinitionService.clearCache();
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(SUCCESS_BODY, '{"code":"200","message":"unused"}')
    );

    Contact contactRecord = new Contact(
      LastName = 'Campaign Contact',
      Phone = '9876543212',
      MobilePhone = '9876543212'
    );
    insert contactRecord;

    Test.startTest();
    BWM_JourneyDefinitionService.SendJourneyResult result =
      BWM_CampaignJourneyService.sendToContacts(
        new List<Id>{ contactRecord.Id },
        'prospect_not_resp'
      );
    Test.stopTest();

    System.assertEquals(1, result.sentCount);
  }

  @IsTest
  static void sendToAccountsSkipsWhenPhoneMissing() {
    BWM_JourneyDefinitionService.clearCache();
    Account accountRecord = new Account(Name = 'No Phone Account');
    insert accountRecord;

    Test.startTest();
    BWM_JourneyDefinitionService.SendJourneyResult result =
      BWM_CampaignJourneyService.sendToAccounts(
        new List<Id>{ accountRecord.Id },
        'prospect_not_resp'
      );
    Test.stopTest();

    System.assertEquals(0, result.sentCount);
    System.assertEquals(1, result.skippedCount);
  }

  @IsTest
  static void sendToOfflineCampaignsDispatchesCampaignJourneyPayload() {
    BWM_JourneyDefinitionService.clearCache();
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(SUCCESS_BODY, '{"code":"200","message":"unused"}')
    );

    Offline_Campaign__c offlineRecord = new Offline_Campaign__c(
      Name = 'Offline Campaign Journey',
      Phone__c = '9876543213',
      Email__c = 'offline@test.com',
      Department__c = 'Crash Barrier',
      Active__c = true
    );
    insert offlineRecord;

    Test.startTest();
    BWM_JourneyDefinitionService.SendJourneyResult result =
      BWM_CampaignJourneyService.sendToOfflineCampaigns(
        new List<Id>{ offlineRecord.Id },
        'prospect_not_resp'
      );
    Test.stopTest();

    System.assertEquals(1, result.sentCount);
  }

  @IsTest
  static void sendToLeadsRecordsFailureWhenApiReturnsError() {
    BWM_JourneyDefinitionService.clearCache();
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"500","message":"Journey failed."}',
        '{"code":"500","message":"unused"}'
      )
    );

    Lead leadRecord = insertLead('9876543214');

    Test.startTest();
    BWM_JourneyDefinitionService.SendJourneyResult result =
      BWM_CampaignJourneyService.sendToLeads(
        new List<Id>{ leadRecord.Id },
        'prospect_not_resp'
      );
    Test.stopTest();

    System.assertEquals(0, result.sentCount);
    System.assertEquals(1, result.skippedCount);
    System.assert(!result.messages.isEmpty());
  }

  @IsTest
  static void validateJourneyRequestRequiresSelection() {
    Boolean thrown = false;
    try {
      BWM_CampaignJourneyService.sendToContacts(new List<Id>(), 'prospect_not_resp');
    } catch (AuraHandledException ex) {
      thrown = true;
    }
    System.assertEquals(true, thrown);
  }

  private static Lead insertLead(String phone) {
    BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = true;
    Lead leadRecord = new Lead(
      LastName = 'Campaign Journey',
      Company = 'Test Co',
      Company_Name__c = 'Test Co',
      Status = 'Prospect',
      Department_Name__c = 'Crash Barrier',
      Phone = phone,
      Email = 'test@example.com'
    );
    insert leadRecord;
    BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = false;
    return leadRecord;
  }
}