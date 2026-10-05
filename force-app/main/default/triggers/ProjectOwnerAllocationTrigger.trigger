trigger ProjectOwnerAllocationTrigger on Project__c (after insert) {
  ProjectOwnerAllocationHandler.handleAfterInsert(Trigger.new);
}