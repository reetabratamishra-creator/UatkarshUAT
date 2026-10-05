public with sharing class OfflineCampaignManagementController {
  @AuraEnabled
  public static List<Offline_Campaign__c> searchOfflineCampaigns(
    String searchTerm,
    String phoneFilter,
    String emailFilter,
    String departmentFilter
  ) {
    String namePattern = String.isNotBlank(searchTerm)
      ? '%' + searchTerm.trim() + '%'
      : null;
    String phonePattern = String.isNotBlank(phoneFilter)
      ? '%' + phoneFilter.trim() + '%'
      : null;
    String emailPattern = String.isNotBlank(emailFilter)
      ? '%' + emailFilter.trim() + '%'
      : null;
    String departmentPattern = String.isNotBlank(departmentFilter)
      ? '%' + departmentFilter.trim() + '%'
      : null;

    String soql =
      'SELECT Id, Name, Phone__c, Email__c, Department__c, Active__c, CreatedDate FROM Offline_Campaign__c WHERE Active__c = true';
    if (namePattern != null) {
      soql += ' AND Name LIKE :namePattern';
    }
    if (phonePattern != null) {
      soql += ' AND Phone__c LIKE :phonePattern';
    }
    if (emailPattern != null) {
      soql += ' AND Email__c LIKE :emailPattern';
    }
    if (departmentPattern != null) {
      soql += ' AND Department__c LIKE :departmentPattern';
    }
    soql += ' ORDER BY CreatedDate DESC LIMIT 5000';
    return Database.query(soql);
  }

  @AuraEnabled
  public static BWM_CampaignEmailService.SendCampaignEmailResult sendOfflineCampaignEmail(
    List<Id> offlineCampaignIds,
    String infobipTemplateId
  ) {
    try {
      return BWM_CampaignEmailService.sendToOfflineCampaigns(
        offlineCampaignIds,
        infobipTemplateId
      );
    } catch (Exception ex) {
      throw new AuraHandledException(ex.getMessage());
    }
  }

  @AuraEnabled
  public static List<BWM_InfobipEmailTemplateService.TemplateOption> getBluewaveEmailTemplates() {
    try {
      return BWM_InfobipEmailTemplateService.fetchTemplates();
    } catch (Exception ex) {
      throw new AuraHandledException(ex.getMessage());
    }
  }

  @AuraEnabled
  public static List<BWM_JourneyDefinitionService.JourneyOption> getCampaignJourneys() {
    return BWM_JourneyDefinitionService.fetchActiveJourneys();
  }

  @AuraEnabled
  public static BWM_JourneyDefinitionService.SendJourneyResult sendOfflineCampaignJourney(
    List<Id> offlineCampaignIds,
    String journeyName
  ) {
    return BWM_CampaignJourneyService.sendToOfflineCampaigns(
      offlineCampaignIds,
      journeyName
    );
  }

  @AuraEnabled
  public static List<LeadManagementWhatsAppService.WhatsAppTemplateOption> getWhatsAppTemplates() {
    return LeadManagementWhatsAppService.fetchApprovedTemplates();
  }

  @AuraEnabled
  public static LeadManagementWhatsAppService.SendWhatsAppResult sendOfflineCampaignWhatsApp(
    List<Id> offlineCampaignIds,
    String templateName
  ) {
    return OfflineCampaignManagementWhatsAppService.sendToOfflineCampaigns(
      offlineCampaignIds,
      templateName
    );
  }

  @AuraEnabled
  public static List<LeadManagementRcsService.RcsTemplateOption> getRcsTemplates() {
    return LeadManagementRcsService.fetchApprovedTemplates();
  }

  @AuraEnabled
  public static OfflineCampaignManagementRcsService.SendRcsResult sendOfflineCampaignRcs(
    List<Id> offlineCampaignIds,
    String templateName
  ) {
    return OfflineCampaignManagementRcsService.sendToOfflineCampaigns(
      offlineCampaignIds,
      templateName
    );
  }

  @AuraEnabled
  public static List<BWM_SmsTemplateService.SmsTemplateOption> getSmsTemplates() {
    return BWM_SmsTemplateService.fetchApprovedTemplates();
  }

  @AuraEnabled
  public static OfflineCampaignManagementSmsService.SendSmsResult sendOfflineCampaignSms(
    List<Id> offlineCampaignIds,
    String templateName
  ) {
    return OfflineCampaignManagementSmsService.sendToOfflineCampaigns(
      offlineCampaignIds,
      templateName
    );
  }
}