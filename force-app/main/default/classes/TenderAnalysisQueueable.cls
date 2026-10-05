public class TenderAnalysisQueueable
implements Queueable, Database.AllowsCallouts {

    private Id docId;

    public TenderAnalysisQueueable(Id docId){
        this.docId = docId;
    }

    public void execute(QueueableContext qc){

        OCR_DOC__c doc = [
            SELECT Id,
                   AI_Status__c,
                   AI_Response__c
            FROM OCR_DOC__c
            WHERE Id = :docId
            LIMIT 1
        ];

        /*
        try {

            doc.AI_Status__c = 'Processing';
            update doc;

            // Get all files linked to OCR_DOC__c
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :docId
            ];

            Set<Id> documentIds = new Set<Id>();

            for(ContentDocumentLink cdl : links){
                documentIds.add(cdl.ContentDocumentId);
            }

            List<ContentVersion> files = new List<ContentVersion>();

            if(!documentIds.isEmpty()){

                files = [
                    SELECT Id,
                           Title,
                           FileExtension,
                           VersionData,
                           ContentDocumentId
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :documentIds
                    AND IsLatest = true
                ];
            }

            if(files.isEmpty()){

                doc.AI_Status__c = 'Failed';
                doc.AI_Response__c = 'No files found.';
                update doc;
                return;
            }

            String metadataPrompt =
                MetadataService.getMetadataPrompt();

            List<String> responses =
                new List<String>();

            for(ContentVersion cv : files){

                try{

                    System.debug(
                        'Processing File => ' +
                        cv.Title +
                        '.' +
                        cv.FileExtension
                    );

                    String response =
                        GeminiService.analyzeFile(
                            cv,
                            metadataPrompt
                        );

                    responses.add(
                        'FILE : ' +
                        cv.Title +
                        '\n' +
                        response
                    );

                }
                catch(Exception fileEx){

                    responses.add(
                        'FILE : ' +
                        cv.Title +
                        '\nERROR : ' +
                        fileEx.getMessage()
                    );
                }
            }

            doc.AI_Response__c =
                String.join(
                    responses,
                    '\n\n====================\n\n'
                );

            doc.AI_Status__c =
                'Completed';

            update doc;

        }
        catch(Exception ex){

            doc.AI_Status__c =
                'Failed';

            doc.AI_Response__c =
                ex.getMessage() +
                '\n\n' +
                ex.getStackTraceString();

            update doc;

            System.debug(
                'TenderAnalysisQueueable Error : ' +
                ex.getMessage()
            );
        }*/
    }
}