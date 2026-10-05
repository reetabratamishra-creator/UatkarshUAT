/**
 * @description   Test class for BWM_CampaignEmailService Infobip campaign email
 *                send paths.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
@IsTest
private class BWM_CampaignEmailServiceTest {
  private static final String SUCCESS_BODY = '{"messages":[{"status":"PENDING_ACCEPTED"}]}';
  private static final String TEMPLATE_ID = '205000000067199';
  private static final String TEMPLATE_SUBJECT = 'Welcome to Utkarsh Steel';
  private static final String TEMPLATE_DETAIL_BODY =
    '{"id":205000000067199,"name":"NABL_HIGH_MAST_2026","subject":"' +
    TEMPLATE_SUBJECT +
    '"}';

  private static HttpCalloutMock buildCampaignEmailMock(
    String sendResponseBody,
    Integer sendStatusCode
  ) {
    return new BWM_EmailRouteCalloutMock(
      TEMPLATE_DETAIL_BODY,
      sendResponseBody,
      sendStatusCode
    );
  }

  @TestSetup
  static void setupCommonData() {
    BWM_LeadMessagingTriggerHandler.skipEnqueueForTests = true;
    BWM_EmailLeadTriggerHandler.skipEnqueueForTests = true;

    Lead leadWithEmail = new Lead(
      LastName = 'Campaign Email Lead',
      Company = 'Test Co',
      Company_Name__c = 'Test Co',
      Status = 'Prospect',
      Department_Name__c = 'Crash Barrier',
      Phone = '9876543210',
      Email = 'campaign.lead@example.com'
    );
    Lead leadNoEmail = new Lead(
      LastName = 'No Email Lead',
      Company = 'Test Co',
      Company_Name__c = 'Test Co',
      Status = 'Prospect',
      Department_Name__c = 'Crash Barrier',
      Phone = '9876543211'
    );
    insert new List<Lead>{ leadWithEmail, leadNoEmail };

    Account accountRecord = new Account(
      Name = 'Campaign Email Account',
      Phone = '9876543212',
      Email__c = 'campaign.account@example.com'
    );
    insert accountRecord;

    Contact contactWithEmail = new Contact(
      LastName = 'Campaign Email Contact',
      AccountId = accountRecord.Id,
      Phone = '9876543213',
      Email = 'campaign.contact@example.com'
    );
    Contact contactNoEmail = new Contact(
      LastName = 'No Email Contact',
      AccountId = accountRecord.Id,
      Phone = '9876543214'
    );
    insert new List<Contact>{ contactWithEmail, contactNoEmail };

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Campaign Email Opp',
      AccountId = accountRecord.Id,
      StageName = 'Nurture',
      CloseDate = Date.today().addDays(30),
      Department_Name__c = 'Crash Barrier'
    );
    insert opportunityRecord;

    insert new OpportunityContactRole(
      OpportunityId = opportunityRecord.Id,
      ContactId = contactWithEmail.Id,
      IsPrimary = true,
      Role = 'Decision Maker'
    );

    insert new Offline_Campaign__c(
      Name = 'Campaign Email Offline',
      Phone__c = '9876543215',
      Email__c = 'campaign.offline@example.com',
      Department__c = 'Crash Barrier',
      Active__c = true
    );
    insert new Offline_Campaign__c(
      Name = 'No Email Offline',
      Phone__c = '9876543216',
      Department__c = 'Crash Barrier',
      Active__c = true
    );
  }

  /**
   * Scenario: Validation requires at least one record Id and a template Id.
   */
  @IsTest
  static void testValidateRequest_EmptyIdsOrBlankTemplate_ThrowsError() {
    Boolean emptyIdsThrew = false;
    Boolean blankTemplateThrew = false;
    Lead leadRecord = [SELECT Id FROM Lead WHERE Email != null LIMIT 1];

    Test.startTest();
    try {
      BWM_CampaignEmailService.sendToLeads(new List<Id>(), TEMPLATE_ID);
    } catch (AuraHandledException ex) {
      emptyIdsThrew = true;
    }
    try {
      BWM_CampaignEmailService.sendToLeads(new List<Id>{ leadRecord.Id }, '');
    } catch (AuraHandledException ex) {
      blankTemplateThrew = true;
    }
    Test.stopTest();

    System.assertEquals(true, emptyIdsThrew);
    System.assertEquals(true, blankTemplateThrew);
  }

  /**
   * Scenario: Lead with email sends successfully via Infobip mock; lead without email is skipped.
   */
  @IsTest
  static void testSendToLeads_HappyPathAndSkipNoEmail() {
    BWM_CampaignEmailService.resetTemplateSubjectCacheForTests();
    Test.setMock(
      HttpCalloutMock.class,
      buildCampaignEmailMock(SUCCESS_BODY, 200)
    );
    Lead withEmail = [SELECT Id FROM Lead WHERE Email != null LIMIT 1];
    Lead noEmail = [SELECT Id FROM Lead WHERE Email = null LIMIT 1];

    Test.startTest();
    BWM_CampaignEmailService.SendCampaignEmailResult result =
      BWM_CampaignEmailService.sendToLeads(
        new List<Id>{ withEmail.Id, noEmail.Id },
        TEMPLATE_ID
      );
    Test.stopTest();

    System.assertEquals(1, result.sentCount);
    System.assertEquals(1, result.skippedCount);
    System.assert(!result.messages.isEmpty());

    List<Email_Log__c> logs = [
      SELECT Campaign_Email_Subject__c, Template_Name__c, Status__c
      FROM Email_Log__c
      WHERE Related_Record_Id__c = :String.valueOf(withEmail.Id)
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals('NABL_HIGH_MAST_2026', logs[0].Template_Name__c);
    System.assertEquals(TEMPLATE_SUBJECT, logs[0].Campaign_Email_Subject__c);
    System.assertEquals('Sent', logs[0].Status__c);
  }

  /**
   * Scenario: Opportunity campaign email uses primary contact email with mock callout.
   */
  @IsTest
  static void testSendToOpportunities_HappyPathWithPrimaryContact() {
    BWM_CampaignEmailService.resetTemplateSubjectCacheForTests();
    Test.setMock(
      HttpCalloutMock.class,
      buildCampaignEmailMock(SUCCESS_BODY, 200)
    );
    Opportunity opportunityRecord = [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'Campaign Email Opp'
      LIMIT 1
    ];

    Test.startTest();
    BWM_CampaignEmailService.SendCampaignEmailResult result =
      BWM_CampaignEmailService.sendToOpportunities(
        new List<Id>{ opportunityRecord.Id },
        TEMPLATE_ID
      );
    Test.stopTest();

    System.assertEquals(1, result.sentCount);
    System.assertEquals(0, result.skippedCount);
  }

  /**
   * Scenario: Account campaign email sends when Email__c is populated.
   */
  @IsTest
  static void testSendToAccounts_HappyPath() {
    BWM_CampaignEmailService.resetTemplateSubjectCacheForTests();
    Test.setMock(
      HttpCalloutMock.class,
      buildCampaignEmailMock(SUCCESS_BODY, 200)
    );
    Account accountRecord = [
      SELECT Id
      FROM Account
      WHERE Name = 'Campaign Email Account'
      LIMIT 1
    ];

    System.runAs(getAdminUser()) {
      Test.startTest();
      BWM_CampaignEmailService.SendCampaignEmailResult result =
        BWM_CampaignEmailService.sendToAccounts(
          new List<Id>{ accountRecord.Id },
          TEMPLATE_ID
        );
      Test.stopTest();

      System.assertEquals(1, result.sentCount);
    }
  }

  /**
   * Scenario: Contact campaign email sends or skips based on email presence.
   */
  @IsTest
  static void testSendToContacts_HappyPathAndSkipNoEmail() {
    BWM_CampaignEmailService.resetTemplateSubjectCacheForTests();
    Test.setMock(
      HttpCalloutMock.class,
      buildCampaignEmailMock(SUCCESS_BODY, 200)
    );
    Contact withEmail = [
      SELECT Id
      FROM Contact
      WHERE LastName = 'Campaign Email Contact'
      LIMIT 1
    ];
    Contact noEmail = [
      SELECT Id
      FROM Contact
      WHERE LastName = 'No Email Contact'
      LIMIT 1
    ];

    System.runAs(getAdminUser()) {
      Test.startTest();
      BWM_CampaignEmailService.SendCampaignEmailResult result =
        BWM_CampaignEmailService.sendToContacts(
          new List<Id>{ withEmail.Id, noEmail.Id },
          TEMPLATE_ID
        );
      Test.stopTest();

      System.assertEquals(1, result.sentCount);
      System.assertEquals(1, result.skippedCount);
    }
  }

  /**
   * Scenario: Offline campaign email sends or skips based on email presence.
   */
  @IsTest
  static void testSendToOfflineCampaigns_HappyPathAndSkipNoEmail() {
    BWM_CampaignEmailService.resetTemplateSubjectCacheForTests();
    Test.setMock(
      HttpCalloutMock.class,
      buildCampaignEmailMock(SUCCESS_BODY, 200)
    );
    Offline_Campaign__c withOfflineEmail = [
      SELECT Id
      FROM Offline_Campaign__c
      WHERE Name = 'Campaign Email Offline'
      LIMIT 1
    ];
    Offline_Campaign__c noOfflineEmail = [
      SELECT Id
      FROM Offline_Campaign__c
      WHERE Name = 'No Email Offline'
      LIMIT 1
    ];

    System.runAs(getAdminUser()) {
      Test.startTest();
      BWM_CampaignEmailService.SendCampaignEmailResult result =
        BWM_CampaignEmailService.sendToOfflineCampaigns(
          new List<Id>{ withOfflineEmail.Id, noOfflineEmail.Id },
          TEMPLATE_ID
        );
      Test.stopTest();

      System.assertEquals(1, result.sentCount);
      System.assertEquals(1, result.skippedCount);
    }
  }

  /**
   * Scenario: API failure response increments skipped count for Lead campaign email.
   */
  @IsTest
  static void testSendToLeads_ApiFailure_IncrementsSkipped() {
    BWM_CampaignEmailService.resetTemplateSubjectCacheForTests();
    Test.setMock(
      HttpCalloutMock.class,
      buildCampaignEmailMock('{"description":"send failed"}', 500)
    );
    Lead withEmail = [SELECT Id FROM Lead WHERE Email != null LIMIT 1];

    Test.startTest();
    BWM_CampaignEmailService.SendCampaignEmailResult result =
      BWM_CampaignEmailService.sendToLeads(new List<Id>{ withEmail.Id }, TEMPLATE_ID);
    Test.stopTest();

    System.assertEquals(0, result.sentCount);
    System.assertEquals(1, result.skippedCount);
  }

  @IsTest
  static void testSendToLeads_HandlesCalloutException() {
    BWM_CampaignEmailService.resetTemplateSubjectCacheForTests();
    Test.setMock(HttpCalloutMock.class, new ThrowingEmailPostCalloutMock());
    Lead withEmail = [
      SELECT Id
      FROM Lead
      WHERE LastName = 'Campaign Email Lead'
      LIMIT 1
    ];

    Test.startTest();
    BWM_CampaignEmailService.SendCampaignEmailResult result =
      BWM_CampaignEmailService.sendToLeads(new List<Id>{ withEmail.Id }, TEMPLATE_ID);
    Test.stopTest();

    System.assertEquals(0, result.sentCount);
    System.assertEquals(1, result.skippedCount);
    System.assertEquals(1, result.messages.size());
  }

  @IsTest
  static void testSendToOpportunities_SkipsWhenNoPrimaryContact() {
    BWM_CampaignEmailService.resetTemplateSubjectCacheForTests();
    Account accountRecord = new Account(Name = 'Opp Without Primary Contact');
    insert accountRecord;
    Opportunity opportunityRecord = new Opportunity(
      Name = 'No Primary Contact Opp',
      AccountId = accountRecord.Id,
      StageName = 'Nurture',
      CloseDate = Date.today().addDays(30),
      Department_Name__c = 'Crash Barrier'
    );
    insert opportunityRecord;

    Test.startTest();
    BWM_CampaignEmailService.SendCampaignEmailResult result =
      BWM_CampaignEmailService.sendToOpportunities(
        new List<Id>{ opportunityRecord.Id },
        TEMPLATE_ID
      );
    Test.stopTest();

    System.assertEquals(0, result.sentCount);
    System.assertEquals(1, result.skippedCount);
  }

  @IsTest
  static void testValidateRequest_EmptyAccountIds_ThrowsError() {
    Boolean threw = false;
    try {
      BWM_CampaignEmailService.sendToAccounts(new List<Id>(), TEMPLATE_ID);
    } catch (AuraHandledException ex) {
      threw = true;
    }
    System.assertEquals(true, threw);
  }

  @IsTest
  static void testSendToAccounts_ApiFailure_IncrementsSkipped() {
    BWM_CampaignEmailService.resetTemplateSubjectCacheForTests();
    Test.setMock(
      HttpCalloutMock.class,
      buildCampaignEmailMock('{"description":"send failed"}', 500)
    );
    Account accountRecord = [
      SELECT Id
      FROM Account
      WHERE Name = 'Campaign Email Account'
      LIMIT 1
    ];

    System.runAs(getAdminUser()) {
      Test.startTest();
      BWM_CampaignEmailService.SendCampaignEmailResult result =
        BWM_CampaignEmailService.sendToAccounts(
          new List<Id>{ accountRecord.Id },
          TEMPLATE_ID
        );
      Test.stopTest();

      System.assertEquals(0, result.sentCount);
      System.assertEquals(1, result.skippedCount);
    }
  }

  private class ThrowingEmailPostCalloutMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      if ('POST'.equalsIgnoreCase(request.getMethod())) {
        throw new CalloutException('Simulated email callout failure');
      }

      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody(TEMPLATE_DETAIL_BODY);
      return response;
    }
  }

  private static User getAdminUser() {
    return [
      SELECT Id
      FROM User
      WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE
      LIMIT 1
    ];
  }
}