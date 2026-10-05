// ============================================================
// CLASS 7 — TenderAnalyzerBatch.cls
// ─────────────────────────────────────────────────────────────
// Processes 500 OCR_DOC__c records per day
// scope=1 ensures one Queueable fires per record
// ─────────────────────────────────────────────────────────────
// HOW TO RUN:
//   Database.executeBatch(new TenderAnalyzerBatch(), 1);
// ============================================================
public with sharing class TenderAnalyzerBatch
    implements Database.Batchable<SObject>, Database.AllowsCallouts {

    // ─────────────────────────────────────────────────────────
    // START — query all OCR_DOC__c records pending processing
    // ─────────────────────────────────────────────────────────
    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('===== TenderAnalyzerBatch.start =====');
        return Database.getQueryLocator([
            SELECT Id, Name, AI_Status__c
            FROM   OCR_DOC__c
            WHERE  AI_Status__c = 'Pending'
            ORDER BY CreatedDate ASC
        ]);
    }

    // ─────────────────────────────────────────────────────────
    // EXECUTE — called once per record (scope=1)
    // Fires Queueable chain for that one record
    // ─────────────────────────────────────────────────────────
    public void execute(Database.BatchableContext bc, List<OCR_DOC__c> records) {
        OCR_DOC__c record = records[0];
        System.debug('Processing OCR_DOC__c: ' + record.Id + ' | ' + record.Name);

        // Mark as Processing before firing Queueable
        record.AI_Status__c = 'Processing';
        update record;

        // Fire Job1 — start of Queueable chain
        System.enqueueJob(new Job1_UploadFilesQueueable_Batch(record.Id));
    }

    // ─────────────────────────────────────────────────────────
    // FINISH — called after all records processed
    // ─────────────────────────────────────────────────────────
    public void finish(Database.BatchableContext bc) {
        System.debug('===== TenderAnalyzerBatch.finish — All records processed =====');
    }
}


//Database.executeBatch(new TenderAnalyzerBatch(), 1);