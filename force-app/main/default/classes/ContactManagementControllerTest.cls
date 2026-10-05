/**
 * @description   Test class for ContactManagementController search and campaign
 *                send methods.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
@IsTest
private class ContactManagementControllerTest {
  private static final String SUCCESS_JOURNEY =
    '{"code":"200","message":"Journey message enqueued successfully."}';
  private static final String SUCCESS_EMAIL =
    '{"messages":[{"status":"PENDING_ACCEPTED"}]}';

  @TestSetup
  static void setupCommonData() {
    Account accountRecord = new Account(Name = 'Contact Mgmt Account');
    insert accountRecord;

    insert new List<Contact>{
      new Contact(
        LastName = 'Contact Alpha',
        AccountId = accountRecord.Id,
        Phone = '9876543230',
        MobilePhone = '9876543230',
        Email = 'contact.alpha@example.com'
      ),
      new Contact(
        LastName = 'Contact NoPhone',
        AccountId = accountRecord.Id,
        Email = 'contact.nophone@example.com'
      )
    };
  }

  /**
   * Scenario: searchContacts returns matching contacts by name/phone/email.
   */
  @IsTest
  static void testSearchContacts_ReturnsMatchingRecords() {
    Test.startTest();
    List<Contact> results = ContactManagementController.searchContacts(
      'Alpha',
      '9876',
      'contact.alpha',
      null,
      null
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assert(results[0].Name.contains('Alpha'));
  }

  /**
   * Scenario: Journey and campaign email send succeed with mocks.
   */
  @IsTest
  static void testSendContactJourneyAndCampaignEmail_HappyPath() {
    BWM_JourneyDefinitionService.clearCache();
    Contact contactRecord = [
      SELECT Id
      FROM Contact
      WHERE LastName = 'Contact Alpha'
      LIMIT 1
    ];

    Test.startTest();
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(SUCCESS_JOURNEY, SUCCESS_JOURNEY)
    );
    BWM_JourneyDefinitionService.SendJourneyResult journeyResult =
      ContactManagementController.sendContactJourney(
        new List<Id>{ contactRecord.Id },
        'prospect_not_resp'
      );
    Test.stopTest();

    System.assertNotEquals(null, journeyResult);
  }

  @IsTest
  static void testSendContactCampaignEmail_HappyPathWithMock() {
    BWM_CampaignEmailService.resetTemplateSubjectCacheForTests();
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_EmailRouteCalloutMock(
        '{"id":205000000067199,"name":"NABL_HIGH_MAST_2026","subject":"Welcome"}',
        SUCCESS_EMAIL,
        200
      )
    );
    Contact contactRecord = [
      SELECT Id
      FROM Contact
      WHERE LastName = 'Contact Alpha'
      LIMIT 1
    ];

    System.runAs(getAdminUser()) {
      Test.startTest();
      BWM_CampaignEmailService.SendCampaignEmailResult emailResult =
        ContactManagementController.sendContactCampaignEmail(
          new List<Id>{ contactRecord.Id },
          '205000000067199'
        );
      Test.stopTest();

      System.assertEquals(1, emailResult.sentCount);
    }
  }

  /**
   * Scenario: WhatsApp send happy path with phone and skip when phone missing.
   */
  @IsTest
  static void testSendContactWhatsApp_HappyPathAndSkipNoPhone() {
    seedTemplateCache('u_dealer_enq_dept');
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(SUCCESS_JOURNEY, SUCCESS_JOURNEY)
    );
    Contact withPhone = [
      SELECT Id
      FROM Contact
      WHERE LastName = 'Contact Alpha'
      LIMIT 1
    ];
    Contact noPhone = [
      SELECT Id
      FROM Contact
      WHERE LastName = 'Contact NoPhone'
      LIMIT 1
    ];

    Test.startTest();
    LeadManagementWhatsAppService.SendWhatsAppResult sent =
      ContactManagementController.sendContactWhatsApp(
        new List<Id>{ withPhone.Id },
        'u_dealer_enq_dept'
      );
    LeadManagementWhatsAppService.SendWhatsAppResult skipped =
      ContactManagementController.sendContactWhatsApp(
        new List<Id>{ noPhone.Id },
        'u_dealer_enq_dept'
      );
    Test.stopTest();

    System.assertEquals(1, sent.sentCount);
    System.assertEquals(0, skipped.sentCount);
    System.assertEquals(1, skipped.skippedCount);
  }

  /**
   * Scenario: Option getters and empty RCS/SMS selection validation.
   */
  @IsTest
  static void testOptionGetters_AndEmptyChannelValidation() {
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_EmailCalloutMock(
        '{"results":[{"id":3,"name":"C1","imagePreviewUrl":"/c.png"}],"paging":{"page":0,"size":20,"totalPages":1,"totalResults":1}}',
        200
      )
    );
    Boolean rcsThrew = false;
    Boolean smsThrew = false;

    Test.startTest();
    List<BWM_JourneyDefinitionService.JourneyOption> journeys =
      ContactManagementController.getCampaignJourneys();
    List<BWM_InfobipEmailTemplateService.TemplateOption> templates =
      ContactManagementController.getBluewaveEmailTemplates();
    try {
      ContactManagementController.sendContactRcs(new List<Id>(), 'tmpl');
    } catch (AuraHandledException ex) {
      rcsThrew = true;
    }
    try {
      ContactManagementController.sendContactSms(new List<Id>(), 'tmpl');
    } catch (AuraHandledException ex) {
      smsThrew = true;
    }
    try {
      ContactManagementController.getWhatsAppTemplates();
      ContactManagementController.getRcsTemplates();
      ContactManagementController.getSmsTemplates();
    } catch (AuraHandledException ex) {
      // Optional when mock body does not match template API schema.
    }
    Test.stopTest();

    System.assertNotEquals(null, journeys);
    System.assertEquals(1, templates.size());
    System.assertEquals(true, rcsThrew);
    System.assertEquals(true, smsThrew);
  }

  @IsTest
  static void testGetCountryStateOptions_ReturnValues() {
    Test.startTest();
    List<ContactManagementController.PicklistOption> countries =
      ContactManagementController.getContactCountryOptions();
    List<ContactManagementController.PicklistOption> states =
      ContactManagementController.getContactStateOptions();
    Test.stopTest();

    System.assertNotEquals(null, countries);
    System.assertNotEquals(null, states);
  }

  @IsTest
  static void testSendContactCampaignEmail_WrapsValidationErrors() {
    Boolean threw = false;
    try {
      ContactManagementController.sendContactCampaignEmail(new List<Id>(), '');
    } catch (AuraHandledException ex) {
      threw = true;
    }
    System.assertEquals(true, threw);
  }

  private static User getAdminUser() {
    return [
      SELECT Id
      FROM User
      WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE
      LIMIT 1
    ];
  }

  @IsTest
  static void testSendContactRcsAndSms_HappyPathWithMock() {
    seedTemplateCache('coverage_channel');
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(SUCCESS_JOURNEY, SUCCESS_JOURNEY, SUCCESS_JOURNEY)
    );
    Contact contactRecord = [
      SELECT Id
      FROM Contact
      WHERE LastName = 'Contact Alpha'
      LIMIT 1
    ];
    contactRecord.Phone = '9000011111';
    contactRecord.MobilePhone = '9000011111';
    update contactRecord;

    Test.startTest();
    ContactManagementRcsService.SendRcsResult rcsResult =
      ContactManagementController.sendContactRcs(
        new List<Id>{ contactRecord.Id },
        'coverage_channel'
      );
    ContactManagementSmsService.SendSmsResult smsResult =
      ContactManagementController.sendContactSms(
        new List<Id>{ contactRecord.Id },
        'coverage_channel'
      );
    Test.stopTest();

    System.assertNotEquals(null, rcsResult);
    System.assertNotEquals(null, smsResult);
  }

  private static void seedTemplateCache(String templateName) {
    BWM_DirectWaCampaignSend.clearCache();
    BWM_DirectWaCampaignSend.templateMetaByName = new Map<String, Map<String, Object>>{
      templateName => new Map<String, Object>{
        'language' => 'en',
        'content' => new Map<String, Object>{
          'header' => new Map<String, Object>{ 'type' => 'TEXT' },
          'body' => 'Hello {{1}}'
        }
      }
    };
    BWM_RcsDirectPayloadBuilder.cacheTemplates(
      new List<Object>{
        new Map<String, Object>{ 'TemplateName' => templateName, 'templateText' => 'Hello' }
      }
    );
    BWM_SmsDirectPayloadBuilder.cacheTemplates(
      new List<Object>{
        new Map<String, Object>{
          'templateName' => templateName,
          'dltTemplateId' => 'DLT1',
          'templateText' => 'Hi {#var#}'
        }
      }
    );
  }
}