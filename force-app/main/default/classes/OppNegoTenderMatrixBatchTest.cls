/**
 * @description   Test class for OpportunityNegotiationTenderMatrixBatch.
 * @author        Anshita Chanda
 * @date          2026-08-17
 */
@IsTest
private class OppNegoTenderMatrixBatchTest {
  @IsTest
  static void testStartExecuteFinish() {
    EscalationMatrixTestUtil.prepareTestContext();

    Test.startTest();
    Database.QueryLocator locator = new OpportunityNegotiationTenderMatrixBatch().start(null);
    new OpportunityNegotiationTenderMatrixBatch().finish(null);
    Test.stopTest();

    System.assertNotEquals(null, locator);
  }

  @IsTest
  static void testExecuteNegotiationTenderEscalation() {
    Id tenderRecordTypeId = EscalationMatrixTestUtil.getTenderRecordTypeId();
    if (tenderRecordTypeId == null) {
      return;
    }

    EscalationMatrixTestUtil.prepareTestContext();

    Opportunity opportunityRecord = EscalationMatrixTestUtil.createOpportunity(
      'Negotiation',
      'Negotiation Tender Opp',
      false,
      tenderRecordTypeId
    );
    EscalationMatrixTestUtil.setOldOpportunityActivity(opportunityRecord.Id, 61);
    opportunityRecord.TenderEsc15Sent__c = false;
    opportunityRecord.TenderEsc21Sent__c = false;
    opportunityRecord.TenderEsc30Sent__c = false;
    update opportunityRecord;

    opportunityRecord = EscalationMatrixTestUtil.queryTenderOpportunity(opportunityRecord.Id);

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
}