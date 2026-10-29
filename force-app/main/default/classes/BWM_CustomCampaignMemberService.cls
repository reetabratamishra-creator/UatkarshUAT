/**
 * @description Creates Campaign and Custom Campaign Member records after successful
 *              Campaign Management sends.
 */
public without sharing class BWM_CustomCampaignMemberService {
    public static final String MEMBER_TYPE_LEAD = 'LEAD';
    public static final String MEMBER_TYPE_OPPORTUNITY = 'OPPORTUNITY';
    public static final String MEMBER_TYPE_CONTACT = 'CONTACT';
    public static final String MEMBER_TYPE_ACCOUNT = 'ACCOUNT';
    public static final String MEMBER_TYPE_OFFLINE_CAMPAIGN = 'OFFLINE_CAMPAIGN';
    public static final String STATUS_SCHEDULED = 'Scheduled';
    public static final String STATUS_COMPLETED = 'Completed';

    public class CreateCampaignResult {
        @AuraEnabled
        public Id campaignId;
        @AuraEnabled
        public Integer memberCount;
    }

    /**
     * @description Creates a Campaign and one Custom Campaign Member per record id.
     * @param campaignName User-entered campaign name.
     * @param memberType One of the MEMBER_TYPE_* constants.
     * @param recordIds Recipient record ids for the selected object type.
     * @return CreateCampaignResult with campaign id and member count.
     */
    public static CreateCampaignResult createCampaignWithMembers(
        String campaignName,
        String memberType,
        List<Id> recordIds
    ) {
        return createCampaignWithMembers(campaignName, memberType, recordIds, null);
    }

    /**
     * @description Creates a Campaign with the chosen schedule and one Custom Campaign Member per record id.
     *              Status is Scheduled when the schedule is in the future, otherwise Completed.
     * @param campaignName User-entered campaign name.
     * @param memberType One of the MEMBER_TYPE_* constants.
     * @param recordIds Recipient record ids for the selected object type.
     * @param scheduledDateTime UTC timestamp from the schedule screen (yyyy-MM-ddTHH:mm:ssZ), or blank.
     * @return CreateCampaignResult with campaign id and member count.
     */
    public static CreateCampaignResult createCampaignWithMembers(
        String campaignName,
        String memberType,
        List<Id> recordIds,
        String scheduledDateTime
    ) {
        validateInputs(campaignName, memberType, recordIds);
        assertCreateAccess();

        Datetime scheduledAt = parseScheduledDateTime(scheduledDateTime);
        Campaign campaignRecord = new Campaign(
            Name = campaignName.trim(),
            IsActive = true,
            Scheduled_Date_Time__c = scheduledAt,
            Sent_Date_Time__c = scheduledAt == null ? Datetime.now() : null,
            Status = scheduledAt != null && scheduledAt > Datetime.now()
                ? STATUS_SCHEDULED
                : STATUS_COMPLETED
        );
        insert campaignRecord;

        List<Custom_Campaign_Member__c> members = buildMembers(
            campaignRecord.Id,
            memberType,
            recordIds
        );
        insert members;

        CreateCampaignResult result = new CreateCampaignResult();
        result.campaignId = campaignRecord.Id;
        result.memberCount = members.size();
        return result;
    }

    @TestVisible
    private static Datetime parseScheduledDateTime(String scheduledDateTime) {
        if (String.isBlank(scheduledDateTime)) {
            return null;
        }
        String value = scheduledDateTime.trim();
        try {
            return (Datetime) JSON.deserialize('"' + value + '"', Datetime.class);
        } catch (Exception ex) {
            throw new AuraHandledException('Invalid scheduled date and time: ' + value);
        }
    }

    private static void validateInputs(
        String campaignName,
        String memberType,
        List<Id> recordIds
    ) {
        if (String.isBlank(campaignName)) {
            throw new AuraHandledException('Campaign name is required.');
        }
        if (String.isBlank(memberType)) {
            throw new AuraHandledException('Member type is required.');
        }
        if (recordIds == null || recordIds.isEmpty()) {
            throw new AuraHandledException('Select at least one record.');
        }

        Set<String> allowedTypes = new Set<String>{
            MEMBER_TYPE_LEAD,
            MEMBER_TYPE_OPPORTUNITY,
            MEMBER_TYPE_CONTACT,
            MEMBER_TYPE_ACCOUNT,
            MEMBER_TYPE_OFFLINE_CAMPAIGN
        };
        if (!allowedTypes.contains(memberType)) {
            throw new AuraHandledException('Unsupported member type: ' + memberType);
        }
    }

    private static void assertCreateAccess() {
        if (!Schema.sObjectType.Custom_Campaign_Member__c.isCreateable()) {
            throw new AuraHandledException(
                'You do not have permission to create Custom Campaign Member records.'
            );
        }
    }

    private static List<Custom_Campaign_Member__c> buildMembers(
        Id campaignId,
        String memberType,
        List<Id> recordIds
    ) {
        List<Custom_Campaign_Member__c> members = new List<Custom_Campaign_Member__c>();
        for (Id recordId : recordIds) {
            if (recordId == null) {
                continue;
            }
            Custom_Campaign_Member__c member = new Custom_Campaign_Member__c(
                Campaign__c = campaignId
            );
            switch on memberType {
                when 'LEAD' {
                    member.Lead__c = recordId;
                }
                when 'OPPORTUNITY' {
                    member.Opportunity__c = recordId;
                }
                when 'CONTACT' {
                    member.Contact__c = recordId;
                }
                when 'ACCOUNT' {
                    member.Account__c = recordId;
                }
                when 'OFFLINE_CAMPAIGN' {
                    member.Offline_Campaign__c = recordId;
                }
            }
            members.add(member);
        }

        if (members.isEmpty()) {
            throw new AuraHandledException('No valid record ids were provided.');
        }
        return members;
    }
}