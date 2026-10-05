/**
 * @description Aura entry points for Send WhatsApp Campaign (direct WhatsApp channel).
 */
public with sharing class BWM_WaCampCtrlA {
    @AuraEnabled
    public static LeadManagementWhatsAppService.SendWhatsAppResult sendLeadWhatsApp(
        List<Id> leadIds,
        String templateName
    ) {
        return BWM_WaCampSendA.sendToLeads(leadIds, templateName);
    }

    @AuraEnabled
    public static DealerOpportunityWhatsAppService.SendWhatsAppResult sendOpportunityWhatsApp(
        List<Id> opportunityIds,
        String templateName
    ) {
        return BWM_WaCampSendA.sendToOpportunities(opportunityIds, templateName);
    }

    @AuraEnabled
    public static LeadManagementWhatsAppService.SendWhatsAppResult sendAccountWhatsApp(
        List<Id> accountIds,
        String templateName
    ) {
        return BWM_WaCampSendA.sendToRecords(
            BWM_CampaignRecordSupport.queryAccountsByIds(accountIds),
            templateName,
            BWM_MessagingConstants.TRIGGER_ACCOUNT_CAMPAIGN
        );
    }

    @AuraEnabled
    public static LeadManagementWhatsAppService.SendWhatsAppResult sendContactWhatsApp(
        List<Id> contactIds,
        String templateName
    ) {
        return BWM_WaCampSendA.sendToRecords(
            BWM_CampaignRecordSupport.queryContactsByIds(contactIds),
            templateName,
            BWM_MessagingConstants.TRIGGER_CONTACT_CAMPAIGN
        );
    }

    @AuraEnabled
    public static LeadManagementWhatsAppService.SendWhatsAppResult sendOfflineCampaignWhatsApp(
        List<Id> offlineCampaignIds,
        String templateName
    ) {
        return BWM_WaCampSendA.sendToRecords(
            BWM_CampaignRecordSupport.queryOfflineCampaignsByIds(offlineCampaignIds),
            templateName,
            BWM_MessagingConstants.TRIGGER_OFFLINE_CAMPAIGN
        );
    }
}