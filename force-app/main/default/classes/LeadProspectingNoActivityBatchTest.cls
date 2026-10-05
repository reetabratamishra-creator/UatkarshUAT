/**
 * @description   Test class for LeadProspectingNoActivityBatch.
 * @author        Anshita Chanda
 * @date          2026-08-17
 */
@IsTest
private class LeadProspectingNoActivityBatchTest {
  @IsTest
  static void testStartExecuteFinish() {
    EscalationMatrixTestUtil.prepareTestContext();

    Test.startTest();
    Database.QueryLocator locator = new LeadProspectingNoActivityBatch().start(null);
    new LeadProspectingNoActivityBatch().finish(null);
    Test.stopTest();

    System.assertNotEquals(null, locator);
  }

  @IsTest
  static void testExecute24HourEscalation() {
    EscalationMatrixTestUtil.prepareTestContext();

    Lead leadRecord = EscalationMatrixTestUtil.createLead('Prospecting', 'Prospecting24');
    leadRecord.Prospecting_Escalation_24_Sent__c = false;
    update as system leadRecord;
    LeadProspectingNoActivityBatch.setTestLastProspectingActivity(
      leadRecord.Id,
      System.now().addHours(-25)
    );

    leadRecord = EscalationMatrixTestUtil.queryProspectingLead(leadRecord.Id);

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
  static void testExecute48And96HourEscalation() {
    EscalationMatrixTestUtil.prepareTestContext();

    Lead leadRecord = EscalationMatrixTestUtil.createLead('Prospecting', 'Prospecting96');
    leadRecord.Prospecting_Escalation_24_Sent__c = true;
    leadRecord.Prospecting_Escalation_48_Sent__c = false;
    leadRecord.Prospecting_Escalation_72_Sent__c = false;
    leadRecord.Prospecting_Escalation_168_Sent__c = true;
    update as system leadRecord;
    LeadProspectingNoActivityBatch.setTestLastProspectingActivity(
      leadRecord.Id,
      System.now().addHours(-100)
    );

    leadRecord = EscalationMatrixTestUtil.queryProspectingLead(leadRecord.Id);

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
  static void testExecute168HourEscalation() {
    EscalationMatrixTestUtil.prepareTestContext();

    Lead leadRecord = EscalationMatrixTestUtil.createLead('Prospecting', 'Prospecting168');
    leadRecord.Prospecting_Escalation_24_Sent__c = true;
    leadRecord.Prospecting_Escalation_48_Sent__c = true;
    leadRecord.Prospecting_Escalation_72_Sent__c = true;
    leadRecord.Prospecting_Escalation_168_Sent__c = false;
    update as system leadRecord;
    LeadProspectingNoActivityBatch.setTestLastProspectingActivity(
      leadRecord.Id,
      System.now().addHours(-170)
    );

    leadRecord = EscalationMatrixTestUtil.queryProspectingLead(leadRecord.Id);

    Test.startTest();
    new LeadProspectingNoActivityBatch().execute(null, new List<Lead>{ leadRecord });
    Test.stopTest();

    Lead updatedLead = [
      SELECT Prospecting_Escalation_168_Sent__c
      FROM Lead
      WHERE Id = :leadRecord.Id
    ];
    System.assertEquals(true, updatedLead.Prospecting_Escalation_168_Sent__c);
  }
}