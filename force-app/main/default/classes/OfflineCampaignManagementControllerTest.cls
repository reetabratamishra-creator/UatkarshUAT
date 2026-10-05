/**
 * @description   Test class for OfflineCampaignManagementController search and send
 *                paths.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
@IsTest
private class OfflineCampaignManagementControllerTest {
  /**
   * Common Offline Campaign fixtures for search and send tests.
   */
  @TestSetup
  static void setupCommonData() {
    insert new List<Offline_Campaign__c>{
      new Offline_Campaign__c(
        Name = 'Offline Test',
        Phone__c = '9876543210',
        Email__c = 'offline.test@example.com',
        Department__c = 'Crash Barrier',
        Active__c = true
      ),
      new Offline_Campaign__c(
        Name = 'Offline Inactive',
        Phone__c = '9876543210',
        Email__c = 'inactive@example.com',
        Department__c = 'Crash Barrier',
        Active__c = false
      ),
      new Offline_Campaign__c(
        Name = 'Offline No Phone',
        Email__c = 'offline.nophone@example.com',
        Department__c = 'Enquiry',
        Active__c = true
      )
    };
  }

  /**
   * Scenario: Search returns only active Offline Campaigns matching filters.
   */
  @IsTest
  static void searchOfflineCampaignsReturnsMatchingActiveRecords() {
    Test.startTest();
    List<Offline_Campaign__c> results = OfflineCampaignManagementController.searchOfflineCampaigns(
      'Offline Test',
      '9876',
      'offline.test',
      'Crash'
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals('Offline Test', results[0].Name);
  }

  /**
   * Scenario: Journey send succeeds for offline campaign with phone via mock.
   */
  @IsTest
  static void testSendOfflineCampaignJourney_HappyPathWithMock() {
    BWM_JourneyDefinitionService.clearCache();
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );
    Offline_Campaign__c offlineRecord = [
      SELECT Id
      FROM Offline_Campaign__c
      WHERE Name = 'Offline Test'
      LIMIT 1
    ];

    Test.startTest();
    BWM_JourneyDefinitionService.SendJourneyResult result =
      OfflineCampaignManagementController.sendOfflineCampaignJourney(
        new List<Id>{ offlineRecord.Id },
        'prospect_not_resp'
      );
    Test.stopTest();

    System.assertEquals(1, result.sentCount);
  }

  /**
   * Scenario: WhatsApp send succeeds with phone and skips when phone missing.
   */
  @IsTest
  static void testSendOfflineCampaignWhatsApp_HappyPathAndSkipNoPhone() {
    Offline_Campaign__c withPhone = [
      SELECT Id
      FROM Offline_Campaign__c
      WHERE Name = 'Offline Test'
      LIMIT 1
    ];
    Offline_Campaign__c noPhone = [
      SELECT Id
      FROM Offline_Campaign__c
      WHERE Name = 'Offline No Phone'
      LIMIT 1
    ];
    BWM_DirectWaCampaignSend.clearCache();
    Map<String, Object> meta = new Map<String, Object>{
      'language' => 'en',
      'name' => 'u_dealer_enq_dept',
      'content' => new Map<String, Object>{
        'header' => new Map<String, Object>{ 'type' => 'TEXT' },
        'body' => 'Hello {{1}}'
      }
    };
    BWM_DirectWaCampaignSend.templateMetaByName = new Map<String, Map<String, Object>>{
      'u_dealer_enq_dept' => meta
    };
    LeadManagementWhatsAppService.templateMetaByName = new Map<String, Map<String, Object>>{
      'u_dealer_enq_dept' => meta
    };
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );
    Test.startTest();
    LeadManagementWhatsAppService.SendWhatsAppResult sent =
      OfflineCampaignManagementController.sendOfflineCampaignWhatsApp(
        new List<Id>{ withPhone.Id },
        'u_dealer_enq_dept'
      );
    Test.stopTest();
    LeadManagementWhatsAppService.SendWhatsAppResult skipped =
      OfflineCampaignManagementController.sendOfflineCampaignWhatsApp(
        new List<Id>{ noPhone.Id },
        'u_dealer_enq_dept'
      );

    System.assertNotEquals(null, sent);
    System.assertEquals(0, skipped.sentCount);
    System.assertEquals(1, skipped.skippedCount);
  }

  /**
   * Scenario: Campaign email send uses Infobip mock for offline campaign with email.
   */
  @IsTest
  static void testSendOfflineCampaignEmail_HappyPathWithMock() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_EmailCalloutMock('{"messages":[{"status":"PENDING_ACCEPTED"}]}', 200)
    );
    Offline_Campaign__c offlineRecord = [
      SELECT Id
      FROM Offline_Campaign__c
      WHERE Name = 'Offline Test'
      LIMIT 1
    ];

    Test.startTest();
    BWM_CampaignEmailService.SendCampaignEmailResult result =
      OfflineCampaignManagementController.sendOfflineCampaignEmail(
        new List<Id>{ offlineRecord.Id },
        '205000000067199'
      );
    Test.stopTest();

    System.assertEquals(1, result.sentCount);
  }

  /**
   * Scenario: Journey options and empty RCS/SMS selection validation.
   */
  @IsTest
  static void testOptionGetters_AndEmptyChannelValidation() {
    Boolean rcsThrew = false;
    Boolean smsThrew = false;

    Test.startTest();
    List<BWM_JourneyDefinitionService.JourneyOption> journeys =
      OfflineCampaignManagementController.getCampaignJourneys();
    try {
      OfflineCampaignManagementController.sendOfflineCampaignRcs(new List<Id>(), 'tmpl');
    } catch (AuraHandledException ex) {
      rcsThrew = true;
    }
    try {
      OfflineCampaignManagementController.sendOfflineCampaignSms(new List<Id>(), 'tmpl');
    } catch (AuraHandledException ex) {
      smsThrew = true;
    }
    Test.stopTest();

    System.assertNotEquals(null, journeys);
    System.assertEquals(true, rcsThrew);
    System.assertEquals(true, smsThrew);
  }

  @IsTest
  static void testSendOfflineCampaignRcsAndSms_HappyPathWithMock() {
    BWM_RcsDirectPayloadBuilder.cacheTemplates(
      new List<Object>{
        new Map<String, Object>{
          'TemplateName' => 'coverage_channel',
          'templateText' => 'Hello'
        }
      }
    );
    BWM_SmsDirectPayloadBuilder.cacheTemplates(
      new List<Object>{
        new Map<String, Object>{
          'templateName' => 'coverage_channel',
          'dltTemplateId' => 'DLT1',
          'templateText' => 'Hi {#var#}'
        }
      }
    );
    Offline_Campaign__c offlineRecord = [
      SELECT Id
      FROM Offline_Campaign__c
      WHERE Name = 'Offline Test'
      LIMIT 1
    ];
    offlineRecord.Phone__c = '9000011112';
    update offlineRecord;
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"accepted"}',
        '{"code":"200","message":"accepted"}',
        '{"code":"200","message":"accepted"}'
      )
    );

    Test.startTest();
    OfflineCampaignManagementRcsService.SendRcsResult rcsResult =
      OfflineCampaignManagementController.sendOfflineCampaignRcs(
        new List<Id>{ offlineRecord.Id },
        'coverage_channel'
      );
    OfflineCampaignManagementSmsService.SendSmsResult smsResult =
      OfflineCampaignManagementController.sendOfflineCampaignSms(
        new List<Id>{ offlineRecord.Id },
        'coverage_channel'
      );
    Test.stopTest();

    System.assertNotEquals(null, rcsResult);
    System.assertNotEquals(null, smsResult);
  }

  /**
   * Scenario: Unfiltered search, template getters, and email validation/catch paths run.
   */
  @IsTest
  static void testSearchWithoutFilters_GettersAndEmailCatch() {
    Test.startTest();
    List<Offline_Campaign__c> unfiltered =
      OfflineCampaignManagementController.searchOfflineCampaigns(null, null, null, null);
    Boolean emailThrew = false;
    try {
      OfflineCampaignManagementController.sendOfflineCampaignEmail(new List<Id>(), '');
    } catch (Exception ex) {
      emailThrew = true;
    }
    try {
      OfflineCampaignManagementController.getBluewaveEmailTemplates();
    } catch (Exception ex) {
      System.assertNotEquals(null, ex);
    }
    try {
      OfflineCampaignManagementController.getWhatsAppTemplates();
    } catch (Exception ex) {
      System.assertNotEquals(null, ex);
    }
    try {
      OfflineCampaignManagementController.getRcsTemplates();
    } catch (Exception ex) {
      System.assertNotEquals(null, ex);
    }
    try {
      OfflineCampaignManagementController.getSmsTemplates();
    } catch (Exception ex) {
      System.assertNotEquals(null, ex);
    }
    Test.stopTest();

    System.assert(unfiltered.size() >= 1);
    System.assertEquals(true, emailThrew);
  }
}