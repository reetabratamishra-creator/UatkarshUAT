@IsTest
private class BWM_CustomCampaignMemberServiceTest {
    @IsTest
    static void testCreateCampaignWithLeadMembers() {
        Lead leadRecord = new Lead(
            LastName = 'Campaign Member Test ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Company = 'Test Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Email = 'ccm.lead+' + String.valueOf(Math.abs(Crypto.getRandomInteger())) + '@test.com'
        );
        insert as system leadRecord;

        Test.startTest();
        BWM_CustomCampaignMemberService.CreateCampaignResult result = BWM_CustomCampaignMemberService.createCampaignWithMembers(
            'Lead Outreach',
            BWM_CustomCampaignMemberService.MEMBER_TYPE_LEAD,
            new List<Id>{ leadRecord.Id }
        );
        Test.stopTest();

        System.assertNotEquals(null, result.campaignId, 'Campaign should be created.');
        System.assertEquals(1, result.memberCount, 'One member should be created.');

        Campaign createdCampaign = [
            SELECT Id, Name, Status, IsActive, Scheduled_Date_Time__c, Sent_Date_Time__c
            FROM Campaign
            WHERE Id = :result.campaignId
            WITH SYSTEM_MODE
        ];
        System.assertEquals('Lead Outreach', createdCampaign.Name);
        System.assertEquals(true, createdCampaign.IsActive);
        System.assertEquals('Completed', createdCampaign.Status);
        System.assertEquals(null, createdCampaign.Scheduled_Date_Time__c);
        System.assertNotEquals(null, createdCampaign.Sent_Date_Time__c, 'Immediate send stores the sent time.');

        List<Custom_Campaign_Member__c> members = [
            SELECT Id, Campaign__c, Lead__c
            FROM Custom_Campaign_Member__c
            WHERE Campaign__c = :result.campaignId
            WITH SYSTEM_MODE
        ];
        System.assertEquals(1, members.size());
        System.assertEquals(leadRecord.Id, members[0].Lead__c);
    }

    @IsTest
    static void testCreateCampaignWithMultipleOpportunityMembers() {
        Account accountRecord = new Account(Name = 'CCM Account ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
        insert as system accountRecord;

        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer indexNumber = 0; indexNumber < 2; indexNumber++) {
            opportunities.add(
                new Opportunity(
                    Name = 'CCM Opp  ' + String.valueOf(Math.abs(Crypto.getRandomInteger())) + indexNumber,
                    StageName = 'Prospecting',
                    CloseDate = Date.today().addDays(30),
                    AccountId = accountRecord.Id
                )
            );
        }
        insert as system opportunities;

        Test.startTest();
        BWM_CustomCampaignMemberService.CreateCampaignResult result = BWM_CustomCampaignMemberService.createCampaignWithMembers(
            'Dealer Push',
            BWM_CustomCampaignMemberService.MEMBER_TYPE_OPPORTUNITY,
            new List<Id>{ opportunities[0].Id, opportunities[1].Id }
        );
        Test.stopTest();

        System.assertEquals(2, result.memberCount);
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Custom_Campaign_Member__c
                WHERE Campaign__c = :result.campaignId
                WITH SYSTEM_MODE
            ]
        );
    }

    @IsTest
    static void testBlankCampaignNameThrows() {
        Lead leadRecord = new Lead(
            LastName = 'Invalid Campaign ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Company = 'Test Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert as system leadRecord;

        Boolean threw = false;
        try {
            BWM_CustomCampaignMemberService.createCampaignWithMembers(
                '   ',
                BWM_CustomCampaignMemberService.MEMBER_TYPE_LEAD,
                new List<Id>{ leadRecord.Id }
            );
        } catch (Exception ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Blank campaign name should throw.');
    }

    @IsTest
    static void testInvalidMemberTypeThrows() {
        Lead leadRecord = new Lead(
            LastName = 'Invalid Type ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Company = 'Test Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert as system leadRecord;

        Boolean threw = false;
        try {
            BWM_CustomCampaignMemberService.createCampaignWithMembers(
                'Valid Name',
                'UNKNOWN',
                new List<Id>{ leadRecord.Id }
            );
        } catch (Exception ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Invalid member type should throw.');
    }

    @IsTest
    static void testControllerCreateCampaignWithMembers() {
        Lead leadRecord = new Lead(
            LastName = 'Controller Test ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Company = 'Test Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert as system leadRecord;

        Test.startTest();
        BWM_CustomCampaignMemberService.CreateCampaignResult result = BWM_CustomCampaignMemberCtrl.createCampaignWithMembers(
            'Controller Campaign',
            BWM_CustomCampaignMemberService.MEMBER_TYPE_LEAD,
            new List<Id>{ leadRecord.Id }
        );
        Test.stopTest();

        System.assertEquals(1, result.memberCount);
    }

    @IsTest
    static void testFutureScheduleCreatesScheduledCampaign() {
        Lead leadRecord = new Lead(
            LastName = 'Future Schedule ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Company = 'Test Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert as system leadRecord;
        Datetime futureTime = Datetime.now().addDays(2);
        String scheduledDateTime = futureTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

        Test.startTest();
        BWM_CustomCampaignMemberService.CreateCampaignResult result =
            BWM_CustomCampaignMemberCtrl.createScheduledCampaignWithMembers(
                'Future Campaign',
                BWM_CustomCampaignMemberService.MEMBER_TYPE_LEAD,
                new List<Id>{ leadRecord.Id },
                scheduledDateTime
            );
        Test.stopTest();

        Campaign createdCampaign = [
            SELECT Status, Scheduled_Date_Time__c, Sent_Date_Time__c
            FROM Campaign
            WHERE Id = :result.campaignId
            WITH SYSTEM_MODE
        ];
        System.assertEquals('Scheduled', createdCampaign.Status);
        System.assertEquals(null, createdCampaign.Sent_Date_Time__c, 'Scheduled sends do not use Sent Date and Time.');
        System.assertEquals(
            scheduledDateTime,
            createdCampaign.Scheduled_Date_Time__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
        );
    }

    @IsTest
    static void testPastScheduleCreatesCompletedCampaign() {
        Lead leadRecord = new Lead(
            LastName = 'Past Schedule ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Company = 'Test Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert as system leadRecord;

        Test.startTest();
        BWM_CustomCampaignMemberService.CreateCampaignResult result =
            BWM_CustomCampaignMemberService.createCampaignWithMembers(
                'Past Campaign',
                BWM_CustomCampaignMemberService.MEMBER_TYPE_LEAD,
                new List<Id>{ leadRecord.Id },
                '2026-01-01T05:30:00Z'
            );
        Test.stopTest();

        Campaign createdCampaign = [
            SELECT Status, Scheduled_Date_Time__c
            FROM Campaign
            WHERE Id = :result.campaignId
            WITH SYSTEM_MODE
        ];
        System.assertEquals('Completed', createdCampaign.Status);
        System.assertEquals(
            Datetime.newInstanceGmt(2026, 1, 1, 5, 30, 0),
            createdCampaign.Scheduled_Date_Time__c
        );
    }

    @IsTest
    static void testInvalidScheduleThrows() {
        Lead leadRecord = new Lead(
            LastName = 'Invalid Schedule ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Company = 'Test Co ' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert as system leadRecord;

        Boolean threw = false;
        try {
            BWM_CustomCampaignMemberCtrl.createScheduledCampaignWithMembers(
                'Invalid Schedule Campaign',
                BWM_CustomCampaignMemberService.MEMBER_TYPE_LEAD,
                new List<Id>{ leadRecord.Id },
                'not a date'
            );
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'An invalid schedule should throw.');
    }
}