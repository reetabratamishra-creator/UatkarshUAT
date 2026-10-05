trigger OCR_Doc_Trigger on OCR_DOC__c (after insert) {
    List<Id> ids = new List<Id>();
    for (OCR_DOC__c rec : Trigger.new) {
        ids.add(rec.Id);
    }
    OCR_Doc_TriggerHandler.process(ids);
}