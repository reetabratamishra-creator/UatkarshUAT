@IsTest
private class PolymerHDPEBatchTest {


/*
 * ============================================================
 * HTTP MOCK
 *
 * Handles:
 * 1. Tender document download
 * 2. Gemini API call
 *
 * <<< UPDATED >>> Gemini response bodies now use the new
 * matchedDepartment-based JSON shape returned by
 * PolymerHDPEGeminiService.checkFile(), replacing the old
 * excludedMatched/relevantMatched pair.
 * ============================================================
 */
private class PolymerHDPEMock implements HttpCalloutMock {

    public HttpResponse respond(HttpRequest req) {

        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');

        String endpoint = req.getEndpoint();

        /*
         * ----------------------------------------------------
         * GEMINI CALLOUT
         * ----------------------------------------------------
         */
        if (endpoint != null &&
            endpoint.contains('generateContent')) {

            String body = req.getBody();

            /*
             * HDPE match
             */
            if (body != null &&
                body.contains('HDPE_TENDER')) {

                res.setStatusCode(200);
                res.setBody(
                    '{"candidates":[{"content":{"parts":[{"text":"{\\"matchedDepartment\\":\\"HDPE\\",\\"reasoning\\":\\"HDPE product keyword matched\\"}"}]}}]}'
                );
            }

            /*
             * Polymer match
             */
            else if (body != null &&
                     body.contains('POLYMER_TENDER')) {

                res.setStatusCode(200);
                res.setBody(
                    '{"candidates":[{"content":{"parts":[{"text":"{\\"matchedDepartment\\":\\"Polymer\\",\\"reasoning\\":\\"Polymer keyword matched\\"}"}]}}]}'
                );
            }

            /*
             * No match
             */
            else if (body != null &&
                     body.contains('NO_MATCH_TENDER')) {

                res.setStatusCode(200);
                res.setBody(
                    '{"candidates":[{"content":{"parts":[{"text":"{\\"matchedDepartment\\":\\"None\\",\\"reasoning\\":\\"No keyword matched\\"}"}]}}]}'
                );
            }

            /*
             * Gemini error
             */
            else if (body != null &&
                     body.contains('GEMINI_ERROR_TENDER')) {

                res.setStatusCode(400);
                res.setBody(
                    '{"error":{"message":"Gemini test error"}}'
                );
            }

            /*
             * Default Gemini response
             */
            else {

                res.setStatusCode(200);
                res.setBody(
                    '{"candidates":[{"content":{"parts":[{"text":"{\\"matchedDepartment\\":\\"None\\",\\"reasoning\\":\\"Default test response\\"}"}]}}]}'
                );
            }

            return res;
        }

        /*
         * ----------------------------------------------------
         * DOCUMENT DOWNLOAD CALLOUT
         * ----------------------------------------------------
         */

        /*
         * HTTP 500
         */
        if (endpoint != null &&
            endpoint.contains('download500')) {

            res.setStatusCode(500);
            res.setBody('Download failed');

            return res;
        }

        /*
         * Empty document
         */
        if (endpoint != null &&
            endpoint.contains('emptyfile')) {

            res.setStatusCode(200);
            res.setBody('');

            return res;
        }

        /*
         * Download exception
         */
        if (endpoint != null &&
            endpoint.contains('downloadException')) {

            throw new CalloutException(
                'Download exception for test'
            );
        }

        /*
         * Normal document download
         */
        res.setStatusCode(200);
        res.setBody('Test tender document content');

        return res;
    }
}


/*
 * ============================================================
 * CREATE TENDER
 *
 * Tender__c.Name is Auto Number, so DO NOT assign Name.
 *
 * NOTE: Tender_Description__c and Tender_AI_Summary_JSON__c are
 * intentionally left unset so PolymerHDPEPromptService.checkDepartment()
 * resolves fired=false (no Step 1 input available) and every Tender
 * falls straight through to Step 2 (document/Gemini check), matching
 * the pre-existing test expectations below.
 * ============================================================
 */
private static Tender__c createTender() {

    Tender__c tender = new Tender__c();

    tender.MergeProduct__c = true;
    tender.Department_Name__c = null;
    tender.Polymer_HDPE_Stage_Check__c = null;

    insert tender;

    return tender;
}


/*
 * ============================================================
 * CREATE DOCUMENT
 *
 * Dynamically finds the lookup/master-detail field pointing
 * to Tender__c.
 * ============================================================
 */
private static Tender_Docoment_Details__c createDocument(
    Id tenderId,
    String fileName,
    String typeValue,
    String downloadUrl
) {

    Tender_Docoment_Details__c doc =
        new Tender_Docoment_Details__c();

    doc.Name__c = fileName;
    doc.Type__c = typeValue;

    /*
     * Download_URL_Text__c
     */
    doc.Download_URL_Text__c = downloadUrl;

    /*
     * Download_URL__c
     */
    Map<String, Schema.SObjectField> documentFields =
        Tender_Docoment_Details__c.SObjectType
            .getDescribe()
            .fields
            .getMap();

    if (documentFields.containsKey('Download_URL__c')) {

        doc.put(
            'Download_URL__c',
            downloadUrl
        );
    }

    /*
     * Find Tender__c lookup/master-detail field
     */
    for (String fieldName : documentFields.keySet()) {

        Schema.DescribeFieldResult fieldDescribe =
            documentFields
                .get(fieldName)
                .getDescribe();

        if (fieldDescribe.getType() ==
            Schema.DisplayType.REFERENCE) {

            for (Schema.SObjectType referenceType :
                fieldDescribe.getReferenceTo()) {

                if (referenceType ==
                    Tender__c.SObjectType) {

                    doc.put(
                        fieldName,
                        tenderId
                    );

                    break;
                }
            }
        }
    }

    insert doc;

    return doc;
}


/*
 * ============================================================
 * QUERY TENDER WITH CHILD DOCUMENTS
 *
 * <<< FIXED >>> Added Tender_Description__c. PolymerHDPEBatch.execute()
 * now runs Step 1 (PolymerHDPEPromptService.checkDepartment()) BEFORE
 * the document loop, and that method reads Tender_Description__c
 * unconditionally. Without querying it here, every batch.execute()
 * call in this test class threw SObjectException ("without querying
 * the requested field"), which was silently caught by the outer
 * try/catch in PolymerHDPEBatch and turned every result into
 * "Failed - Unexpected Error" - this was the root cause of all the
 * assertion failures.
 * ============================================================
 */
private static Tender__c getTenderWithDocuments(
    Id tenderId
) {

    return [
        SELECT
            Id,
            Name,
            MergeProduct__c,
            Product_Name__c,
            Department_Name__c,
            Tender_Description__c,
            Is_checked_Polymer_HDPE__c,
            Reading_Polymer_HDPE_summary__c,
            Polymer_HDPE_Stage_Check__c,
            (
                SELECT
                    Id,
                    Name__c,
                    Type__c,
                    Download_URL__c,
                    Download_URL_Text__c,
                    Document_Id__c,
                    CreatedDate
                FROM Tender_Docoment_Details__r
                ORDER BY CreatedDate DESC
            )
        FROM Tender__c
        WHERE Id = :tenderId
        LIMIT 1
    ];
}


/*
 * ============================================================
 * TEST START()
 * ============================================================
 */
@IsTest
static void testStart() {

    createTender();

    PolymerHDPEBatch batch =
        new PolymerHDPEBatch();

    Test.startTest();

    Database.QueryLocator locator =
        batch.start(null);

    Test.stopTest();

    System.assertNotEquals(
        null,
        locator,
        'QueryLocator should not be null.'
    );
}


/*
 * ============================================================
 * TEST FINISH()
 * ============================================================
 */
@IsTest
static void testFinish() {

    PolymerHDPEBatch batch =
        new PolymerHDPEBatch();

    Test.startTest();

    batch.finish(null);

    Test.stopTest();

    System.assert(
        true,
        'Finish method executed successfully.'
    );
}


/*
 * ============================================================
 * NO DOCUMENTS
 *
 * Expected:
 * Product = HDPE
 * Checked = false
 * Stage = Failed - No Documents
 * ============================================================
 */
@IsTest
static void testNoDocuments() {

    Tender__c tender =
        createTender();

    Tender__c scopeTender =
        getTenderWithDocuments(tender.Id);

    PolymerHDPEBatch batch =
        new PolymerHDPEBatch();

    Test.startTest();

    batch.execute(
        null,
        new List<Tender__c>{
            scopeTender
        }
    );

    Test.stopTest();

    Tender__c result = [
        SELECT
            Product_Name__c,
            Department_Name__c,
            Is_checked_Polymer_HDPE__c,
            Polymer_HDPE_Stage_Check__c
        FROM Tender__c
        WHERE Id = :tender.Id
    ];

    System.assertEquals(
        'HDPE',
        result.Product_Name__c
    );

    System.assertEquals(
        'HDPE',
        result.Department_Name__c
    );

    System.assertEquals(
        false,
        result.Is_checked_Polymer_HDPE__c
    );

    System.assertEquals(
        'Failed - No Documents',
        result.Polymer_HDPE_Stage_Check__c
    );
}


/*
 * ============================================================
 * UNSUPPORTED FILE
 *
 * Expected:
 * Product = HDPE
 * Checked = true
 * Stage = No Supported Files
 * ============================================================
 */
@IsTest
static void testUnsupportedFile() {

    Tender__c tender =
        createTender();

    createDocument(
        tender.Id,
        'Tender.zip',
        'ZIP',
        'https://unsupported.test/file'
    );

    Tender__c scopeTender =
        getTenderWithDocuments(tender.Id);

    PolymerHDPEBatch batch =
        new PolymerHDPEBatch();

    Test.startTest();

    batch.execute(
        null,
        new List<Tender__c>{
            scopeTender
        }
    );

    Test.stopTest();

    Tender__c result = [
        SELECT
            Product_Name__c,
            Department_Name__c,
            Is_checked_Polymer_HDPE__c,
            Polymer_HDPE_Stage_Check__c
        FROM Tender__c
        WHERE Id = :tender.Id
    ];

    System.assertEquals(
        'HDPE',
        result.Product_Name__c
    );

    System.assertEquals(
        'HDPE',
        result.Department_Name__c
    );

    System.assertEquals(
        true,
        result.Is_checked_Polymer_HDPE__c
    );

    System.assertEquals(
        'No Supported Files',
        result.Polymer_HDPE_Stage_Check__c
    );
}


/*
 * ============================================================
 * BLANK DOWNLOAD URL
 *
 * Supported file but no URL.
 *
 * Expected:
 * Product = HDPE
 * Checked = true
 * Stage = Checked - No Match
 * ============================================================
 */
@IsTest
static void testBlankDownloadUrl() {

    Tender__c tender =
        createTender();

    createDocument(
        tender.Id,
        'BlankUrl.pdf',
        'PDF',
        null
    );

    Tender__c scopeTender =
        getTenderWithDocuments(tender.Id);

    PolymerHDPEBatch batch =
        new PolymerHDPEBatch();

    Test.startTest();

    batch.execute(
        null,
        new List<Tender__c>{
            scopeTender
        }
    );

    Test.stopTest();

    Tender__c result = [
        SELECT
            Product_Name__c,
            Department_Name__c,
            Is_checked_Polymer_HDPE__c,
            Polymer_HDPE_Stage_Check__c
        FROM Tender__c
        WHERE Id = :tender.Id
    ];

    System.assertEquals(
        'HDPE',
        result.Product_Name__c
    );

    System.assertEquals(
        'HDPE',
        result.Department_Name__c
    );

    System.assertEquals(
        true,
        result.Is_checked_Polymer_HDPE__c
    );

    System.assertEquals(
        'Checked - No Match',
        result.Polymer_HDPE_Stage_Check__c
    );
}


/*
 * ============================================================
 * DOWNLOAD HTTP ERROR
 *
 * Expected:
 * Product = HDPE
 * Checked = false
 * Stage = Failed - Will Retry
 * ============================================================
 */
@IsTest
static void testDownloadHttpError() {

    Tender__c tender =
        createTender();

    createDocument(
        tender.Id,
        'Download500.pdf',
        'PDF',
        'https://download500.test/file'
    );

    Tender__c scopeTender =
        getTenderWithDocuments(tender.Id);

    Test.setMock(
        HttpCalloutMock.class,
        new PolymerHDPEMock()
    );

    PolymerHDPEBatch batch =
        new PolymerHDPEBatch();

    Test.startTest();

    batch.execute(
        null,
        new List<Tender__c>{
            scopeTender
        }
    );

    Test.stopTest();

    Tender__c result = [
        SELECT
            Product_Name__c,
            Department_Name__c,
            Is_checked_Polymer_HDPE__c,
            Polymer_HDPE_Stage_Check__c
        FROM Tender__c
        WHERE Id = :tender.Id
    ];

    System.assertEquals(
        'HDPE',
        result.Product_Name__c
    );

    System.assertEquals(
        'HDPE',
        result.Department_Name__c
    );

    System.assertEquals(
        false,
        result.Is_checked_Polymer_HDPE__c
    );

    System.assertEquals(
        'Failed - Will Retry',
        result.Polymer_HDPE_Stage_Check__c
    );
}


/*
 * ============================================================
 * DOWNLOAD EXCEPTION
 * ============================================================
 */
@IsTest
static void testDownloadException() {

    Tender__c tender =
        createTender();

    createDocument(
        tender.Id,
        'DownloadException.pdf',
        'PDF',
        'https://downloadException.test/file'
    );

    Tender__c scopeTender =
        getTenderWithDocuments(tender.Id);

    Test.setMock(
        HttpCalloutMock.class,
        new PolymerHDPEMock()
    );

    PolymerHDPEBatch batch =
        new PolymerHDPEBatch();

    Test.startTest();

    batch.execute(
        null,
        new List<Tender__c>{
            scopeTender
        }
    );

    Test.stopTest();

    Tender__c result = [
        SELECT
            Product_Name__c,
            Department_Name__c,
            Is_checked_Polymer_HDPE__c,
            Polymer_HDPE_Stage_Check__c
        FROM Tender__c
        WHERE Id = :tender.Id
    ];

    System.assertEquals(
        'HDPE',
        result.Product_Name__c
    );

    System.assertEquals(
        'HDPE',
        result.Department_Name__c
    );

    System.assertEquals(
        false,
        result.Is_checked_Polymer_HDPE__c
    );

    System.assertEquals(
        'Failed - Will Retry',
        result.Polymer_HDPE_Stage_Check__c
    );
}


/*
 * ============================================================
 * EMPTY FILE
 * ============================================================
 */
@IsTest
static void testEmptyFile() {

    Tender__c tender =
        createTender();

    createDocument(
        tender.Id,
        'EmptyFile.pdf',
        'PDF',
        'https://emptyfile.test/file'
    );

    Tender__c scopeTender =
        getTenderWithDocuments(tender.Id);

    Test.setMock(
        HttpCalloutMock.class,
        new PolymerHDPEMock()
    );

    PolymerHDPEBatch batch =
        new PolymerHDPEBatch();

    Test.startTest();

    batch.execute(
        null,
        new List<Tender__c>{
            scopeTender
        }
    );

    Test.stopTest();

    Tender__c result = [
        SELECT
            Product_Name__c,
            Department_Name__c,
            Is_checked_Polymer_HDPE__c,
            Polymer_HDPE_Stage_Check__c
        FROM Tender__c
        WHERE Id = :tender.Id
    ];

    System.assertEquals(
        'HDPE',
        result.Product_Name__c
    );

    System.assertEquals(
        'HDPE',
        result.Department_Name__c
    );

    System.assertEquals(
        false,
        result.Is_checked_Polymer_HDPE__c
    );

    System.assertEquals(
        'Failed - Will Retry',
        result.Polymer_HDPE_Stage_Check__c
    );
}


/*
 * ============================================================
 * GEMINI ERROR
 * ============================================================
 */
@IsTest
static void testGeminiError() {

    Tender__c tender =
        createTender();

    createDocument(
        tender.Id,
        'GEMINI_ERROR_TENDER.pdf',
        'PDF',
        'https://geminierror.test/file'
    );

    Tender__c scopeTender =
        getTenderWithDocuments(tender.Id);

    Test.setMock(
        HttpCalloutMock.class,
        new PolymerHDPEMock()
    );

    PolymerHDPEBatch batch =
        new PolymerHDPEBatch();

    Test.startTest();

    batch.execute(
        null,
        new List<Tender__c>{
            scopeTender
        }
    );

    Test.stopTest();

    Tender__c result = [
        SELECT
            Product_Name__c,
            Department_Name__c,
            Is_checked_Polymer_HDPE__c,
            Polymer_HDPE_Stage_Check__c
        FROM Tender__c
        WHERE Id = :tender.Id
    ];

    System.assertEquals(
        'HDPE',
        result.Product_Name__c
    );

    System.assertEquals(
        'HDPE',
        result.Department_Name__c
    );

    System.assertEquals(
        false,
        result.Is_checked_Polymer_HDPE__c
    );

    System.assertEquals(
        'Failed - Will Retry',
        result.Polymer_HDPE_Stage_Check__c
    );
}


/*
 * ============================================================
 * HDPE MATCH
 * ============================================================
 */
@IsTest
static void testHDPEMatch() {

    Tender__c tender =
        createTender();

    createDocument(
        tender.Id,
        'HDPE_TENDER.pdf',
        'PDF',
        'https://hdpe.test/file'
    );

    Tender__c scopeTender =
        getTenderWithDocuments(tender.Id);

    Test.setMock(
        HttpCalloutMock.class,
        new PolymerHDPEMock()
    );

    PolymerHDPEBatch batch =
        new PolymerHDPEBatch();

    Test.startTest();

    batch.execute(
        null,
        new List<Tender__c>{
            scopeTender
        }
    );

    Test.stopTest();

    Tender__c result = [
        SELECT
            Product_Name__c,
            Department_Name__c,
            Is_checked_Polymer_HDPE__c,
            Polymer_HDPE_Stage_Check__c
        FROM Tender__c
        WHERE Id = :tender.Id
    ];

    System.assertEquals(
        'HDPE',
        result.Product_Name__c
    );

    System.assertEquals(
        'HDPE',
        result.Department_Name__c
    );

    System.assertEquals(
        true,
        result.Is_checked_Polymer_HDPE__c
    );

    System.assertEquals(
        'Matched',
        result.Polymer_HDPE_Stage_Check__c
    );
}


/*
 * ============================================================
 * POLYMER MATCH
 * ============================================================
 */
@IsTest
static void testPolymerMatch() {

    Tender__c tender =
        createTender();

    createDocument(
        tender.Id,
        'POLYMER_TENDER.pdf',
        'PDF',
        'https://polymer.test/file'
    );

    Tender__c scopeTender =
        getTenderWithDocuments(tender.Id);

    Test.setMock(
        HttpCalloutMock.class,
        new PolymerHDPEMock()
    );

    PolymerHDPEBatch batch =
        new PolymerHDPEBatch();

    Test.startTest();

    batch.execute(
        null,
        new List<Tender__c>{
            scopeTender
        }
    );

    Test.stopTest();

    Tender__c result = [
        SELECT
            Product_Name__c,
            Department_Name__c,
            Is_checked_Polymer_HDPE__c,
            Polymer_HDPE_Stage_Check__c
        FROM Tender__c
        WHERE Id = :tender.Id
    ];

    System.assertEquals(
        'Polymer',
        result.Product_Name__c
    );

    System.assertEquals(
        'Polymer',
        result.Department_Name__c
    );

    System.assertEquals(
        true,
        result.Is_checked_Polymer_HDPE__c
    );

    System.assertEquals(
        'Matched',
        result.Polymer_HDPE_Stage_Check__c
    );
}


/*
 * ============================================================
 * NO MATCH
 * ============================================================
 */
@IsTest
static void testNoMatch() {

    Tender__c tender =
        createTender();

    createDocument(
        tender.Id,
        'NO_MATCH_TENDER.pdf',
        'PDF',
        'https://nomatch.test/file'
    );

    Tender__c scopeTender =
        getTenderWithDocuments(tender.Id);

    Test.setMock(
        HttpCalloutMock.class,
        new PolymerHDPEMock()
    );

    PolymerHDPEBatch batch =
        new PolymerHDPEBatch();

    Test.startTest();

    batch.execute(
        null,
        new List<Tender__c>{
            scopeTender
        }
    );

    Test.stopTest();

    Tender__c result = [
        SELECT
            Product_Name__c,
            Department_Name__c,
            Is_checked_Polymer_HDPE__c,
            Polymer_HDPE_Stage_Check__c
        FROM Tender__c
        WHERE Id = :tender.Id
    ];

    System.assertEquals(
        'HDPE',
        result.Product_Name__c
    );

    System.assertEquals(
        'HDPE',
        result.Department_Name__c
    );

    System.assertEquals(
        true,
        result.Is_checked_Polymer_HDPE__c
    );

    System.assertEquals(
        'Checked - No Match',
        result.Polymer_HDPE_Stage_Check__c
    );
}


/*
 * ============================================================
 * FULL BATCH EXECUTION
 *
 * Covers:
 * start()
 * execute()
 * finish()
 * ============================================================
 */
@IsTest
static void testFullBatchExecution() {

    Tender__c tender =
        createTender();

    createDocument(
        tender.Id,
        'HDPE_TENDER_BATCH.pdf',
        'PDF',
        'https://batch.test/file'
    );

    Test.setMock(
        HttpCalloutMock.class,
        new PolymerHDPEMock()
    );

    Test.startTest();

    Database.executeBatch(
        new PolymerHDPEBatch(),
        1
    );

    Test.stopTest();

    Tender__c result = [
        SELECT
            Product_Name__c,
            Department_Name__c,
            Is_checked_Polymer_HDPE__c,
            Polymer_HDPE_Stage_Check__c,
            Reading_Polymer_HDPE_summary__c
        FROM Tender__c
        WHERE Id = :tender.Id
    ];

    System.assertEquals(
        'HDPE',
        result.Product_Name__c
    );

    System.assertEquals(
        'HDPE',
        result.Department_Name__c
    );

    System.assertEquals(
        true,
        result.Is_checked_Polymer_HDPE__c
    );

    System.assertEquals(
        'Matched',
        result.Polymer_HDPE_Stage_Check__c
    );

    System.assertNotEquals(
        null,
        result.Reading_Polymer_HDPE_summary__c
    );
}


}