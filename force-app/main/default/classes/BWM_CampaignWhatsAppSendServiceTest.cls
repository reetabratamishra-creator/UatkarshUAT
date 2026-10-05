/**
 * @description   Test class for BWM_CampaignWhatsAppSendService WhatsApp campaign
 *                sends.
 * @author        Anshita Chanda
 * @date          2026-08-06
 */
@IsTest
private class BWM_CampaignWhatsAppSendServiceTest {
  @IsTest
  static void sendToContactDispatchesCampaignWhatsAppPayload() {
    BWM_JourneyDefinitionService.clearCache();
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Contact contactRecord = new Contact(
      LastName = 'Campaign WhatsApp',
      Phone = '9876543210',
      Email = 'contact@test.com'
    );
    insert contactRecord;
    contactRecord = [
      SELECT Id, Name, Phone, MobilePhone, Email, Owner.Name, Owner.Phone, Owner.Email
      FROM Contact
      WHERE Id = :contactRecord.Id
    ];

    Test.startTest();
    LeadManagementWhatsAppService.SendWhatsAppResult result =
      BWM_CampaignWhatsAppSendService.sendToRecords(
        new List<SObject>{ contactRecord },
        'u_dealer_enq_dept',
        BWM_MessagingConstants.TRIGGER_CONTACT_CAMPAIGN,
        BWM_MessagingConstants.OBJECT_TYPE_CONTACT
      );
    Test.stopTest();

    System.assertEquals(1, result.sentCount);
    System.assertEquals(0, result.skippedCount);
  }

  @IsTest
  static void sendToAccountDispatchesCampaignWhatsAppPayload() {
    BWM_JourneyDefinitionService.clearCache();
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey message enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Account accountRecord = new Account(
      Name = 'Campaign WhatsApp Account',
      Phone = '9876543215'
    );
    insert accountRecord;
    accountRecord = [
      SELECT Id, Name, Phone, Owner.Name, Owner.Phone, Owner.Email
      FROM Account
      WHERE Id = :accountRecord.Id
    ];

    Test.startTest();
    LeadManagementWhatsAppService.SendWhatsAppResult result =
      BWM_CampaignWhatsAppSendService.sendToRecords(
        new List<SObject>{ accountRecord },
        'u_dealer_enq_dept',
        BWM_MessagingConstants.TRIGGER_ACCOUNT_CAMPAIGN,
        BWM_MessagingConstants.OBJECT_TYPE_ACCOUNT
      );
    Test.stopTest();

    System.assertEquals(1, result.sentCount);
  }

  @IsTest
  static void sendToRecordsSkipsWhenPhoneMissing() {
    Contact contactRecord = new Contact(LastName = 'No Phone Contact');
    insert contactRecord;
    contactRecord = [
      SELECT Id, Name, Phone, MobilePhone, Email, Owner.Name, Owner.Phone, Owner.Email
      FROM Contact
      WHERE Id = :contactRecord.Id
    ];

    Test.startTest();
    LeadManagementWhatsAppService.SendWhatsAppResult result =
      BWM_CampaignWhatsAppSendService.sendToRecords(
        new List<SObject>{ contactRecord },
        'u_dealer_enq_dept',
        BWM_MessagingConstants.TRIGGER_CONTACT_CAMPAIGN,
        BWM_MessagingConstants.OBJECT_TYPE_CONTACT
      );
    Test.stopTest();

    System.assertEquals(0, result.sentCount);
    System.assertEquals(1, result.skippedCount);
  }

  @IsTest
  static void sendToRecordsRecordsFailureWhenApiReturnsError() {
    BWM_JourneyDefinitionService.clearCache();
    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"500","message":"Journey failed."}',
        '{"code":"500","message":"unused"}'
      )
    );

    Contact contactRecord = new Contact(
      LastName = 'Campaign WhatsApp Fail',
      Phone = '9876543216',
      MobilePhone = '9876543216',
      Email = 'fail@test.com'
    );
    insert contactRecord;
    contactRecord = [
      SELECT Id, Name, Phone, MobilePhone, Email, Owner.Name, Owner.Phone, Owner.Email
      FROM Contact
      WHERE Id = :contactRecord.Id
    ];

    Test.startTest();
    LeadManagementWhatsAppService.SendWhatsAppResult result =
      BWM_CampaignWhatsAppSendService.sendToRecords(
        new List<SObject>{ contactRecord },
        'u_dealer_enq_dept',
        BWM_MessagingConstants.TRIGGER_CONTACT_CAMPAIGN,
        BWM_MessagingConstants.OBJECT_TYPE_CONTACT
      );
    Test.stopTest();

    System.assertEquals(0, result.sentCount);
    System.assertEquals(1, result.skippedCount);
  }
}