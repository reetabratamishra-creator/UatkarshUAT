/**
 * @description   Test class for TaskOverdueEscalationMatrixBatch.
 * @author        Anshita Chanda
 * @date          2026-08-17
 */
@IsTest
private class TaskOverdueEscalationMatrixBatchTest {
  @IsTest
  static void testStartExecuteFinish() {
    EscalationMatrixTestUtil.prepareTestContext();

    Test.startTest();
    Database.QueryLocator locator = new TaskOverdueEscalationMatrixBatch().start(null);
    new TaskOverdueEscalationMatrixBatch().finish(null);
    Test.stopTest();

    System.assertNotEquals(null, locator);
  }

  @IsTest
  static void testExecuteLead36HourEscalation() {
    EscalationMatrixTestUtil.prepareTestContext();

    Lead leadRecord = EscalationMatrixTestUtil.createLead('Prospect', 'TaskOverdue36');
    leadRecord.FirstOverdueTaskDate__c = System.now().addHours(-40);
    leadRecord.LeadOverdueEsc36Sent__c = false;
    leadRecord.LeadOverdueEsc96Sent__c = false;
    update leadRecord;

    Task taskRecord = new Task(
      WhoId = leadRecord.Id,
      Subject = 'Follow Up Overdue 36h',
      Status = 'Not Started',
      ActivityDate = Date.today().addDays(-2)
    );
    insert taskRecord;

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
  static void testExecuteLead96HourEscalation() {
    EscalationMatrixTestUtil.prepareTestContext();

    Lead leadRecord = EscalationMatrixTestUtil.createLead('Prospect', 'TaskOverdue96');
    leadRecord.FirstOverdueTaskDate__c = System.now().addHours(-100);
    leadRecord.LeadOverdueEsc36Sent__c = true;
    leadRecord.LeadOverdueEsc96Sent__c = false;
    update leadRecord;

    Task taskRecord = new Task(
      WhoId = leadRecord.Id,
      Subject = 'Follow Up Overdue 96h',
      Status = 'Not Started',
      ActivityDate = Date.today().addDays(-5)
    );
    insert taskRecord;

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
  static void testExecuteOpportunity36HourEscalation() {
    EscalationMatrixTestUtil.prepareTestContext();

    Opportunity opportunityRecord = EscalationMatrixTestUtil.createOpportunity(
      'Nurture',
      'Task Overdue Opp 36h',
      false,
      null
    );
    opportunityRecord.FirstOverdueTaskDate__c = System.now().addHours(-40);
    opportunityRecord.OppOverdueEsc36Sent__c = false;
    update opportunityRecord;

    Task taskRecord = new Task(
      WhatId = opportunityRecord.Id,
      Subject = 'Opportunity Follow Up Overdue 36h',
      Status = 'Not Started',
      ActivityDate = Date.today().addDays(-2)
    );
    insert taskRecord;

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
}