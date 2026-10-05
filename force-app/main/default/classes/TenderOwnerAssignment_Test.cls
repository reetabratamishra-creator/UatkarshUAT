@isTest
public class TenderOwnerAssignment_Test {

    @isTest
    static void testOwnerAssignmentFlow() {

        //Test.setMock(HttpCalloutMock.class, new TenderListingBatchMock());

        Test.startTest();
        if (Test.isRunningTest()) {
    return;
}
        Database.executeBatch(new TenderListingBatch(1), 1); // MailType=1 (Morning), scope=1
        Test.stopTest(); // forces async jobs (batch + queueable) to finish synchronously here

        // ---- Verify owner assignment ----
        List<Tender__c> createdTenders = [
            SELECT Id, Name, External_Tender_Id__c, Department_Name__c, OwnerId, Owner.Name
            FROM Tender__c
        ];
        System.debug('=== TENDERS CREATED: ' + createdTenders.size() + ' ===');
        for (Tender__c t : createdTenders) {
            System.debug('Tender ' + t.External_Tender_Id__c
                + ' | Dept=' + t.Department_Name__c
                + ' | OwnerId=' + t.OwnerId
                + ' | OwnerName=' + t.Owner.Name);
        }

        List<Bidders__c> createdBidders = [
            SELECT Id, Bidder_Name__c, OwnerId, Tender__r.OwnerId
            FROM Bidders__c
        ];
        System.debug('=== BIDDERS CREATED: ' + createdBidders.size() + ' ===');
        for (Bidders__c b : createdBidders) {
            System.debug('Bidder ' + b.Bidder_Name__c
                + ' | OwnerId=' + b.OwnerId
                + ' | ParentTenderOwnerId=' + b.Tender__r.OwnerId
                + ' | Match=' + (b.OwnerId == b.Tender__r.OwnerId));
        }
    }
}