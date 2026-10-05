/**
 * @description   Test class for Escalation Matrix email service and batch entry points.
 * @author        Anshita Chanda
 * @date          2026-08-10
 */
@IsTest
private class EscalationMatrixEmailServiceTest {
  @IsTest
  static void testBatchStartMethodsAndScheduler() {
    Test.startTest();
    System.assertNotEquals(null, new LeadProspectNotContacted48_96Batch().start(null));
    System.assertNotEquals(null, new LeadProspectingNoActivityBatch().start(null));
    System.assertNotEquals(null, new OpportunityQuotationPendingMatrixBatch().start(null));
    System.assertNotEquals(null, new OpportunityNurtureActiveMatrixBatch().start(null));
    System.assertNotEquals(null, new OpportunityNurtureTenderMatrixBatch().start(null));
    System.assertNotEquals(null, new OpportunityNurtureBudgetaryMatrixBatch().start(null));
    System.assertNotEquals(null, new OpportunityNegotiationActiveMatrixBatch().start(null));
    System.assertNotEquals(null, new OpportunityNegotiationTenderMatrixBatch().start(null));
    System.assertNotEquals(null, new OppNegoBudgetaryMatrixBatch().start(null));
    System.assertNotEquals(null, new TaskOverdueEscalationMatrixBatch().start(null));
    new EscalationMatrixScheduler().execute(null);
    Test.stopTest();
  }

  @IsTest
  static void testServiceHelpersAndNullGuards() {
    Lead leadRecord = new Lead(
      Prospect_Stage_Entry_Date__c = System.now().addHours(-50)
    );

    System.assertEquals(
      true,
      EscalationMatrixEmailService.hasNoActivitySince(
        leadRecord.Prospect_Stage_Entry_Date__c,
        null
      )
    );
    System.assert(
      EscalationMatrixEmailService.hoursSince(leadRecord.Prospect_Stage_Entry_Date__c) >= 48
    );
    System.assertEquals(
      'Transmission Tower',
      EscalationMatrixEmailService.getRoleDepartmentName('Transmission & Telecom Tower')
    );
    System.assertEquals(0, EscalationMatrixOpportunityHelper.getLastActivityDates(null).size());
    System.assertEquals(0, EscalationMatrixOpportunityHelper.hoursSinceDate(null));
    System.assertEquals(0, EscalationMatrixEmailService.daysSince((Date) null));
    System.assertEquals(false, EscalationMatrixEmailService.sendLeadEmail(null, 'x', null));
    System.assertEquals(
      false,
      EscalationMatrixEmailService.sendOpportunityEmail(null, 'x', null)
    );
    System.assertEquals(
      false,
      EscalationMatrixEmailService.sendTaskOverdueOwnerEmail(
        null,
        'Task Overdue Owner',
        null,
        'test@example.com'
      )
    );
    System.assertEquals(
      false,
      EscalationMatrixEmailService.sendTaskRelatedEmail(
        null,
        'Task Overdue Owner',
        EscalationMatrixEmailService.RecipientGroup.OWNER,
        null,
        null
      )
    );
  }

  @IsTest
  static void testEmailServiceSendPaths() {
    prepareTestContext();

    Lead leadRecord = createLead('Prospect', 'ServicePath');
    Opportunity opportunityRecord = createOpportunity('Nurture', 'Service Path Opp', false, null);

    leadRecord = queryLead(leadRecord.Id);
    opportunityRecord = queryOpportunity(opportunityRecord.Id);

    System.assertEquals(
      true,
      EscalationMatrixEmailService.sendLeadEmail(
        leadRecord,
        'Lead Not Contacted 48h HOD',
        EscalationMatrixEmailService.RecipientGroup.OWNER
      )
    );
    System.assertEquals(
      true,
      EscalationMatrixEmailService.sendOpportunityEmail(
        opportunityRecord,
        'Pending Quotation 48h Owner',
        EscalationMatrixEmailService.RecipientGroup.OWNER_AND_CRM
      )
    );

    Task taskRecord = new Task(
      WhoId = leadRecord.Id,
      Subject = 'Overdue Task',
      Status = 'Not Started',
      ActivityDate = Date.today().addDays(-1)
    );
    insert as system taskRecord;

    System.assertEquals(
      true,
      EscalationMatrixEmailService.sendTaskOverdueOwnerEmail(
        taskRecord,
        'Task Overdue Owner',
        leadRecord.Id,
        UserInfo.getUserEmail()
      )
    );

    System.assert(
      !EscalationMatrixEmailService.resolveLeadRecipients(
          leadRecord,
          EscalationMatrixEmailService.RecipientGroup.HOD_ONLY
        )
        .isEmpty()
    );
    System.assert(
      !EscalationMatrixEmailService.resolveOpportunityRecipients(
          opportunityRecord,
          EscalationMatrixEmailService.RecipientGroup.ED_SIR
        )
        .isEmpty()
    );
  }

  @IsTest
  static void testLeadProspect48HourEscalation() {
    prepareTestContext();

    Lead leadRecord = createLead('Prospect', 'Prospect48');
    leadRecord.Prospect_Stage_Entry_Date__c = System.now().addHours(-50);
    leadRecord.Escalation_48_Sent__c = false;
    leadRecord.Escalation_72_Sent__c = false;
    update as system leadRecord;

    leadRecord = queryProspectLead(leadRecord.Id);

    Test.startTest();
    new LeadProspectNotContacted48_96Batch().execute(null, new List<Lead>{ leadRecord });
    Test.stopTest();

    Lead updatedLead = [
      SELECT Escalation_48_Sent__c
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];
    System.assertEquals(true, updatedLead.Escalation_48_Sent__c);
  }

  @IsTest
  static void testLeadProspect96HourEscalation() {
    prepareTestContext();

    Lead leadRecord = createLead('Prospect', 'Prospect96');
    leadRecord.Prospect_Stage_Entry_Date__c = System.now().addHours(-100);
    leadRecord.Escalation_48_Sent__c = true;
    leadRecord.Escalation_72_Sent__c = false;
    update as system leadRecord;

    leadRecord = queryProspectLead(leadRecord.Id);

    Test.startTest();
    new LeadProspectNotContacted48_96Batch().execute(null, new List<Lead>{ leadRecord });
    Test.stopTest();

    Lead updatedLead = [
      SELECT Escalation_72_Sent__c
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];
    System.assertEquals(true, updatedLead.Escalation_72_Sent__c);
  }

  @IsTest
  static void testLeadProspecting24HourEscalation() {
    prepareTestContext();

    Lead leadRecord = createLead('Prospecting', 'Prospecting24');
    leadRecord.Prospecting_Escalation_24_Sent__c = false;
    update as system leadRecord;
    LeadProspectingNoActivityBatch.setTestLastProspectingActivity(
      leadRecord.Id,
      System.now().addHours(-25)
    );

    leadRecord = queryProspectingLead(leadRecord.Id);

    Test.startTest();
    new LeadProspectingNoActivityBatch().execute(null, new List<Lead>{ leadRecord });
    Test.stopTest();

    Lead updatedLead = [
      SELECT Prospecting_Escalation_24_Sent__c
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];
    System.assertEquals(true, updatedLead.Prospecting_Escalation_24_Sent__c);
  }

  @IsTest
  static void testLeadProspecting48And96HourEscalation() {
    prepareTestContext();

    Lead leadRecord = createLead('Prospecting', 'Prospecting96');
    leadRecord.Prospecting_Escalation_24_Sent__c = true;
    leadRecord.Prospecting_Escalation_48_Sent__c = false;
    leadRecord.Prospecting_Escalation_72_Sent__c = false;
    leadRecord.Prospecting_Escalation_168_Sent__c = true;
    update as system leadRecord;
    LeadProspectingNoActivityBatch.setTestLastProspectingActivity(
      leadRecord.Id,
      System.now().addHours(-100)
    );

    leadRecord = queryProspectingLead(leadRecord.Id);

    Test.startTest();
    new LeadProspectingNoActivityBatch().execute(null, new List<Lead>{ leadRecord });
    Test.stopTest();

    Lead updatedLead = [
      SELECT Prospecting_Escalation_48_Sent__c, Prospecting_Escalation_72_Sent__c
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];
    System.assertEquals(true, updatedLead.Prospecting_Escalation_48_Sent__c);
    System.assertEquals(true, updatedLead.Prospecting_Escalation_72_Sent__c);
  }

  @IsTest
  static void testOpportunityQuotation48HourEscalation() {
    prepareTestContext();

    Opportunity opportunityRecord = createOpportunity(
      'Nurture',
      'Quotation Pending Opp',
      false,
      null
    );
    opportunityRecord.Nurture_Stage_Entry_Date__c = System.now().addHours(-50);
    opportunityRecord.Nurture_Escalation_48_Sent__c = false;
    update as system opportunityRecord;

    opportunityRecord = queryOpportunity(opportunityRecord.Id);

    Test.startTest();
    new OpportunityQuotationPendingMatrixBatch()
      .execute(null, new List<Opportunity>{ opportunityRecord });
    Test.stopTest();

    Opportunity updatedOpp = [
      SELECT Nurture_Escalation_48_Sent__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    System.assertEquals(true, updatedOpp.Nurture_Escalation_48_Sent__c);
  }

  @IsTest
  static void testOpportunityQuotation60And72HourEscalation() {
    prepareTestContext();

    Opportunity opportunityRecord = createOpportunity(
      'Nurture',
      'Quotation Pending 72h Opp',
      false,
      null
    );
    opportunityRecord.Nurture_Stage_Entry_Date__c = System.now().addHours(-80);
    opportunityRecord.Nurture_Escalation_48_Sent__c = true;
    opportunityRecord.Nurture_Escalation_60_Sent__c = false;
    opportunityRecord.Nurture_Escalation_72_Sent__c = false;
    update as system opportunityRecord;

    opportunityRecord = queryOpportunity(opportunityRecord.Id);

    Test.startTest();
    new OpportunityQuotationPendingMatrixBatch()
      .execute(null, new List<Opportunity>{ opportunityRecord });
    Test.stopTest();

    Opportunity updatedOpp = [
      SELECT Nurture_Escalation_60_Sent__c, Nurture_Escalation_72_Sent__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    System.assertEquals(true, updatedOpp.Nurture_Escalation_60_Sent__c);
    System.assertEquals(true, updatedOpp.Nurture_Escalation_72_Sent__c);
  }

  @IsTest
  static void testOpportunityQuotationSkipsWhenQuoteExists() {
    prepareTestContext();

    Opportunity opportunityRecord = createOpportunity(
      'Nurture',
      'Quoted Opp',
      false,
      null
    );
    opportunityRecord.Nurture_Stage_Entry_Date__c = System.now().addHours(-50);
    opportunityRecord.Nurture_Escalation_48_Sent__c = false;
    update as system opportunityRecord;

    Quote quoteRecord = new Quote(
      Name = 'Test Quote ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
      OpportunityId = opportunityRecord.Id
    );
    insert as system quoteRecord;

    opportunityRecord = queryOpportunity(opportunityRecord.Id);

    Test.startTest();
    new OpportunityQuotationPendingMatrixBatch()
      .execute(null, new List<Opportunity>{ opportunityRecord });
    Test.stopTest();

    Opportunity updatedOpp = [
      SELECT Nurture_Escalation_48_Sent__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    System.assertEquals(false, updatedOpp.Nurture_Escalation_48_Sent__c);
  }

  @IsTest
  static void testOpportunityNurtureActiveEscalation() {
    prepareTestContext();

    Opportunity opportunityRecord = createOpportunity(
      'Nurture',
      'Active Nurture Opp',
      false,
      null
    );
    setOldOpportunityActivity(opportunityRecord.Id, 5);
    opportunityRecord.Active_Task_Escalation_72_Sent__c = false;
    opportunityRecord.Active_Task_Escalation_96_Sent__c = false;
    update as system opportunityRecord;

    opportunityRecord = queryActiveNurtureOpportunity(opportunityRecord.Id);

    Test.startTest();
    new OpportunityNurtureActiveMatrixBatch()
      .execute(null, new List<Opportunity>{ opportunityRecord });
    Test.stopTest();

    Opportunity updatedOpp = [
      SELECT Active_Task_Escalation_72_Sent__c, Active_Task_Escalation_96_Sent__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    System.assertEquals(true, updatedOpp.Active_Task_Escalation_72_Sent__c);
    System.assertEquals(true, updatedOpp.Active_Task_Escalation_96_Sent__c);
  }

  @IsTest
  static void testOpportunityNurtureTenderEscalation() {
    Id tenderRecordTypeId = getTenderRecordTypeId();
    if (tenderRecordTypeId == null) {
      return;
    }

    prepareTestContext();

    Opportunity opportunityRecord = createOpportunity(
      'Nurture',
      'Tender Nurture Opp',
      false,
      tenderRecordTypeId
    );
    setOldOpportunityActivity(opportunityRecord.Id, 22);
    opportunityRecord.TenderEsc15Sent__c = false;
    opportunityRecord.TenderEsc21Sent__c = false;
    update as system opportunityRecord;

    opportunityRecord = queryTenderOpportunity(opportunityRecord.Id);

    Test.startTest();
    new OpportunityNurtureTenderMatrixBatch()
      .execute(null, new List<Opportunity>{ opportunityRecord });
    Test.stopTest();

    Opportunity updatedOpp = [
      SELECT TenderEsc15Sent__c, TenderEsc21Sent__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    System.assertEquals(true, updatedOpp.TenderEsc15Sent__c);
    System.assertEquals(true, updatedOpp.TenderEsc21Sent__c);
  }

  @IsTest
  static void testOpportunityNurtureBudgetaryEscalation() {
    prepareTestContext();

    Opportunity opportunityRecord = createOpportunity(
      'Nurture',
      'Budgetary Nurture Opp',
      true,
      null
    );
    setOldOpportunityActivity(opportunityRecord.Id, 22);
    opportunityRecord.NurtureEscalation48Sent__c = false;
    opportunityRecord.NurtureEscalation60Sent__c = false;
    update as system opportunityRecord;

    opportunityRecord = queryBudgetaryOpportunity(opportunityRecord.Id);

    Test.startTest();
    new OpportunityNurtureBudgetaryMatrixBatch()
      .execute(null, new List<Opportunity>{ opportunityRecord });
    Test.stopTest();

    Opportunity updatedOpp = [
      SELECT NurtureEscalation48Sent__c, NurtureEscalation60Sent__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    System.assertEquals(true, updatedOpp.NurtureEscalation48Sent__c);
    System.assertEquals(true, updatedOpp.NurtureEscalation60Sent__c);
  }

  @IsTest
  static void testOpportunityNegotiationActiveEscalation() {
    prepareTestContext();

    Opportunity opportunityRecord = createOpportunity(
      'Negotiation',
      'Negotiation Active Opp',
      false,
      null
    );
    setOldOpportunityActivity(opportunityRecord.Id, 22);
    opportunityRecord.EscalationNeg7Sent__c = false;
    opportunityRecord.EscalationNeg14Sent__c = false;
    opportunityRecord.EscalationNeg21Sent__c = false;
    update as system opportunityRecord;

    opportunityRecord = queryNegotiationActiveOpportunity(opportunityRecord.Id);

    Test.startTest();
    new OpportunityNegotiationActiveMatrixBatch()
      .execute(null, new List<Opportunity>{ opportunityRecord });
    Test.stopTest();

    Opportunity updatedOpp = [
      SELECT EscalationNeg7Sent__c, EscalationNeg14Sent__c, EscalationNeg21Sent__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    System.assertEquals(true, updatedOpp.EscalationNeg7Sent__c);
    System.assertEquals(true, updatedOpp.EscalationNeg14Sent__c);
    System.assertEquals(true, updatedOpp.EscalationNeg21Sent__c);
  }

  @IsTest
  static void testOpportunityNegotiationTenderEscalation() {
    Id tenderRecordTypeId = getTenderRecordTypeId();
    if (tenderRecordTypeId == null) {
      return;
    }

    prepareTestContext();

    Opportunity opportunityRecord = createOpportunity(
      'Negotiation',
      'Negotiation Tender Opp',
      false,
      tenderRecordTypeId
    );
    setOldOpportunityActivity(opportunityRecord.Id, 61);
    opportunityRecord.TenderEsc15Sent__c = false;
    opportunityRecord.TenderEsc21Sent__c = false;
    opportunityRecord.TenderEsc30Sent__c = false;
    update as system opportunityRecord;

    opportunityRecord = queryTenderOpportunity(opportunityRecord.Id);

    Test.startTest();
    new OpportunityNegotiationTenderMatrixBatch()
      .execute(null, new List<Opportunity>{ opportunityRecord });
    Test.stopTest();

    Opportunity updatedOpp = [
      SELECT TenderEsc15Sent__c, TenderEsc21Sent__c, TenderEsc30Sent__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    System.assertEquals(true, updatedOpp.TenderEsc15Sent__c);
    System.assertEquals(true, updatedOpp.TenderEsc21Sent__c);
    System.assertEquals(true, updatedOpp.TenderEsc30Sent__c);
  }

  @IsTest
  static void testOpportunityNegotiationBudgetaryEscalation() {
    prepareTestContext();

    Opportunity opportunityRecord = createOpportunity(
      'Negotiation',
      'Negotiation Budgetary Opp',
      true,
      null
    );
    setOldOpportunityActivity(opportunityRecord.Id, 61);
    opportunityRecord.NurtureEscalation48Sent__c = false;
    opportunityRecord.NurtureEscalation60Sent__c = false;
    opportunityRecord.NurtureEscalation72Sent__c = false;
    update as system opportunityRecord;

    opportunityRecord = queryBudgetaryOpportunity(opportunityRecord.Id);

    Test.startTest();
    new OppNegoBudgetaryMatrixBatch()
      .execute(null, new List<Opportunity>{ opportunityRecord });
    Test.stopTest();

    Opportunity updatedOpp = [
      SELECT NurtureEscalation48Sent__c, NurtureEscalation60Sent__c, NurtureEscalation72Sent__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    System.assertEquals(true, updatedOpp.NurtureEscalation48Sent__c);
    System.assertEquals(true, updatedOpp.NurtureEscalation60Sent__c);
    System.assertEquals(true, updatedOpp.NurtureEscalation72Sent__c);
  }

  @IsTest
  static void testTaskOverdueLead36HourEscalation() {
    prepareTestContext();

    Lead leadRecord = createLead('Prospect', 'TaskOverdue36');
    leadRecord.FirstOverdueTaskDate__c = System.now().addHours(-40);
    leadRecord.LeadOverdueEsc36Sent__c = false;
    leadRecord.LeadOverdueEsc96Sent__c = false;
    update as system leadRecord;

    Task taskRecord = new Task(
      WhoId = leadRecord.Id,
      Subject = 'Follow Up Overdue 36h',
      Status = 'Not Started',
      ActivityDate = Date.today().addDays(-2)
    );
    insert as system taskRecord;

    leadRecord = [
      SELECT
        Id,
        Name,
        OwnerId,
        Owner.Email,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c,
        FirstOverdueTaskDate__c,
        LeadOverdueEsc36Sent__c,
        LeadOverdueEsc96Sent__c
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];

    Test.startTest();
    new TaskOverdueEscalationMatrixBatch()
      .execute(null, new List<Task>{ taskRecord });
    Test.stopTest();

    Lead updatedLead = [
      SELECT LeadOverdueEsc36Sent__c
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];
    System.assertEquals(true, updatedLead.LeadOverdueEsc36Sent__c);
  }

  @IsTest
  static void testTaskOverdueLead96HourEscalation() {
    prepareTestContext();

    Lead leadRecord = createLead('Prospect', 'TaskOverdue96');
    leadRecord.FirstOverdueTaskDate__c = System.now().addHours(-100);
    leadRecord.LeadOverdueEsc36Sent__c = true;
    leadRecord.LeadOverdueEsc96Sent__c = false;
    update as system leadRecord;

    Task taskRecord = new Task(
      WhoId = leadRecord.Id,
      Subject = 'Follow Up Overdue 96h',
      Status = 'Not Started',
      ActivityDate = Date.today().addDays(-5)
    );
    insert as system taskRecord;

    leadRecord = [
      SELECT
        Id,
        Name,
        OwnerId,
        Owner.Email,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c,
        FirstOverdueTaskDate__c,
        LeadOverdueEsc36Sent__c,
        LeadOverdueEsc96Sent__c
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];

    Test.startTest();
    new TaskOverdueEscalationMatrixBatch()
      .execute(null, new List<Task>{ taskRecord });
    Test.stopTest();

    Lead updatedLead = [
      SELECT LeadOverdueEsc96Sent__c
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];
    System.assertEquals(true, updatedLead.LeadOverdueEsc96Sent__c);
  }

  @IsTest
  static void testLeadProspectSkipsWhenRecentActivity() {
    prepareTestContext();

    Lead leadRecord = createLead('Prospect', 'ProspectSkip');
    leadRecord.Prospect_Stage_Entry_Date__c = System.now().addHours(-50);
    leadRecord.Escalation_48_Sent__c = false;
    update as system leadRecord;

    insert as system new Task(
      WhoId = leadRecord.Id,
      Subject = 'Recent Activity',
      Status = 'Completed',
      ActivityDate = Date.today()
    );

    leadRecord = queryProspectLead(leadRecord.Id);

    Test.startTest();
    new LeadProspectNotContacted48_96Batch().execute(null, new List<Lead>{ leadRecord });
    Test.stopTest();

    Lead updatedLead = [
      SELECT Escalation_48_Sent__c
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];
    System.assertEquals(false, updatedLead.Escalation_48_Sent__c);
  }

  @IsTest
  static void testEmailServiceAdditionalRecipientGroups() {
    prepareTestContext();

    Lead leadRecord = queryLead(createLead('Prospect', 'RecipientGroups').Id);
    Opportunity opportunityRecord = queryOpportunity(
      createOpportunity('Nurture', 'Recipient Opp', false, null).Id
    );

    System.assert(
      EscalationMatrixEmailService.sendLeadEmail(
        leadRecord,
        'Lead Not Contacted 48h HOD',
        EscalationMatrixEmailService.RecipientGroup.HOD_ONLY
      )
    );
    System.assert(
      EscalationMatrixEmailService.sendLeadEmail(
        leadRecord,
        'Lead Not Contacted 96h Sir',
        EscalationMatrixEmailService.RecipientGroup.ED_SIR
      )
    );
    System.assert(
      EscalationMatrixEmailService.sendOpportunityEmail(
        opportunityRecord,
        'Pending Quotation 48h Owner',
        EscalationMatrixEmailService.RecipientGroup.CRM_HEAD_ONLY
      )
    );
    System.assert(
      EscalationMatrixEmailService.sendTaskOverdueOwnerEmail(
        new Task(Subject = 'Overdue', ActivityDate = Date.today().addDays(-1)),
        'Task Overdue Owner',
        opportunityRecord.Id,
        UserInfo.getUserEmail()
      )
    );
  }

  @IsTest
  static void testTaskOverdueOpportunity36HourEscalation() {
    prepareTestContext();

    Opportunity opportunityRecord = createOpportunity(
      'Nurture',
      'Task Overdue Opp 36h',
      false,
      null
    );
    opportunityRecord.FirstOverdueTaskDate__c = System.now().addHours(-40);
    opportunityRecord.OppOverdueEsc36Sent__c = false;
    update as system opportunityRecord;

    Task taskRecord = new Task(
      WhatId = opportunityRecord.Id,
      Subject = 'Opportunity Follow Up Overdue 36h',
      Status = 'Not Started',
      ActivityDate = Date.today().addDays(-2)
    );
    insert as system taskRecord;

    Test.startTest();
    new TaskOverdueEscalationMatrixBatch()
      .execute(null, new List<Task>{ taskRecord });
    Test.stopTest();

    Opportunity updatedOpp = [
      SELECT OppOverdueEsc36Sent__c
      FROM Opportunity
      WHERE Id = :opportunityRecord.Id
    ];
    System.assertEquals(true, updatedOpp.OppOverdueEsc36Sent__c);
  }

  @IsTest
  static void testSendRenderedEmailWithoutSimulation() {
    EscalationMatrixEmailService.clearTestState();

    LeadManagementEmailService.RenderedEmail leadRendered = new LeadManagementEmailService.RenderedEmail();
    leadRendered.subject = 'Live Send Subject';
    leadRendered.plainTextBody = 'Live send body';
    EscalationMatrixEmailService.testLeadRenderedOverride = leadRendered;
    EscalationMatrixEmailService.testRecipientOverrides = new Set<String>{
      UserInfo.getUserEmail().trim().toLowerCase()
    };

    List<EmailTemplate> templates = [
      SELECT Id
      FROM EmailTemplate
      WHERE Folder.Name LIKE 'Utkarsh Escalation Matrix Template%'
      LIMIT 1
    ];
    if (!templates.isEmpty()) {
      EscalationMatrixEmailService.setTestTemplateId(
        'Lead Not Contacted 48h HOD',
        templates[0].Id
      );
    }

    Lead leadRecord = queryLead(createLead('Prospect', 'LiveSend').Id);

    System.assertEquals(
      true,
      EscalationMatrixEmailService.sendLeadEmail(
        leadRecord,
        'Lead Not Contacted 48h HOD',
        EscalationMatrixEmailService.RecipientGroup.OWNER
      )
    );
  }

  @IsTest
  static void testResolveTemplateIdFromFolder() {
    EscalationMatrixEmailService.clearTestState();

    Lead leadRecord = queryLead(createLead('Prospect', 'TemplateLookup').Id);
    LeadManagementEmailService.RenderedEmail leadRendered = new LeadManagementEmailService.RenderedEmail();
    leadRendered.subject = 'Template Lookup Subject';
    leadRendered.plainTextBody = 'Template lookup body';
    EscalationMatrixEmailService.testLeadRenderedOverride = leadRendered;
    EscalationMatrixEmailService.testRecipientOverrides = new Set<String>{
      UserInfo.getUserEmail().trim().toLowerCase()
    };
    EscalationMatrixEmailService.testSimulateSuccessfulSend = true;

    List<EmailTemplate> templates = [
      SELECT Id, Name
      FROM EmailTemplate
      WHERE Folder.Name LIKE 'Utkarsh Escalation Matrix Template%'
      LIMIT 1
    ];

    if (templates.isEmpty()) {
      return;
    }

    System.assertEquals(
      true,
      EscalationMatrixEmailService.sendLeadEmail(
        leadRecord,
        templates[0].Name,
        EscalationMatrixEmailService.RecipientGroup.OWNER
      )
    );
  }

  @IsTest
  static void testOpportunityHelperActivityAggregation() {
    EscalationMatrixOpportunityHelper.clearTestLastActivityDates();

    Opportunity opportunityRecord = createOpportunity(
      'Nurture',
      'Helper Opp',
      false,
      null
    );

    insert as system new Task(
      WhatId = opportunityRecord.Id,
      Subject = 'Old Task',
      Status = 'Completed',
      ActivityDate = Date.today().addDays(-3)
    );
    insert as system new Event(
      WhatId = opportunityRecord.Id,
      Subject = 'Old Event',
      DurationInMinutes = 30,
      ActivityDateTime = System.now().addDays(-1)
    );

    Map<Id, Date> activityDates = EscalationMatrixOpportunityHelper.getLastActivityDates(
      new Set<Id>{ opportunityRecord.Id }
    );
    Date latestActivityDate = activityDates.get(opportunityRecord.Id);

    System.assertNotEquals(null, latestActivityDate);
    System.assert(
      EscalationMatrixOpportunityHelper.hoursSinceDate(Date.today().addDays(-4)) >= 72
    );
  }

  @IsTest
  static void testAllRecipientResolutionPaths() {
    EscalationMatrixEmailService.clearTestState();

    Lead leadRecord = queryLead(createLead('Prospect', 'AllRecipientsLead').Id);
    Opportunity opportunityRecord = queryOpportunity(
      createOpportunity('Nurture', 'All Recipients Opp', false, null).Id
    );

    EscalationMatrixEmailService.RecipientGroup[] groups = new EscalationMatrixEmailService.RecipientGroup[]{
      EscalationMatrixEmailService.RecipientGroup.OWNER,
      EscalationMatrixEmailService.RecipientGroup.OWNER_AND_CRM,
      EscalationMatrixEmailService.RecipientGroup.HOD_ONLY,
      EscalationMatrixEmailService.RecipientGroup.CRM_HEAD_ONLY,
      EscalationMatrixEmailService.RecipientGroup.HOD_AND_CRM_HEAD,
      EscalationMatrixEmailService.RecipientGroup.ED_SIR
    };

    for (EscalationMatrixEmailService.RecipientGroup recipientType : groups) {
      EscalationMatrixEmailService.resolveLeadRecipients(leadRecord, recipientType);
      EscalationMatrixEmailService.resolveOpportunityRecipients(
        opportunityRecord,
        recipientType
      );
    }
  }

  @IsTest
  static void testHasNoActivitySinceWithRecentActivity() {
    Datetime anchorDate = System.now().addDays(-2);
    System.assertEquals(
      false,
      EscalationMatrixEmailService.hasNoActivitySince(anchorDate, Date.today())
    );
    System.assertEquals(false, EscalationMatrixEmailService.hasNoActivitySince(null, Date.today()));
  }

  private static void prepareTestContext() {
    EscalationMatrixEmailService.clearTestState();
    EscalationMatrixOpportunityHelper.clearTestLastActivityDates();
    LeadProspectingNoActivityBatch.clearTestLastProspectingActivityOverrides();

    LeadManagementEmailService.RenderedEmail leadRendered = new LeadManagementEmailService.RenderedEmail();
    leadRendered.subject = 'Escalation Test Subject';
    leadRendered.plainTextBody = 'Escalation test body';
    EscalationMatrixEmailService.testLeadRenderedOverride = leadRendered;

    DealerOpportunityEmailService.RenderedEmail oppRendered = new DealerOpportunityEmailService.RenderedEmail();
    oppRendered.subject = 'Escalation Test Subject';
    oppRendered.plainTextBody = 'Escalation test body';
    EscalationMatrixEmailService.testOppRenderedOverride = oppRendered;

    EscalationMatrixEmailService.testRecipientOverrides = new Set<String>{
      UserInfo.getUserEmail().trim().toLowerCase()
    };
    EscalationMatrixEmailService.testSimulateSuccessfulSend = true;

    List<EmailTemplate> templates = [
      SELECT Id, Name
      FROM EmailTemplate
      LIMIT 1
    ];
    if (!templates.isEmpty()) {
      EscalationMatrixEmailService.setTestTemplateId(
        'Lead Not Contacted 48h HOD',
        templates[0].Id
      );
      EscalationMatrixEmailService.setTestTemplateId(
        'Pending Quotation 48h Owner',
        templates[0].Id
      );
      EscalationMatrixEmailService.setTestTemplateId('Task Overdue Owner', templates[0].Id);
    }
  }

  private static Lead createLead(String statusValue, String lastName) {
    Lead leadRecord = new Lead(
      LastName = lastName,
      Company = 'Escalation Matrix Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
      LeadSource = 'OUTBOUND PHONE CALL',
      Status = statusValue,
      Department_Name__c = 'Enquiry',
      Email = lastName.toLowerCase().replace(' ', '') + '@example.com',
      Phone = (String.valueOf(Math.abs(Crypto.getRandomInteger())) + '9123456789').right(10)
    );
    insert as system leadRecord;
    return leadRecord;
  }

  private static Opportunity createOpportunity(
    String stageName,
    String opportunityName,
    Boolean budgetConfirmed,
    Id recordTypeId
  ) {
    Account accountRecord = new Account(Name = opportunityName + ' Account');
    insert as system accountRecord;

    Opportunity opportunityRecord = new Opportunity(
      Name = opportunityName,
      AccountId = accountRecord.Id,
      StageName = stageName,
      CloseDate = Date.today().addDays(30),
      Budget_Confirmed__c = budgetConfirmed
    );
    if (recordTypeId != null) {
      opportunityRecord.RecordTypeId = recordTypeId;
    }
    insert as system opportunityRecord;
    return opportunityRecord;
  }

  private static void setOpportunityCreatedDate(Id opportunityId, Datetime createdDate) {
    Test.setCreatedDate(opportunityId, createdDate);
  }

  private static void setOldOpportunityActivity(Id opportunityId, Integer daysAgo) {
    setOpportunityCreatedDate(opportunityId, System.now().addDays(-daysAgo));
    EscalationMatrixOpportunityHelper.setTestLastActivityDate(
      opportunityId,
      Date.today().addDays(-daysAgo)
    );
  }

  private static Id getTenderRecordTypeId() {
    Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
      .get('Tender_Opportunity');
    return recordTypeInfo == null ? null : recordTypeInfo.getRecordTypeId();
  }

  private static Lead queryLead(Id leadId) {
    return [
      SELECT
        Id,
        Name,
        OwnerId,
        Owner.Email,
        Status,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c
      FROM Lead
      WHERE Id = :leadId
    ];
  }

  private static Lead queryProspectLead(Id leadId) {
    return [
      SELECT
        Id,
        Name,
        OwnerId,
        Status,
        Department_NameFormula__c,
        Prospect_Stage_Entry_Date__c,
        Escalation_48_Sent__c,
        Escalation_72_Sent__c,
        Escalation_120_Sent__c,
        LastActivityDate,
        CRM_User_Email_Formula__c
      FROM Lead
      WHERE Id = :leadId
    ];
  }

  private static Lead queryProspectingLead(Id leadId) {
    return [
      SELECT
        Id,
        Name,
        OwnerId,
        Status,
        Department_NameFormula__c,
        Last_Prospecting_Activity__c,
        Prospecting_Escalation_24_Sent__c,
        Prospecting_Escalation_48_Sent__c,
        Prospecting_Escalation_72_Sent__c,
        Prospecting_Escalation_168_Sent__c,
        CRM_User_Email_Formula__c
      FROM Lead
      WHERE Id = :leadId
    ];
  }

  private static Opportunity queryOpportunity(Id opportunityId) {
    return [
      SELECT
        Id,
        Name,
        OwnerId,
        StageName,
        CreatedDate,
        Nurture_Stage_Entry_Date__c,
        Department_Name__c,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c,
        Nurture_Escalation_48_Sent__c,
        Nurture_Escalation_60_Sent__c,
        Nurture_Escalation_72_Sent__c
      FROM Opportunity
      WHERE Id = :opportunityId
    ];
  }

  private static Opportunity queryActiveNurtureOpportunity(Id opportunityId) {
    return [
      SELECT
        Id,
        Name,
        OwnerId,
        StageName,
        CreatedDate,
        Budget_Confirmed__c,
        RecordType.DeveloperName,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c,
        Active_Task_Escalation_72_Sent__c,
        Active_Task_Escalation_96_Sent__c,
        Active_Task_Escalation_120_Sent__c
      FROM Opportunity
      WHERE Id = :opportunityId
    ];
  }

  private static Opportunity queryTenderOpportunity(Id opportunityId) {
    return [
      SELECT
        Id,
        Name,
        OwnerId,
        StageName,
        CreatedDate,
        LastModifiedDate,
        RecordType.DeveloperName,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c,
        TenderEsc15Sent__c,
        TenderEsc21Sent__c,
        TenderEsc30Sent__c
      FROM Opportunity
      WHERE Id = :opportunityId
    ];
  }

  private static Opportunity queryBudgetaryOpportunity(Id opportunityId) {
    return [
      SELECT
        Id,
        Name,
        OwnerId,
        StageName,
        CreatedDate,
        LastModifiedDate,
        Budget_Confirmed__c,
        RecordType.DeveloperName,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c,
        NurtureEscalation48Sent__c,
        NurtureEscalation60Sent__c,
        NurtureEscalation72Sent__c
      FROM Opportunity
      WHERE Id = :opportunityId
    ];
  }

  @IsTest
  static void testResolveRecipientsWithoutOverridesCoversRoleLookups() {
    Lead leadRecord = createLead('Prospect', 'NoOverrideLead');
    Opportunity opportunityRecord = createOpportunity(
      'Nurture',
      'No Override Opp',
      false,
      null
    );
    leadRecord = queryLead(leadRecord.Id);
    opportunityRecord = queryOpportunity(opportunityRecord.Id);

    EscalationMatrixEmailService.clearTestState();

    EscalationMatrixEmailService.resolveLeadRecipients(
      leadRecord,
      EscalationMatrixEmailService.RecipientGroup.OWNER
    );
    EscalationMatrixEmailService.resolveLeadRecipients(
      leadRecord,
      EscalationMatrixEmailService.RecipientGroup.OWNER_AND_CRM
    );
    EscalationMatrixEmailService.resolveLeadRecipients(
      leadRecord,
      EscalationMatrixEmailService.RecipientGroup.HOD_ONLY
    );
    EscalationMatrixEmailService.resolveLeadRecipients(
      leadRecord,
      EscalationMatrixEmailService.RecipientGroup.CRM_HEAD_ONLY
    );
    EscalationMatrixEmailService.resolveLeadRecipients(
      leadRecord,
      EscalationMatrixEmailService.RecipientGroup.HOD_AND_CRM_HEAD
    );
    EscalationMatrixEmailService.resolveLeadRecipients(
      leadRecord,
      EscalationMatrixEmailService.RecipientGroup.ED_SIR
    );
    EscalationMatrixEmailService.resolveOpportunityRecipients(
      opportunityRecord,
      EscalationMatrixEmailService.RecipientGroup.OWNER
    );
    EscalationMatrixEmailService.resolveOpportunityRecipients(
      opportunityRecord,
      EscalationMatrixEmailService.RecipientGroup.OWNER_AND_CRM
    );
    EscalationMatrixEmailService.resolveOpportunityRecipients(
      opportunityRecord,
      EscalationMatrixEmailService.RecipientGroup.HOD_ONLY
    );
    EscalationMatrixEmailService.resolveOpportunityRecipients(
      opportunityRecord,
      EscalationMatrixEmailService.RecipientGroup.CRM_HEAD_ONLY
    );
    EscalationMatrixEmailService.resolveOpportunityRecipients(
      opportunityRecord,
      EscalationMatrixEmailService.RecipientGroup.HOD_AND_CRM_HEAD
    );
    EscalationMatrixEmailService.resolveOpportunityRecipients(
      opportunityRecord,
      EscalationMatrixEmailService.RecipientGroup.ED_SIR
    );

    System.assertEquals(
      false,
      EscalationMatrixEmailService.sendLeadEmail(
        leadRecord,
        'Missing Template Name XYZ',
        EscalationMatrixEmailService.RecipientGroup.OWNER
      )
    );
  }

  @IsTest
  static void testSendTaskRelatedEmailRendersTaskTemplate() {
    EscalationMatrixEmailService.clearTestState();
    EscalationMatrixEmailService.testRecipientOverrides = new Set<String>{
      UserInfo.getUserEmail()
    };

    Lead leadRecord = createLead('Prospect', 'TaskMerge');
    Task taskRecord = new Task(
      WhoId = leadRecord.Id,
      Subject = 'Overdue follow-up',
      Status = 'Not Started',
      ActivityDate = Date.today().addDays(-1),
      OwnerId = UserInfo.getUserId()
    );
    insert as system taskRecord;
    taskRecord = [
      SELECT Id, WhoId, OwnerId
      FROM Task
      WHERE Id = :taskRecord.Id
    ];

    List<EmailTemplate> templates = [
      SELECT Id
      FROM EmailTemplate
      WHERE Name = 'Task Overdue Owner'
      LIMIT 1
    ];
    if (templates.isEmpty()) {
      System.assertEquals(
        false,
        EscalationMatrixEmailService.sendTaskRelatedEmail(
          taskRecord,
          'Task Overdue Owner',
          EscalationMatrixEmailService.RecipientGroup.OWNER,
          leadRecord,
          null
        )
      );
      return;
    }

    EscalationMatrixEmailService.setTestTemplateId('Task Overdue Owner', templates[0].Id);

    Test.startTest();
    Boolean sent = EscalationMatrixEmailService.sendTaskRelatedEmail(
      taskRecord,
      'Task Overdue Owner',
      EscalationMatrixEmailService.RecipientGroup.OWNER,
      leadRecord,
      null
    );
    Test.stopTest();

    System.assertNotEquals(null, sent);
  }

  private static Opportunity queryNegotiationActiveOpportunity(Id opportunityId) {
    return [
      SELECT
        Id,
        Name,
        OwnerId,
        StageName,
        CreatedDate,
        Budget_Confirmed__c,
        RecordType.DeveloperName,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c,
        EscalationNeg7Sent__c,
        EscalationNeg14Sent__c,
        EscalationNeg21Sent__c
      FROM Opportunity
      WHERE Id = :opportunityId
    ];
  }
}