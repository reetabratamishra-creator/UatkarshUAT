/**
 * @description   Test class for OppNegoBudgetaryMatrixBatch.
 * @author        Anshita Chanda
 * @date          2026-08-17
 */
@IsTest
private class OppNegoBudgetaryMatrixBatchTest {
  @IsTest
  static void testStartExecuteFinish() {
    EscalationMatrixTestUtil.prepareTestContext();

    Test.startTest();
    Database.QueryLocator locator = new OppNegoBudgetaryMatrixBatch().start(null);
    new OppNegoBudgetaryMatrixBatch().finish(null);
    Test.stopTest();

    System.assertNotEquals(null, locator);
  }

  @IsTest
  static void testExecuteNegotiationBudgetaryEscalation() {
    EscalationMatrixTestUtil.prepareTestContext();

    Opportunity opportunityRecord = EscalationMatrixTestUtil.createOpportunity(
      'Negotiation',
      'Negotiation Budgetary Opp',
      true,
      null
    );
    EscalationMatrixTestUtil.setOldOpportunityActivity(opportunityRecord.Id, 61);
    opportunityRecord.NurtureEscalation48Sent__c = false;
    opportunityRecord.NurtureEscalation60Sent__c = false;
    opportunityRecord.NurtureEscalation72Sent__c = false;
    update opportunityRecord;

    opportunityRecord = EscalationMatrixTestUtil.queryBudgetaryOpportunity(opportunityRecord.Id);

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
}