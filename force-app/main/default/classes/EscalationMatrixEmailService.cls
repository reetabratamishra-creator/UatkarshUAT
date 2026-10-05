/**
 * @description   Shared Lightning email template render/send helpers for the
 *                Utkarsh Escalation Matrix automations.
 * @author        Anshita Chanda
 * @date          2026-08-10
 */
public without sharing class EscalationMatrixEmailService {
  public enum RecipientGroup {
    OWNER,
    OWNER_AND_CRM,
    HOD_ONLY,
    CRM_HEAD_ONLY,
    HOD_AND_CRM_HEAD,
    ED_SIR
  }

  private static Map<String, Id> templateIdByName;
  private static List<Messaging.SingleEmailMessage> queuedMessages;
  private static List<String> queuedCorrelationKeys;
  private static Set<String> successfulSendKeys;
  private static Id cachedOrgWideEmailAddressId;
  private static Boolean orgWideEmailResolved = false;
  private static Map<Id, String> ownerEmailById = new Map<Id, String>();
  private static Map<String, List<String>> roleEmailsByRoleName = new Map<String, List<String>>();
  private static Map<Id, Opportunity> opportunityRenderById = new Map<Id, Opportunity>();
  private static Map<Id, Lead> leadRenderById = new Map<Id, Lead>();

  @TestVisible
  private static Map<String, Id> testTemplateIdOverrides;

  @TestVisible
  private static Set<String> testRecipientOverrides;

  @TestVisible
  private static LeadManagementEmailService.RenderedEmail testLeadRenderedOverride;

  @TestVisible
  private static DealerOpportunityEmailService.RenderedEmail testOppRenderedOverride;

  @TestVisible
  private static Boolean testSimulateSuccessfulSend = false;

  /**
   * @description Sends a rendered Lead escalation email to the requested recipient group.
   */
  public static Boolean sendLeadEmail(
    Lead leadRecord,
    String templateName,
    RecipientGroup recipientType
  ) {
    if (leadRecord == null || String.isBlank(templateName)) {
      return false;
    }

    LeadManagementEmailService.RenderedEmail rendered = renderLeadTemplate(
      leadRecord,
      templateName
    );
    if (rendered == null) {
      return false;
    }

    Set<String> recipients = resolveLeadRecipients(leadRecord, recipientType);
    return sendRenderedEmail(
      leadRecord.Id,
      rendered,
      recipients,
      buildSendKey(leadRecord.Id, templateName)
    );
  }

  /**
   * @description Sends a rendered Opportunity escalation email to the requested recipient group.
   */
  public static Boolean sendOpportunityEmail(
    Opportunity opportunityRecord,
    String templateName,
    RecipientGroup recipientType
  ) {
    if (opportunityRecord == null || String.isBlank(templateName)) {
      return false;
    }

    DealerOpportunityEmailService.RenderedEmail rendered = renderOpportunityTemplate(
      opportunityRecord,
      templateName
    );
    if (rendered == null) {
      return false;
    }

    Set<String> recipients = resolveOpportunityRecipients(
      opportunityRecord,
      recipientType
    );
    return sendRenderedEmail(
      resolveOpportunityTargetObjectId(opportunityRecord),
      rendered,
      recipients,
      buildSendKey(opportunityRecord.Id, templateName)
    );
  }

  /**
   * @description Sends a task overdue email to the Lead or Opportunity owner.
   */
  public static Boolean sendTaskOverdueOwnerEmail(
    Task taskRecord,
    String templateName,
    Id targetObjectId,
    String ownerEmail
  ) {
    if (taskRecord == null || String.isBlank(templateName) || String.isBlank(ownerEmail)) {
      return false;
    }

    Id templateId = resolveTemplateId(templateName);
    if (templateId == null || targetObjectId == null) {
      return false;
    }

    SObject targetRecord = targetObjectId.getSobjectType() == Lead.SObjectType
      ? (SObject) queryLeadForRender(targetObjectId)
      : (SObject) queryOpportunityForRender(targetObjectId);

    if (targetRecord == null) {
      return false;
    }

    LeadManagementEmailService.RenderedEmail leadRendered;
    DealerOpportunityEmailService.RenderedEmail oppRendered;

    if (targetRecord instanceof Lead) {
      leadRendered = renderLeadTemplate((Lead) targetRecord, templateName);
      if (leadRendered == null) {
        return false;
      }
      return sendRenderedEmail(
        targetObjectId,
        leadRendered,
        new Set<String>{ ownerEmail.trim().toLowerCase() },
        buildSendKey(targetObjectId, templateName)
      );
    }

    oppRendered = renderOpportunityTemplate((Opportunity) targetRecord, templateName);
    if (oppRendered == null) {
      return false;
    }
    return sendRenderedEmail(
      targetObjectId,
      oppRendered,
      new Set<String>{ ownerEmail.trim().toLowerCase() },
      buildSendKey(targetObjectId, templateName)
    );
  }

  /**
   * @description Renders a Task-related Lightning template against the Task Id
   *              so {{{Task.Subject}}} / {{{Task.Owner.Name}}} merge. Recipients
   *              still come from the related Lead or Opportunity.
   */
  public static Boolean sendTaskRelatedEmail(
    Task taskRecord,
    String templateName,
    RecipientGroup recipientType,
    Lead leadRecord,
    Opportunity opportunityRecord
  ) {
    if (taskRecord == null || taskRecord.Id == null || String.isBlank(templateName)) {
      return false;
    }

    if (Test.isRunningTest() && testLeadRenderedOverride != null && leadRecord != null) {
      return sendLeadEmail(leadRecord, templateName, recipientType);
    }
    if (Test.isRunningTest() && testOppRenderedOverride != null && opportunityRecord != null) {
      return sendOpportunityEmail(opportunityRecord, templateName, recipientType);
    }

    Id templateId = resolveTemplateId(templateName);
    if (templateId == null) {
      return false;
    }

    Set<String> recipients = leadRecord != null
      ? resolveLeadRecipients(leadRecord, recipientType)
      : resolveOpportunityRecipients(opportunityRecord, recipientType);
    if (recipients == null || recipients.isEmpty()) {
      return false;
    }

    DealerOpportunityEmailService.RenderedEmail rendered = renderTaskTemplate(
      templateId,
      taskRecord
    );
    if (rendered == null) {
      return false;
    }

    Id correlationRecordId = leadRecord != null
      ? leadRecord.Id
      : (opportunityRecord != null ? opportunityRecord.Id : taskRecord.Id);
    Id targetObjectId = leadRecord != null
      ? leadRecord.Id
      : (opportunityRecord != null
          ? resolveOpportunityTargetObjectId(opportunityRecord)
          : taskRecord.OwnerId);

    return sendRenderedEmail(
      targetObjectId,
      rendered,
      recipients,
      buildSendKey(correlationRecordId, templateName)
    );
  }

  /**
   * @description True when the last flush successfully sent the email for this record/template.
   */
  public static Boolean wasSendSuccessful(Id recordId, String templateName) {
    if (recordId == null || String.isBlank(templateName)) {
      return false;
    }
    if (Test.isRunningTest() && testSimulateSuccessfulSend) {
      return true;
    }
    return successfulSendKeys != null &&
      successfulSendKeys.contains(buildSendKey(recordId, templateName));
  }

  /**
   * @description Partial Opportunity updates; skips approval-locked records.
   */
  public static void updateOpportunitiesAllowPartial(List<Opportunity> opportunitiesToUpdate) {
    if (opportunitiesToUpdate == null || opportunitiesToUpdate.isEmpty()) {
      return;
    }

    List<Opportunity> safeUpdates = new List<Opportunity>();
    for (Opportunity opportunityRecord : opportunitiesToUpdate) {
      if (opportunityRecord == null || opportunityRecord.Id == null) {
        continue;
      }
      if (Approval.isLocked(opportunityRecord.Id)) {
        System.debug(
          LoggingLevel.WARN,
          'Skipped escalation flag update for locked Opportunity ' + opportunityRecord.Id
        );
        continue;
      }
      safeUpdates.add(opportunityRecord);
    }

    if (!safeUpdates.isEmpty()) {
      Database.update(safeUpdates, false);
    }
  }

  public static String getRoleDepartmentName(String department) {
    Map<String, String> departmentMap = new Map<String, String>{
      'Transmission & Telecom Tower' => 'Transmission Tower'
    };
    return departmentMap.containsKey(department) ? departmentMap.get(department) : department;
  }

  public static Set<String> resolveLeadRecipients(
    Lead leadRecord,
    RecipientGroup recipientType
  ) {
    if (
      Test.isRunningTest() &&
      testRecipientOverrides != null &&
      !testRecipientOverrides.isEmpty()
    ) {
      return new Set<String>(testRecipientOverrides);
    }

    Set<String> recipients = new Set<String>();
    String department = getRoleDepartmentName(leadRecord.Department_NameFormula__c);

    if (
      recipientType == RecipientGroup.OWNER ||
      recipientType == RecipientGroup.OWNER_AND_CRM
    ) {
      addOwnerEmail(leadRecord.OwnerId, recipients);
    }

    if (recipientType == RecipientGroup.OWNER_AND_CRM) {
      addCrmHeadEmails(leadRecord.CRM_User_Email_Formula__c, department, recipients);
    }

    if (recipientType == RecipientGroup.HOD_ONLY) {
      addRoleEmails(department + ' HOD', recipients);
    }

    if (recipientType == RecipientGroup.CRM_HEAD_ONLY) {
      addRoleEmails('Utkarsh CRM Head', recipients);
    }

    if (recipientType == RecipientGroup.HOD_AND_CRM_HEAD) {
      addRoleEmails(department + ' HOD', recipients);
      addRoleEmails('Utkarsh CRM Head', recipients);
      addCrmHeadEmails(leadRecord.CRM_User_Email_Formula__c, department, recipients);
    }

    if (recipientType == RecipientGroup.ED_SIR) {
      addRoleEmails('Utkarsh ED', recipients);
    }

    return recipients;
  }

  public static Set<String> resolveOpportunityRecipients(
    Opportunity opportunityRecord,
    RecipientGroup recipientType
  ) {
    if (
      Test.isRunningTest() &&
      testRecipientOverrides != null &&
      !testRecipientOverrides.isEmpty()
    ) {
      return new Set<String>(testRecipientOverrides);
    }

    Set<String> recipients = new Set<String>();
    String department = getRoleDepartmentName(
      String.isNotBlank(opportunityRecord.Department_NameFormula__c)
        ? opportunityRecord.Department_NameFormula__c
        : opportunityRecord.Department_Name__c
    );

    if (
      recipientType == RecipientGroup.OWNER ||
      recipientType == RecipientGroup.OWNER_AND_CRM
    ) {
      addOwnerEmail(opportunityRecord.OwnerId, recipients);
    }

    if (recipientType == RecipientGroup.OWNER_AND_CRM) {
      addCrmHeadEmails(
        opportunityRecord.CRM_User_Email_Formula__c,
        department,
        recipients
      );
    }

    if (recipientType == RecipientGroup.HOD_ONLY) {
      addRoleEmails(department + ' HOD', recipients);
    }

    if (recipientType == RecipientGroup.CRM_HEAD_ONLY) {
      addRoleEmails('Utkarsh CRM Head', recipients);
    }

    if (recipientType == RecipientGroup.HOD_AND_CRM_HEAD) {
      addRoleEmails(department + ' HOD', recipients);
      addRoleEmails('Utkarsh CRM Head', recipients);
      addCrmHeadEmails(
        opportunityRecord.CRM_User_Email_Formula__c,
        department,
        recipients
      );
    }

    if (recipientType == RecipientGroup.ED_SIR) {
      addRoleEmails('Utkarsh ED', recipients);
    }

    return recipients;
  }

  public static Boolean hasNoActivitySince(Datetime anchorDate, Date lastActivityDate) {
    if (anchorDate == null) {
      return false;
    }
    if (lastActivityDate == null) {
      return true;
    }
    return lastActivityDate <= anchorDate.date();
  }

  public static Long hoursSince(Datetime anchorDate) {
    if (anchorDate == null) {
      return 0;
    }
    return (System.now().getTime() - anchorDate.getTime()) / (1000 * 60 * 60);
  }

  public static Long daysSince(Datetime anchorDate) {
    if (anchorDate == null) {
      return 0;
    }
    return anchorDate.date().daysBetween(Date.today());
  }

  public static Long daysSince(Date anchorDate) {
    if (anchorDate == null) {
      return 0;
    }
    return anchorDate.daysBetween(Date.today());
  }

  @TestVisible
  static void setTestTemplateId(String templateName, Id templateId) {
    if (testTemplateIdOverrides == null) {
      testTemplateIdOverrides = new Map<String, Id>();
    }
    testTemplateIdOverrides.put(templateName, templateId);
  }

  @TestVisible
  static void clearTestTemplateIds() {
    clearTestState();
  }

  @TestVisible
  static void clearTestState() {
    testTemplateIdOverrides = null;
    templateIdByName = null;
    testRecipientOverrides = null;
    testLeadRenderedOverride = null;
    testOppRenderedOverride = null;
    testSimulateSuccessfulSend = false;
    queuedMessages = null;
    queuedCorrelationKeys = null;
    successfulSendKeys = null;
    cachedOrgWideEmailAddressId = null;
    orgWideEmailResolved = false;
    ownerEmailById.clear();
    roleEmailsByRoleName.clear();
    opportunityRenderById.clear();
    leadRenderById.clear();
  }

  /**
   * @description Flushes queued emails (one sendEmail invocation per up to 10 messages).
   */
  public static void flushQueuedEmails() {
    if (queuedMessages == null || queuedMessages.isEmpty()) {
      return;
    }

    if (successfulSendKeys == null) {
      successfulSendKeys = new Set<String>();
    }

    if (Test.isRunningTest() && testSimulateSuccessfulSend) {
      if (queuedCorrelationKeys != null) {
        successfulSendKeys.addAll(queuedCorrelationKeys);
      }
      queuedMessages.clear();
      queuedCorrelationKeys = null;
      return;
    }

    List<Messaging.SingleEmailMessage> toSend = new List<Messaging.SingleEmailMessage>(
      queuedMessages
    );
    List<String> keysToSend = queuedCorrelationKeys == null
      ? new List<String>()
      : new List<String>(queuedCorrelationKeys);
    queuedMessages.clear();
    queuedCorrelationKeys = null;

    Integer index = 0;
    while (index < toSend.size()) {
      List<Messaging.SingleEmailMessage> chunk = new List<Messaging.SingleEmailMessage>();
      List<String> keyChunk = new List<String>();
      while (index < toSend.size() && chunk.size() < 10) {
        chunk.add(toSend[index]);
        if (index < keysToSend.size()) {
          keyChunk.add(keysToSend[index]);
        }
        index++;
      }
      try {
        Messaging.SendEmailResult[] results = Messaging.sendEmail(chunk, false);
        for (Integer resultIndex = 0; resultIndex < results.size(); resultIndex++) {
          if (results[resultIndex].isSuccess() && resultIndex < keyChunk.size()) {
            successfulSendKeys.add(keyChunk[resultIndex]);
          }
        }
      } catch (Exception ex) {
        // Org daily Single Email quota exhausted — stop flush without failing the batch.
        if (isEmailLimitExceeded(ex)) {
          return;
        }
        throw ex;
      }
    }
  }

  private static Boolean isEmailLimitExceeded(Exception ex) {
    if (ex == null || String.isBlank(ex.getMessage())) {
      return false;
    }
    String message = ex.getMessage().toUpperCase();
    return message.contains('SINGLE_EMAIL_LIMIT_EXCEEDED') ||
      message.contains('EMAIL LIMIT EXCEEDED');
  }

  private static String buildSendKey(Id recordId, String templateName) {
    return String.valueOf(recordId) + '|' + templateName;
  }

  private static LeadManagementEmailService.RenderedEmail renderLeadTemplate(
    Lead leadRecord,
    String templateName
  ) {
    if (Test.isRunningTest() && testLeadRenderedOverride != null) {
      return testLeadRenderedOverride;
    }

    Id templateId = resolveTemplateId(templateName);
    if (templateId == null) {
      return null;
    }
    return LeadManagementEmailService.renderTemplate(templateId, leadRecord);
  }

  private static DealerOpportunityEmailService.RenderedEmail renderTaskTemplate(
    Id templateId,
    Task taskRecord
  ) {
    if (templateId == null || taskRecord == null || taskRecord.Id == null) {
      return null;
    }

    Id whoId = taskRecord.WhoId != null ? taskRecord.WhoId : taskRecord.OwnerId;
    try {
      Messaging.SingleEmailMessage renderedMessage = Messaging.renderStoredEmailTemplate(
        templateId,
        whoId,
        taskRecord.Id
      );
      DealerOpportunityEmailService.RenderedEmail rendered = new DealerOpportunityEmailService.RenderedEmail();
      rendered.subject = renderedMessage.getSubject();
      rendered.htmlBody = renderedMessage.getHtmlBody();
      rendered.plainTextBody = renderedMessage.getPlainTextBody();
      if (
        String.isBlank(rendered.subject) &&
        String.isBlank(rendered.htmlBody) &&
        String.isBlank(rendered.plainTextBody)
      ) {
        return null;
      }
      return rendered;
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.ERROR,
        'Task template render failed for ' +
          taskRecord.Id +
          ': ' +
          ex.getMessage()
      );
      return null;
    }
  }

  private static DealerOpportunityEmailService.RenderedEmail renderOpportunityTemplate(
    Opportunity opportunityRecord,
    String templateName
  ) {
    if (Test.isRunningTest() && testOppRenderedOverride != null) {
      return testOppRenderedOverride;
    }

    Id templateId = resolveTemplateId(templateName);
    if (templateId == null) {
      return null;
    }

    Opportunity renderRecord = queryOpportunityForRender(opportunityRecord.Id);
    if (renderRecord == null) {
      return null;
    }

    return DealerOpportunityEmailService.renderTemplate(
      templateId,
      renderRecord,
      null
    );
  }

  private static Boolean sendRenderedEmail(
    Id targetObjectId,
    LeadManagementEmailService.RenderedEmail rendered,
    Set<String> recipients,
    String correlationKey
  ) {
    if (rendered == null || recipients == null || recipients.isEmpty()) {
      return false;
    }

    if (Test.isRunningTest() && testSimulateSuccessfulSend) {
      if (successfulSendKeys == null) {
        successfulSendKeys = new Set<String>();
      }
      if (String.isNotBlank(correlationKey)) {
        successfulSendKeys.add(correlationKey);
      }
      return true;
    }

    enqueueMessage(
      buildMessage(
        targetObjectId,
        rendered.subject,
        rendered.htmlBody,
        rendered.plainTextBody,
        new List<String>(recipients)
      ),
      correlationKey
    );
    // Tests expect immediate send; production batches call flushQueuedEmails().
    if (Test.isRunningTest()) {
      flushQueuedEmails();
    }
    return true;
  }

  private static Boolean sendRenderedEmail(
    Id targetObjectId,
    DealerOpportunityEmailService.RenderedEmail rendered,
    Set<String> recipients,
    String correlationKey
  ) {
    if (rendered == null || recipients == null || recipients.isEmpty()) {
      return false;
    }

    if (Test.isRunningTest() && testSimulateSuccessfulSend) {
      if (successfulSendKeys == null) {
        successfulSendKeys = new Set<String>();
      }
      if (String.isNotBlank(correlationKey)) {
        successfulSendKeys.add(correlationKey);
      }
      return true;
    }

    enqueueMessage(
      buildMessage(
        targetObjectId,
        rendered.subject,
        rendered.htmlBody,
        rendered.plainTextBody,
        new List<String>(recipients)
      ),
      correlationKey
    );
    if (Test.isRunningTest()) {
      flushQueuedEmails();
    }
    return true;
  }

  private static void enqueueMessage(
    Messaging.SingleEmailMessage message,
    String correlationKey
  ) {
    if (queuedMessages == null) {
      queuedMessages = new List<Messaging.SingleEmailMessage>();
      queuedCorrelationKeys = new List<String>();
    }
    queuedMessages.add(message);
    queuedCorrelationKeys.add(correlationKey);
  }

  private static Messaging.SingleEmailMessage buildMessage(
    Id targetObjectId,
    String subject,
    String htmlBody,
    String plainTextBody,
    List<String> toAddresses
  ) {
    Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
    message.setToAddresses(toAddresses);
    message.setSubject(subject);
    message.setSaveAsActivity(false);
    message.setTargetObjectId(targetObjectId);
    message.setTreatTargetObjectAsRecipient(false);

    if (String.isNotBlank(htmlBody)) {
      message.setHtmlBody(htmlBody);
    }
    if (String.isNotBlank(plainTextBody)) {
      message.setPlainTextBody(plainTextBody);
    }

    applyOrgWideSender(message);
    return message;
  }

  private static Id resolveTemplateId(String templateName) {
    if (Test.isRunningTest() && testTemplateIdOverrides != null) {
      return testTemplateIdOverrides.get(templateName);
    }

    if (templateIdByName == null) {
      templateIdByName = new Map<String, Id>();
      for (EmailTemplate templateRecord : [
        SELECT Id, Name
        FROM EmailTemplate
        WHERE Folder.Name = 'Utkarsh Escalation Matrix Template'
      ]) {
        templateIdByName.put(templateRecord.Name, templateRecord.Id);
      }
    }

    return templateIdByName.get(templateName);
  }

  private static void addOwnerEmail(Id ownerId, Set<String> recipients) {
    if (ownerId == null) {
      return;
    }

    if (!ownerEmailById.containsKey(ownerId)) {
      List<User> owners = [
        SELECT Email
        FROM User
        WHERE Id = :ownerId AND Email != NULL
        LIMIT 1
      ];
      ownerEmailById.put(
        ownerId,
        owners.isEmpty() ? null : owners[0].Email.trim().toLowerCase()
      );
    }

    String ownerEmail = ownerEmailById.get(ownerId);
    if (String.isNotBlank(ownerEmail)) {
      recipients.add(ownerEmail);
    }
  }

  private static void addCrmHeadEmails(
    String crmFormulaEmail,
    String department,
    Set<String> recipients
  ) {
    if (String.isNotBlank(crmFormulaEmail)) {
      recipients.add(crmFormulaEmail.trim().toLowerCase());
    }
    addRoleEmails(department + ' CRM User', recipients);
  }

  private static void addRoleEmails(String roleName, Set<String> recipients) {
    if (String.isBlank(roleName)) {
      return;
    }

    if (!roleEmailsByRoleName.containsKey(roleName)) {
      List<String> roleEmails = new List<String>();
      for (User userRecord : [
        SELECT Email
        FROM User
        WHERE IsActive = TRUE AND UserRole.Name = :roleName AND Email != NULL
      ]) {
        roleEmails.add(userRecord.Email.trim().toLowerCase());
      }
      roleEmailsByRoleName.put(roleName, roleEmails);
    }

    recipients.addAll(roleEmailsByRoleName.get(roleName));
  }

  private static void applyOrgWideSender(Messaging.SingleEmailMessage message) {
    BWM_Email_Settings__mdt settings = BWM_EmailSettingsService.getSettings();
    if (settings == null || String.isBlank(settings.Central_Sender_Email__c)) {
      return;
    }

    if (!orgWideEmailResolved) {
      List<OrgWideEmailAddress> orgWideAddresses = [
        SELECT Id
        FROM OrgWideEmailAddress
        WHERE Address = :settings.Central_Sender_Email__c.trim()
        LIMIT 1
      ];
      cachedOrgWideEmailAddressId = orgWideAddresses.isEmpty()
        ? null
        : orgWideAddresses[0].Id;
      orgWideEmailResolved = true;
    }

    if (cachedOrgWideEmailAddressId != null) {
      message.setOrgWideEmailAddressId(cachedOrgWideEmailAddressId);
    }
  }

  private static Id resolveOpportunityTargetObjectId(Opportunity opportunityRecord) {
    Opportunity renderRecord = queryOpportunityForRender(opportunityRecord.Id);
    if (renderRecord == null) {
      return opportunityRecord.OwnerId;
    }

    if (renderRecord.ContactId != null) {
      return renderRecord.ContactId;
    }

    return renderRecord.OwnerId;
  }

  private static Lead queryLeadForRender(Id leadId) {
    if (leadRenderById.containsKey(leadId)) {
      return leadRenderById.get(leadId);
    }

    List<Lead> rows = [
      SELECT
        Id,
        Name,
        OwnerId,
        Owner.Name,
        Owner.Email,
        Department_Name__c,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c
      FROM Lead
      WHERE Id = :leadId
      LIMIT 1
    ];
    Lead renderRecord = rows.isEmpty() ? null : rows[0];
    leadRenderById.put(leadId, renderRecord);
    return renderRecord;
  }

  private static Opportunity queryOpportunityForRender(Id opportunityId) {
    if (opportunityRenderById.containsKey(opportunityId)) {
      return opportunityRenderById.get(opportunityId);
    }

    List<Opportunity> rows = [
      SELECT
        Id,
        Name,
        OwnerId,
        Owner.Name,
        Owner.Email,
        ContactId,
        Department_Name__c,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c
      FROM Opportunity
      WHERE Id = :opportunityId
      LIMIT 1
    ];
    Opportunity renderRecord = rows.isEmpty() ? null : rows[0];
    opportunityRenderById.put(opportunityId, renderRecord);
    return renderRecord;
  }
}