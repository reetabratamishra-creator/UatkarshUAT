@IsTest
private class RecordFilesListControllerTest {
    @IsTest
    static void returnsLinkedFiles() {
        Account acc = new Account(Name = 'Test Acc');
        insert acc;

        ContentVersion cv = new ContentVersion(
            Title = 'apex-test', PathOnClient = 'apex-test.log',
            VersionData = Blob.valueOf('hello')
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            LinkedEntityId = acc.Id, ContentDocumentId = docId, ShareType = 'V'
        );

        RecordFilesListController.FileResult res = RecordFilesListController.getFiles(acc.Id, 6);
        System.assertEquals(1, res.totalCount);
        System.assertEquals('apex-test', res.files[0].title);
        System.assertEquals('log', res.files[0].fileExtension);
    }
}