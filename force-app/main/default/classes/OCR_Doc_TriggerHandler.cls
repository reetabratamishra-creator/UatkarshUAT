public class OCR_Doc_TriggerHandler {
    public static void process(List<Id> recordIds) {
        for (Id recId : recordIds) {
            System.enqueueJob(
                new OCR_Doc_ProcessorQueueable(recId)
            );
        }
    }
}