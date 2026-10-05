trigger TenderOwnerAllocationTrigger on Tender__c (after insert) {
TenderOwnerAllocationHandler.handleAfterInsert(Trigger.new);
}