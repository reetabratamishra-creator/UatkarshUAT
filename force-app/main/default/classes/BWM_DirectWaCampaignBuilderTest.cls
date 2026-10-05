@IsTest
private class BWM_DirectWaCampaignBuilderTest {
  @IsTest
  static void buildPayloadUsesWhatsAppChannelAndTemplatePayload() {
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Lead leadRecord = (Lead) JSON.deserialize(
      '{"Id":"00Q000000000001AAA","Status":"Prospect","Department_Name__c":"Crash Barrier","Owner":{"attributes":{"type":"User"},"Name":"Owner Name","Phone":"9999999999","Email":"owner@test.com"}}',
      Lead.class
    );
    Map<String, Object> templateMeta = new Map<String, Object>{
      'language' => 'en',
      'content' => new Map<String, Object>{
        'header' => new Map<String, Object>{ 'type' => 'DOCUMENT' },
        'body' => 'Hello {{1}} {{2}} {{3}} {{4}} {{5}} {{6}}'
      }
    };

    Test.startTest();
    String payload = BWM_DirectWaCampaignBuilder.buildPayload(
      settings,
      null,
      'prospect_dept_enq_280526',
      templateMeta,
      leadRecord,
      '917980828320'
    );
    Test.stopTest();

    System.assert(payload.contains('"channel":"WhatsApp"'), payload);
    System.assert(payload.contains('"templatepayload"'), payload);
    System.assert(!payload.contains('"channel":"Journey"'), payload);
    System.assert(payload.contains('"biz_opaque_callback_data"'), payload);
  }

  @IsTest
  static void buildPayloadForOpportunityRecord() {
    BWM_Messaging_Settings__mdt settings = BWM_SettingsService.getSettings();
    Opportunity opportunityRecord = (Opportunity) JSON.deserialize(
      '{"Id":"006000000000001AAA","Name":"Opp One","Department_Name__c":"Enquiry","Owner":{"attributes":{"type":"User"},"Name":"Owner Name","Phone":"9999999999","Email":"owner@test.com"}}',
      Opportunity.class
    );
    Map<String, Object> templateMeta = new Map<String, Object>{
      'language' => 'en',
      'content' => new Map<String, Object>{
        'body' => 'Hello {{1}} {{2}}'
      }
    };

    Test.startTest();
    String payload = BWM_DirectWaCampaignBuilder.buildPayload(
      settings,
      null,
      'dealer_enq_dept',
      templateMeta,
      opportunityRecord,
      '917980828321'
    );
    Test.stopTest();

    System.assert(payload.contains('"to":["917980828321"]'), payload);
    System.assert(payload.contains('"name":"dealer_enq_dept"'), payload);
  }
}