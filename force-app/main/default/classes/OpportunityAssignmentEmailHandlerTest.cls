/**
 * @description Test class for OpportunityAssignmentEmailHandler.
 *              Covers helpers, Project-only filtering, and insert/update paths.
 *              All SOQL uses WITH SYSTEM_MODE; DML uses "as system".
 */
@IsTest
private class OpportunityAssignmentEmailHandlerTest {

    private static Id queryProjectRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Opportunity'
            AND DeveloperName = :OpportunityAssignmentEmailHandler.PROJECT_RECORD_TYPE_DEVELOPER_NAME
            AND IsActive = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    private static Id queryAnyNonProjectRecordTypeId(Id projectRtId) {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Opportunity'
            AND IsActive = TRUE
            AND Id != :projectRtId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    private static Id queryAnyTemplateId() {
        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE IsActive = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Id;
    }

    @IsTest
    static void testL1BidderQualification() {
        Opportunity newOpp = new Opportunity(
            StageName = OpportunityAssignmentEmailHandler.STAGE_L1_BIDDER_DECLARED
        );
        Opportunity oldOpp = new Opportunity(StageName = 'Prospecting');

        System.assertEquals(
            true,
            OpportunityAssignmentEmailHandler.qualifiesAsL1BidderDeclared(newOpp, oldOpp)
        );
        System.assertEquals(
            false,
            OpportunityAssignmentEmailHandler.qualifiesAsL1BidderDeclared(newOpp, newOpp)
        );
        System.assertEquals(
            false,
            OpportunityAssignmentEmailHandler.qualifiesAsL1BidderDeclared(null, oldOpp)
        );
    }

    @IsTest
    static void testIsProjectOpportunity() {
        Id projectRtId = queryProjectRecordTypeId();
        System.assertNotEquals(
            null,
            projectRtId,
            'Project_Opportunity record type must exist in this org'
        );

        Opportunity projectOpp = new Opportunity(RecordTypeId = projectRtId);
        Opportunity otherOpp = new Opportunity();

        System.assertEquals(
            true,
            OpportunityAssignmentEmailHandler.isProjectOpportunity(projectOpp)
        );
        System.assertEquals(
            false,
            OpportunityAssignmentEmailHandler.isProjectOpportunity(otherOpp)
        );
        System.assertEquals(
            false,
            OpportunityAssignmentEmailHandler.isProjectOpportunity(null)
        );
    }

    @IsTest
    static void testProjectRecordTypeFilter() {
        Id projectRtId = queryProjectRecordTypeId();
        System.assertNotEquals(
            null,
            projectRtId,
            'Project_Opportunity record type must exist in this org'
        );

        Opportunity projectOpp = new Opportunity(RecordTypeId = projectRtId);
        Opportunity otherOpp = new Opportunity();

        List<Opportunity> filtered = OpportunityAssignmentEmailHandler.filterProjectOpportunities(
            new List<Opportunity>{ projectOpp, otherOpp }
        );

        System.assertEquals(1, filtered.size());
        System.assertEquals(projectRtId, filtered[0].RecordTypeId);
    }

    @IsTest
    static void testFilterProjectOpportunitiesEmptyInput() {
        System.assertEquals(
            0,
            OpportunityAssignmentEmailHandler.filterProjectOpportunities(
                new List<Opportunity>()
            ).size()
        );
    }

    @IsTest
    static void testGetTemplateForChangeNullOwner() {
        Opportunity noOwner = new Opportunity();
        System.assertEquals(
            null,
            OpportunityAssignmentEmailHandler.getTemplateForChange(noOwner, null, true)
        );
    }

    @IsTest
    static void testGetTemplateForChangePaths() {
        Opportunity insertOpp = new Opportunity(OwnerId = UserInfo.getUserId());
        System.assertEquals(
            OpportunityAssignmentEmailHandler.TEMPLATE_NEW_OPPORTUNITY_ASSIGNED,
            OpportunityAssignmentEmailHandler.getTemplateForChange(insertOpp, null, true)
        );

        List<User> otherUsers = [
            SELECT Id
            FROM User
            WHERE IsActive = TRUE
            AND Id != :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!otherUsers.isEmpty()) {
            Opportunity reassigned = new Opportunity(OwnerId = UserInfo.getUserId());
            Opportunity oldReassigned = new Opportunity(OwnerId = otherUsers[0].Id);
            System.assertEquals(
                OpportunityAssignmentEmailHandler.TEMPLATE_NEW_OPPORTUNITY_ASSIGNED,
                OpportunityAssignmentEmailHandler.getTemplateForChange(
                    reassigned,
                    oldReassigned,
                    false
                )
            );
        }

        Opportunity l1Opp = new Opportunity(
            OwnerId = UserInfo.getUserId(),
            StageName = OpportunityAssignmentEmailHandler.STAGE_L1_BIDDER_DECLARED
        );
        Opportunity oldL1Opp = new Opportunity(
            OwnerId = UserInfo.getUserId(),
            StageName = 'Prospecting'
        );
        System.assertEquals(
            OpportunityAssignmentEmailHandler.TEMPLATE_L1_BIDDER_DECLARED,
            OpportunityAssignmentEmailHandler.getTemplateForChange(l1Opp, oldL1Opp, false)
        );
    }

    @IsTest
    static void testHandleAfterInsertAndUpdate_ProjectOnly() {
        Id templateId = queryAnyTemplateId();
        Id projectRtId = queryProjectRecordTypeId();
        System.assertNotEquals(null, templateId, 'An active email template must exist');
        System.assertNotEquals(
            null,
            projectRtId,
            'Project_Opportunity record type must exist in this org'
        );

        OpportunityAssignmentEmailHandler.testTemplateIdOverride = templateId;

        Account account = new Account(
            Name = 'Opp Assignment Test Account ' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert as system account;

        Opportunity projectOpp = new Opportunity(
            Name = 'Project Opp Email Test ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            OwnerId = UserInfo.getUserId(),
            Department_Name__c = 'HDPE',
            RecordTypeId = projectRtId
        );
        insert as system projectOpp;

        Test.startTest();
        OpportunityAssignmentEmailHandler.handleAfterInsert(
            new List<Opportunity>{ projectOpp }
        );

        Opportunity oldProjectOpp = projectOpp.clone(true, true, true, true);
        projectOpp.StageName = OpportunityAssignmentEmailHandler.STAGE_L1_BIDDER_DECLARED;
        update as system projectOpp;

        OpportunityAssignmentEmailHandler.handleAfterUpdate(
            new List<Opportunity>{ projectOpp },
            new Map<Id, Opportunity>{ projectOpp.Id => oldProjectOpp }
        );
        Test.stopTest();

        projectOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :projectOpp.Id
            WITH SYSTEM_MODE
        ];
        System.assertEquals(
            OpportunityAssignmentEmailHandler.STAGE_L1_BIDDER_DECLARED,
            projectOpp.StageName
        );
    }

    @IsTest
    static void testNonProjectOpportunityIsSkipped() {
        Id templateId = queryAnyTemplateId();
        Id projectRtId = queryProjectRecordTypeId();
        System.assertNotEquals(null, templateId, 'An active email template must exist');
        System.assertNotEquals(
            null,
            projectRtId,
            'Project_Opportunity record type must exist in this org'
        );

        Id otherRtId = queryAnyNonProjectRecordTypeId(projectRtId);
        if (otherRtId == null) {
            return;
        }

        OpportunityAssignmentEmailHandler.testTemplateIdOverride = templateId;

        Account account = new Account(
            Name = 'Non Project Opp Account ' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert as system account;

        Opportunity nonProjectOpp = new Opportunity(
            Name = 'Master/Other Opp ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            OwnerId = UserInfo.getUserId(),
            Department_Name__c = 'HDPE',
            RecordTypeId = otherRtId
        );
        insert as system nonProjectOpp;

        Test.startTest();
        // Insert path — non-Project must be skipped (no exception)
        OpportunityAssignmentEmailHandler.handleAfterInsert(
            new List<Opportunity>{ nonProjectOpp }
        );

        // Update path — in-memory only (avoids sales-process DML error on other RTs)
        Opportunity oldOpp = nonProjectOpp.clone(true, true, true, true);
        nonProjectOpp.StageName = OpportunityAssignmentEmailHandler.STAGE_L1_BIDDER_DECLARED;

        OpportunityAssignmentEmailHandler.handleAfterUpdate(
            new List<Opportunity>{ nonProjectOpp },
            new Map<Id, Opportunity>{ nonProjectOpp.Id => oldOpp }
        );
        Test.stopTest();

        System.assertEquals(
            false,
            OpportunityAssignmentEmailHandler.isProjectOpportunity(nonProjectOpp)
        );
    }

    @IsTest
    static void testCrmAndHodEmailResolution() {
        Opportunity blankDepartment = new Opportunity();
        System.assertEquals(
            null,
            OpportunityAssignmentEmailHandler.resolveCrmHeadEmail(blankDepartment)
        );
        System.assertEquals(
            null,
            OpportunityAssignmentEmailHandler.resolveHodEmail(blankDepartment)
        );

        Opportunity hdpeOpp = new Opportunity(Department_Name__c = 'HDPE');
        String crmEmail = OpportunityAssignmentEmailHandler.resolveCrmHeadEmail(hdpeOpp);
        String hodEmail = OpportunityAssignmentEmailHandler.resolveHodEmail(hdpeOpp);

        if (crmEmail != null) {
            System.assertEquals(true, crmEmail.contains('@'));
        }
        if (hodEmail != null) {
            System.assertEquals(true, hodEmail.contains('@'));
        }
    }
}