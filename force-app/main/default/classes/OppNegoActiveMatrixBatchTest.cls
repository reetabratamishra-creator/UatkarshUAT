/**
 * @description   Test class for OpportunityNegotiationActiveMatrixBatch.
 * @author        Anshita Chanda
 * @date          2026-08-17
 */
@IsTest
private class OppNegoActiveMatrixBatchTest {
  @IsTest
  static void testStartExecuteFinish() {
    EscalationMatrixTestUtil.prepareTestContext();

    Test.startTest();
    Database.QueryLocator locator = new OpportunityNegotiationActiveMatrixBatch().start(null);
    new OpportunityNegotiationActiveMatrixBatch().finish(null);
    Test.stopTest();

    System.assertNotEquals(null, locator);
  }

  @IsTest
  static void testExecuteNegotiationActiveEscalation() {
    EscalationMatrixTestUtil.prepareTestContext();

    Opportunity opportunityRecord = EscalationMatrixTestUtil.createOpportunity(
      'Negotiation',
      'Negotiation Active Opp',
      false,
      null
    );
    EscalationMatrixTestUtil.setOldOpportunityActivity(opportunityRecord.Id, 22);
    opportunityRecord.EscalationNeg7Sent__c = false;
    opportunityRecord.EscalationNeg14Sent__c = false;
    opportunityRecord.EscalationNeg21Sent__c = false;
    update opportunityRecord;

    opportunityRecord = EscalationMatrixTestUtil.queryNegotiationActiveOpportunity(
      opportunityRecord.Id
    );

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
}