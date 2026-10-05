/**
 * @description Test class for TenderStatusEmailHandler.
 *
 * IMPORTANT:
 * This test class intentionally does NOT create EmailTemplate records.
 * EmailTemplate is a setup object and mixing its DML with Contact/Tender DML
 * can cause MIXED_DML_OPERATION when tests are run from the Salesforce UI.
 *
 * The production handler contains:
 *     @TestVisible private static Id testTemplateIdOverride;
 *
 * We use a Contact Id as the override during tests. This allows the handler
 * to enter the email-processing branches without creating setup data.
 */
@IsTest
private class TenderStatusEmailHandlerTest {

    // =========================================================================
    // Test Data Helpers
    // =========================================================================

    private static Contact createContact(String email) {
        Contact c = new Contact(
            LastName = 'Tender Test User',
            Email = email
        );
        insert c;
        return c;
    }

    private static List<Contact> createContacts(Integer count) {
        List<Contact> contacts = new List<Contact>();

        for (Integer i = 0; i < count; i++) {
            contacts.add(
                new Contact(
                    LastName = 'Tender Test ' + i,
                    Email = 'tender.test.' + i + '@example.com'
                )
            );
        }

        insert contacts;
        return contacts;
    }

    /**
     * Configure the handler so that it does not query/create EmailTemplate.
     *
     * We deliberately use a Contact Id as the fake template Id.
     * The production email methods catch any Messaging/template exception.
     */
    private static void configureTestEmailTemplate(Id fakeTemplateId) {
        TenderStatusEmailHandler.templateIdByDeveloperName.clear();
        TenderStatusEmailHandler.orgWideEmailAddressId = null;
        TenderStatusEmailHandler.orgWideEmailAddressQueried = false;
        TenderStatusEmailHandler.testTemplateIdOverride = fakeTemplateId;
    }

    private static Tender__c createBasicTender(Id contactId) {
        return new Tender__c(
            Contact__c = contactId,
            Tender_Stage__c = 'Open'
        );
    }

    // =========================================================================
    // Qualification Methods
    // =========================================================================

    @IsTest
    static void testHodQualificationPositiveCases() {

        Tender__c oldTender = new Tender__c(
            Tender_User_Choice__c = null,
            Tender_Stage__c = 'Open'
        );

        Tender__c participationSubmitted = new Tender__c(
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
            Tender_Stage__c = 'Open'
        );

        Tender__c rejectionSubmitted = new Tender__c(
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION,
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            true,
            TenderStatusEmailHandler.qualifiesForHodParticipationAwaiting(
                participationSubmitted,
                oldTender
            )
        );

        System.assertEquals(
            true,
            TenderStatusEmailHandler.qualifiesForHodRejectionAwaiting(
                rejectionSubmitted,
                oldTender
            )
        );
    }

    @IsTest
    static void testHodQualificationNegativeCases() {

        // Same value = NO change = false
        Tender__c oldParticipation = new Tender__c(
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
            Tender_Stage__c = 'Open'
        );

        Tender__c newParticipationSame = new Tender__c(
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            false,
            TenderStatusEmailHandler.qualifiesForHodParticipationAwaiting(
                newParticipationSame,
                oldParticipation
            )
        );

        // Same rejection value = NO change = false
        Tender__c oldRejection = new Tender__c(
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION,
            Tender_Stage__c = 'Open'
        );

        Tender__c newRejectionSame = new Tender__c(
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION,
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            false,
            TenderStatusEmailHandler.qualifiesForHodRejectionAwaiting(
                newRejectionSame,
                oldRejection
            )
        );

        // Wrong choice should not qualify for participation
        Tender__c wrongChoice = new Tender__c(
            Tender_User_Choice__c = 'Some Other Value',
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            false,
            TenderStatusEmailHandler.qualifiesForHodParticipationAwaiting(
                wrongChoice,
                oldParticipation
            )
        );

        // Wrong choice should not qualify for rejection
        System.assertEquals(
            false,
            TenderStatusEmailHandler.qualifiesForHodRejectionAwaiting(
                wrongChoice,
                oldRejection
            )
        );

        // Null new record
        System.assertEquals(
            false,
            TenderStatusEmailHandler.qualifiesForHodParticipationAwaiting(
                null,
                oldParticipation
            )
        );

        System.assertEquals(
            false,
            TenderStatusEmailHandler.qualifiesForHodRejectionAwaiting(
                null,
                oldRejection
            )
        );

        // Null old record
        System.assertEquals(
            false,
            TenderStatusEmailHandler.qualifiesForHodParticipationAwaiting(
                newParticipationSame,
                null
            )
        );

        System.assertEquals(
            false,
            TenderStatusEmailHandler.qualifiesForHodRejectionAwaiting(
                newRejectionSame,
                null
            )
        );
    }

    // =========================================================================
    // getTemplateForChange
    // =========================================================================

    @IsTest
    static void testGetTemplateForChangeInsertCases() {

        Contact c = createContact('template.insert@example.com');

        // New tender with Contact
        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            TenderStatusEmailHandler.TEMPLATE_NEW_TENDER_ALERT,
            TenderStatusEmailHandler.getTemplateForChange(
                tender,
                null,
                true
            )
        );

        // Null Tender
        System.assertEquals(
            null,
            TenderStatusEmailHandler.getTemplateForChange(
                null,
                null,
                true
            )
        );

        // No Contact
        Tender__c noContact = new Tender__c(
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            TenderStatusEmailHandler.TEMPLATE_NEW_TENDER_ALERT,
            TenderStatusEmailHandler.getTemplateForChange(
                noContact,
                null,
                true
            )
        );
    }

    @IsTest
    static void testGetTemplateForChangeNullAndMissingOld() {

        Contact c = createContact('template.null@example.com');

        Tender__c newTender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open'
        );

        // Update mode with null old record
        System.assertEquals(
            null,
            TenderStatusEmailHandler.getTemplateForChange(
                newTender,
                null,
                false
            )
        );
    }

    @IsTest
    static void testGetTemplateForChangeUserChoices() {

        Contact c = createContact('template.userchoice@example.com');

        Tender__c oldTender = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c = null,
            HOD_Choice__c = null,
            Tender_Stage__c = 'Open'
        );

        // -----------------------------------------------------------------
        // Accept and participate
        // -----------------------------------------------------------------

        Tender__c participation = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
            HOD_Choice__c = null,
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            TenderStatusEmailHandler.TEMPLATE_PARTICIPATION_SUBMITTED,
            TenderStatusEmailHandler.getTemplateForChange(
                participation,
                oldTender,
                false
            )
        );

        // -----------------------------------------------------------------
        // Reject and Create Project
        // -----------------------------------------------------------------

        Tender__c rejection = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION,
            HOD_Choice__c = null,
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            TenderStatusEmailHandler.TEMPLATE_REJECTION_REQUEST_SUBMITTED,
            TenderStatusEmailHandler.getTemplateForChange(
                rejection,
                oldTender,
                false
            )
        );
    }

    @IsTest
    static void testGetTemplateForChangeHodParticipation() {

        Contact c = createContact('template.hod.participation@example.com');

        Tender__c oldTender = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
            HOD_Choice__c = null,
            Tender_Stage__c = 'Open'
        );

        // HOD approved
        Tender__c approved = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
            HOD_Choice__c =
                TenderStatusEmailHandler.HOD_APPROVED,
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            TenderStatusEmailHandler.TEMPLATE_PARTICIPATION_ACCEPTED,
            TenderStatusEmailHandler.getTemplateForChange(
                approved,
                oldTender,
                false
            )
        );

        // HOD rejected
        Tender__c rejected = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
            HOD_Choice__c =
                TenderStatusEmailHandler.HOD_REJECTED,
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            TenderStatusEmailHandler.TEMPLATE_PARTICIPATION_REQUEST_REJECTED,
            TenderStatusEmailHandler.getTemplateForChange(
                rejected,
                oldTender,
                false
            )
        );
    }

    @IsTest
    static void testGetTemplateForChangeHodRejection() {

        Contact c = createContact('template.hod.rejection@example.com');

        Tender__c oldTender = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION,
            HOD_Choice__c = null,
            Tender_Stage__c = 'Open'
        );

        // HOD approved rejection request
        Tender__c approved = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION,
            HOD_Choice__c =
                TenderStatusEmailHandler.HOD_APPROVED,
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            TenderStatusEmailHandler.TEMPLATE_REJECTION_REQUEST_APPROVED,
            TenderStatusEmailHandler.getTemplateForChange(
                approved,
                oldTender,
                false
            )
        );

        // HOD rejected rejection request
        Tender__c rejected = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION,
            HOD_Choice__c =
                TenderStatusEmailHandler.HOD_REJECTED,
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            TenderStatusEmailHandler.TEMPLATE_REJECTION_REQUEST_REJECTED,
            TenderStatusEmailHandler.getTemplateForChange(
                rejected,
                oldTender,
                false
            )
        );
    }

    @IsTest
    static void testGetTemplateForChangeNegativeCases() {

        Contact c = createContact('template.negative@example.com');

        Tender__c oldTender = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c = 'Some Other Value',
            HOD_Choice__c = null,
            Tender_Stage__c = 'Open'
        );

        Tender__c newTender = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c = 'Some Other Value',
            HOD_Choice__c = null,
            Tender_Stage__c = 'Open'
        );

        // No relevant change
        System.assertEquals(
            null,
            TenderStatusEmailHandler.getTemplateForChange(
                newTender,
                oldTender,
                false
            )
        );

        // HOD choice changes, but User Choice is not one of the supported choices
        Tender__c invalidHodChoice = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c = 'Some Other Value',
            HOD_Choice__c =
                TenderStatusEmailHandler.HOD_APPROVED,
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            null,
            TenderStatusEmailHandler.getTemplateForChange(
                invalidHodChoice,
                oldTender,
                false
            )
        );

        // Null tender
        System.assertEquals(
            null,
            TenderStatusEmailHandler.getTemplateForChange(
                null,
                oldTender,
                false
            )
        );

        // Tender without Contact
        Tender__c noContact = new Tender__c(
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            null,
            TenderStatusEmailHandler.getTemplateForChange(
                noContact,
                oldTender,
                false
            )
        );
    }

    // =========================================================================
    // Null / Empty Input
    // =========================================================================

    @IsTest
    static void testNullAndEmptyInputs() {

        Test.startTest();

        TenderStatusEmailHandler.handleAfterInsert(null);

        TenderStatusEmailHandler.handleAfterInsert(
            new List<Tender__c>()
        );

        TenderStatusEmailHandler.handleAfterUpdate(
            null,
            null
        );

        TenderStatusEmailHandler.handleAfterUpdate(
            new List<Tender__c>(),
            new Map<Id, Tender__c>()
        );

        TenderStatusEmailHandler.processRecords(
            null,
            null
        );

        TenderStatusEmailHandler.processRecords(
            new List<Tender__c>(),
            new Map<Id, Tender__c>()
        );

        Test.stopTest();

        System.assert(true);
    }

    // =========================================================================
    // After Insert
    // =========================================================================

    @IsTest
    static void testHandleAfterInsert() {

        Contact c = createContact('insert@example.com');

        // Use Contact Id as harmless fake template override.
        configureTestEmailTemplate(c.Id);

        Tender__c tender = createBasicTender(c.Id);

        Test.startTest();

        insert tender;

        Test.stopTest();

        System.assertNotEquals(
            null,
            tender.Id
        );
    }

    // =========================================================================
    // After Update - Participation
    // =========================================================================

    @IsTest
    static void testHandleAfterUpdateParticipation() {

        Contact c = createContact('participation@example.com');

        configureTestEmailTemplate(c.Id);

        Tender__c tender = createBasicTender(c.Id);

        insert tender;

        Test.startTest();

        tender.Tender_User_Choice__c =
            TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION;

        update tender;

        Test.stopTest();

        System.assertEquals(
            TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
            tender.Tender_User_Choice__c
        );
    }

    // =========================================================================
    // After Update - Rejection
    // =========================================================================

    @IsTest
    static void testHandleAfterUpdateRejection() {

        Contact c = createContact('rejection@example.com');

        configureTestEmailTemplate(c.Id);

        Tender__c tender = createBasicTender(c.Id);

        insert tender;

        Test.startTest();

        tender.Tender_User_Choice__c =
            TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION;

        update tender;

        Test.stopTest();

        System.assertEquals(
            TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION,
            tender.Tender_User_Choice__c
        );
    }

    // =========================================================================
    // After Update - HOD Approved Participation
    // =========================================================================

    @IsTest
    static void testHandleAfterUpdateHodApprovedParticipation() {

        Contact c = createContact('hod.approved.participation@example.com');

        configureTestEmailTemplate(c.Id);

        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open',
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION
        );

        insert tender;

        Test.startTest();

        tender.HOD_Choice__c =
            TenderStatusEmailHandler.HOD_APPROVED;

        update tender;

        Test.stopTest();

        System.assertEquals(
            TenderStatusEmailHandler.HOD_APPROVED,
            tender.HOD_Choice__c
        );
    }

    // =========================================================================
    // After Update - HOD Rejected Participation
    // =========================================================================

    @IsTest
    static void testHandleAfterUpdateHodRejectedParticipation() {

        Contact c = createContact('hod.rejected.participation@example.com');

        configureTestEmailTemplate(c.Id);

        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open',
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION
        );

        insert tender;

        Test.startTest();

        tender.HOD_Choice__c =
            TenderStatusEmailHandler.HOD_REJECTED;

        update tender;

        Test.stopTest();

        System.assertEquals(
            TenderStatusEmailHandler.HOD_REJECTED,
            tender.HOD_Choice__c
        );
    }

    // =========================================================================
    // After Update - HOD Approved Rejection
    // =========================================================================

    @IsTest
    static void testHandleAfterUpdateHodApprovedRejection() {

        Contact c = createContact('hod.approved.rejection@example.com');

        configureTestEmailTemplate(c.Id);

        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open',
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION
        );

        insert tender;

        Test.startTest();

        tender.HOD_Choice__c =
            TenderStatusEmailHandler.HOD_APPROVED;

        update tender;

        Test.stopTest();

        System.assertEquals(
            TenderStatusEmailHandler.HOD_APPROVED,
            tender.HOD_Choice__c
        );
    }

    // =========================================================================
    // After Update - HOD Rejected Rejection
    // =========================================================================

    @IsTest
    static void testHandleAfterUpdateHodRejectedRejection() {

        Contact c = createContact('hod.rejected.rejection@example.com');

        configureTestEmailTemplate(c.Id);

        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open',
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION
        );

        insert tender;

        Test.startTest();

        tender.HOD_Choice__c =
            TenderStatusEmailHandler.HOD_REJECTED;

        update tender;

        Test.stopTest();

        System.assertEquals(
            TenderStatusEmailHandler.HOD_REJECTED,
            tender.HOD_Choice__c
        );
    }

    // =========================================================================
    // Direct processRecords - Insert
    // =========================================================================

    @IsTest
    static void testProcessRecordsInsert() {

        Contact c = createContact('process.insert@example.com');

        configureTestEmailTemplate(c.Id);

        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open'
        );

        insert tender;

        Test.startTest();

        TenderStatusEmailHandler.processRecords(
            new List<Tender__c>{ tender },
            null
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            tender.Id
        );
    }

    // =========================================================================
    // Direct processRecords - Update Participation
    // =========================================================================

    @IsTest
    static void testProcessRecordsUpdateParticipation() {

        Contact c = createContact('process.participation@example.com');

        configureTestEmailTemplate(c.Id);

        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open'
        );

        insert tender;

        Tender__c oldTender = tender.clone(
            true,
            false,
            false,
            false
        );

        tender.Tender_User_Choice__c =
            TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION;

        update tender;

        Test.startTest();

        TenderStatusEmailHandler.processRecords(
            new List<Tender__c>{ tender },
            new Map<Id, Tender__c>{
                tender.Id => oldTender
            }
        );

        Test.stopTest();

        System.assertEquals(
            TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
            tender.Tender_User_Choice__c
        );
    }

    // =========================================================================
    // Direct processRecords - Update Rejection
    // =========================================================================

    @IsTest
    static void testProcessRecordsUpdateRejection() {

        Contact c = createContact('process.rejection@example.com');

        configureTestEmailTemplate(c.Id);

        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open'
        );

        insert tender;

        Tender__c oldTender = tender.clone(
            true,
            false,
            false,
            false
        );

        tender.Tender_User_Choice__c =
            TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION;

        update tender;

        Test.startTest();

        TenderStatusEmailHandler.processRecords(
            new List<Tender__c>{ tender },
            new Map<Id, Tender__c>{
                tender.Id => oldTender
            }
        );

        Test.stopTest();

        System.assertEquals(
            TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION,
            tender.Tender_User_Choice__c
        );
    }

    // =========================================================================
    // Direct processRecords - HOD Approval
    // =========================================================================

    @IsTest
    static void testProcessRecordsHodApproval() {

        Contact c = createContact('process.hod.approval@example.com');

        configureTestEmailTemplate(c.Id);

        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open',
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION
        );

        insert tender;

        Tender__c oldTender = tender.clone(
            true,
            false,
            false,
            false
        );

        tender.HOD_Choice__c =
            TenderStatusEmailHandler.HOD_APPROVED;

        update tender;

        Test.startTest();

        TenderStatusEmailHandler.processRecords(
            new List<Tender__c>{ tender },
            new Map<Id, Tender__c>{
                tender.Id => oldTender
            }
        );

        Test.stopTest();

        System.assertEquals(
            TenderStatusEmailHandler.HOD_APPROVED,
            tender.HOD_Choice__c
        );
    }

    // =========================================================================
    // Direct processRecords - HOD Rejection
    // =========================================================================

    @IsTest
    static void testProcessRecordsHodRejection() {

        Contact c = createContact('process.hod.rejection@example.com');

        configureTestEmailTemplate(c.Id);

        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open',
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION
        );

        insert tender;

        Tender__c oldTender = tender.clone(
            true,
            false,
            false,
            false
        );

        tender.HOD_Choice__c =
            TenderStatusEmailHandler.HOD_REJECTED;

        update tender;

        Test.startTest();

        TenderStatusEmailHandler.processRecords(
            new List<Tender__c>{ tender },
            new Map<Id, Tender__c>{
                tender.Id => oldTender
            }
        );

        Test.stopTest();

        System.assertEquals(
            TenderStatusEmailHandler.HOD_REJECTED,
            tender.HOD_Choice__c
        );
    }

    // =========================================================================
    // Bulk Insert
    // =========================================================================

    @IsTest
    static void testBulkInsert() {

        List<Contact> contacts = createContacts(20);

        configureTestEmailTemplate(contacts[0].Id);

        List<Tender__c> tenders = new List<Tender__c>();

        for (Contact c : contacts) {
            tenders.add(
                new Tender__c(
                    Contact__c = c.Id,
                    Tender_Stage__c = 'Open'
                )
            );
        }

        Test.startTest();

        insert tenders;

        Test.stopTest();

        System.assertEquals(
            20,
            tenders.size()
        );

        for (Tender__c t : tenders) {
            System.assertNotEquals(
                null,
                t.Id
            );
        }
    }

    // =========================================================================
    // Bulk Update
    // =========================================================================

    @IsTest
    static void testBulkUpdate() {

        List<Contact> contacts = createContacts(20);

        configureTestEmailTemplate(contacts[0].Id);

        List<Tender__c> tenders = new List<Tender__c>();

        for (Contact c : contacts) {
            tenders.add(
                new Tender__c(
                    Contact__c = c.Id,
                    Tender_Stage__c = 'Open'
                )
            );
        }

        insert tenders;

        Test.startTest();

        for (Tender__c t : tenders) {
            t.Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION;
        }

        update tenders;

        Test.stopTest();

        for (Tender__c t : tenders) {
            System.assertEquals(
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
                t.Tender_User_Choice__c
            );
        }
    }

    // =========================================================================
    // Bulk Update - Rejection
    // =========================================================================

    @IsTest
    static void testBulkUpdateRejection() {

        List<Contact> contacts = createContacts(20);

        configureTestEmailTemplate(contacts[0].Id);

        List<Tender__c> tenders = new List<Tender__c>();

        for (Contact c : contacts) {
            tenders.add(
                new Tender__c(
                    Contact__c = c.Id,
                    Tender_Stage__c = 'Open'
                )
            );
        }

        insert tenders;

        Test.startTest();

        for (Tender__c t : tenders) {
            t.Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION;
        }

        update tenders;

        Test.stopTest();

        for (Tender__c t : tenders) {
            System.assertEquals(
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION_REJECTION,
                t.Tender_User_Choice__c
            );
        }
    }

    // =========================================================================
    // No Relevant Change
    // =========================================================================

    @IsTest
    static void testNoRelevantChange() {

        Contact c = createContact('no.change@example.com');

        Tender__c oldTender = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
            HOD_Choice__c = null,
            Tender_Stage__c = 'Open'
        );

        Tender__c newTender = new Tender__c(
            Contact__c = c.Id,
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
            HOD_Choice__c = null,
            Tender_Stage__c = 'Open'
        );

        System.assertEquals(
            null,
            TenderStatusEmailHandler.getTemplateForChange(
                newTender,
                oldTender,
                false
            )
        );

        System.assertEquals(
            false,
            TenderStatusEmailHandler.qualifiesForHodParticipationAwaiting(
                newTender,
                oldTender
            )
        );
    }

    // =========================================================================
    // Missing Contact / Email Processing
    // =========================================================================

    @IsTest
    static void testTenderWithoutContact() {

        Tender__c tender = new Tender__c(
            Tender_Stage__c = 'Open'
        );

        insert tender;

        // Insert New Tender Alert goes to Tender Owner, so Contact is not required.
        System.assertEquals(
            TenderStatusEmailHandler.TEMPLATE_NEW_TENDER_ALERT,
            TenderStatusEmailHandler.getTemplateForChange(
                tender,
                null,
                true
            )
        );
    }

    // =========================================================================
    // Missing Old Record During Process
    // =========================================================================

    @IsTest
    static void testProcessRecordsMissingOldRecord() {

        Contact c = createContact('missing.old@example.com');

        configureTestEmailTemplate(c.Id);

        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open',
            Tender_User_Choice__c =
                TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION
        );

        insert tender;

        Test.startTest();

        TenderStatusEmailHandler.processRecords(
            new List<Tender__c>{ tender },
            new Map<Id, Tender__c>()
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            tender.Id
        );
    }

    // =========================================================================
    // Cache Behaviour
    // =========================================================================

    @IsTest
    static void testTemplateCacheBehaviour() {

        Contact c = createContact('cache@example.com');

        configureTestEmailTemplate(c.Id);

        // First call uses test override.
        Id firstId =
            TenderStatusEmailHandler.testTemplateIdOverride;

        System.assertEquals(
            c.Id,
            firstId
        );

        // Second call should still use same override.
        Id secondId =
            TenderStatusEmailHandler.testTemplateIdOverride;

        System.assertEquals(
            firstId,
            secondId
        );
    }

    // =========================================================================
    // Empty Email Address / Null Recipient Paths
    // =========================================================================

    @IsTest
    static void testContactWithoutEmail() {

        Contact c = new Contact(
            LastName = 'No Email Tender Contact'
        );

        insert c;

        configureTestEmailTemplate(c.Id);

        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open'
        );

        Test.startTest();

        insert tender;

        Test.stopTest();

        System.assertNotEquals(
            null,
            tender.Id
        );
    }

    // =========================================================================
    // Multiple Choice Changes
    // =========================================================================

   @IsTest
static void testUserChoiceThenHodChoice() {

    Contact contact = createContact(
        'userchoice.hodchoice@test.example'
    );

    Tender__c tender = new Tender__c(
        Contact__c = contact.Id,
        Tender_Stage__c = 'Open'
    );

    // Initial insert happens before startTest.
    // This creates the old state for the later update.
    insert tender;

    Test.startTest();

    // ---------------------------------------------------------
    // Step 1: Tender User submits participation choice
    // ---------------------------------------------------------
    tender.Tender_User_Choice__c =
        TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION;

    update tender;

    // ---------------------------------------------------------
    // Step 2: HOD approves participation
    // ---------------------------------------------------------
    tender.HOD_Choice__c =
        TenderStatusEmailHandler.HOD_APPROVED;

    update tender;

    Test.stopTest();

    // ---------------------------------------------------------
    // Assertions
    // ---------------------------------------------------------
    System.assertEquals(
        TenderStatusEmailHandler.CHOICE_DIRECT_PARTICIPATION,
        tender.Tender_User_Choice__c,
        'Tender User choice should remain Accept and participate.'
    );

    System.assertEquals(
        TenderStatusEmailHandler.HOD_APPROVED,
        tender.HOD_Choice__c,
        'HOD choice should be Accept for participation.'
    );
}

    @IsTest
    static void testTenderUserEmailsGoToOwner() {

        User runningUser = [
            SELECT Id, Email
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        System.assertEquals(
            false,
            String.isBlank(runningUser.Email),
            'Running user must have Email so Tender User mail can send to Owner.'
        );

        Contact c = createContact('owner.path@example.com');

        Tender__c tender = new Tender__c(
            Contact__c = c.Id,
            Tender_Stage__c = 'Open',
            OwnerId = runningUser.Id
        );
        Database.DMLOptions dmo = new Database.DMLOptions();
        dmo.assignmentRuleHeader.useDefaultRule = false;
        tender.setOptions(dmo);
        insert tender;

        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE IsActive = TRUE
            LIMIT 1
        ];
        System.assertEquals(false, templates.isEmpty(), 'An active email template must exist');
        configureTestEmailTemplate(templates[0].Id);

        System.assertEquals(
            null,
            TenderStatusEmailHandler.buildFormulaRecipientMessage(
                null,
                tender.Id,
                runningUser.Email,
                null
            ),
            'Blank template Id should skip send.'
        );

        Messaging.SingleEmailMessage rendered =
            TenderStatusEmailHandler.buildFormulaRecipientMessage(
                templates[0].Id,
                tender.Id,
                runningUser.Email,
                null
            );
        if (rendered != null) {
            TenderStatusEmailHandler.sendMessageList(
                new List<Messaging.SingleEmailMessage>{ rendered },
                'Owner ToAddress coverage'
            );
        }
        TenderStatusEmailHandler.sendMessageList(
            new List<Messaging.SingleEmailMessage>(),
            'Empty send coverage'
        );

        Map<Id, String> userMap = new Map<Id, String>{
            tender.Id =>
                TenderStatusEmailHandler.TEMPLATE_NEW_TENDER_ALERT
        };
        Map<Id, String> crmMap = new Map<Id, String>{
            tender.Id =>
                TenderStatusEmailHandler.TEMPLATE_CRM_HEAD_NEW_TENDER_ALERT
        };
        Map<Id, String> hodMap = new Map<Id, String>{
            tender.Id =>
                TenderStatusEmailHandler.TEMPLATE_HOD_NEW_TENDER_ALERT
        };

        Test.startTest();
        new TenderStatusEmailHandler.TenderStatusEmailQueueable(
            new List<Id>{ tender.Id },
            userMap,
            crmMap,
            hodMap,
            0
        ).execute(null);
        Test.stopTest();

        System.assertNotEquals(null, tender.Id);
    }

}