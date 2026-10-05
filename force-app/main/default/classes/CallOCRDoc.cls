public with sharing class CallOCRDoc {

    @InvocableMethod(label='Start OCR Analysis')
    public static void start(List<Id> recordIds) {

        for(Id recId : recordIds){
            System.enqueueJob(
                new Job1_UploadFilesQueueable(recId)
            );
        }
    }
}