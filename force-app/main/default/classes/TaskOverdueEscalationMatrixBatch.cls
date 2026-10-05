/**
 * @description   Task overdue escalation emails for owner, 36h HOD, and 96h CRM HOD.
 * @author        Anshita Chanda
 * @date          2026-08-10
 */
public without sharing class TaskOverdueEscalationMatrixBatch implements Database.Batchable<SObject> {
  private static final String TEMPLATE_OWNER = 'Task Overdue Owner';
  private static final String TEMPLATE_36H = 'Task Overdue 36h HOD';
  private static final String TEMPLATE_96H = 'Task Overdue 96h CRM HOD';

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id, Subject, Status, ActivityDate, WhatId, WhoId, OwnerId
        FROM Task
        WHERE
          Status != 'Completed'
          AND ActivityDate != NULL
          AND ActivityDate < TODAY
          AND (WhatId != NULL OR WhoId != NULL)
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<Task> scope) {
    Set<Id> opportunityIds = new Set<Id>();
    Set<Id> leadIds = new Set<Id>();

    for (Task taskRecord : scope) {
      if (taskRecord.WhatId != null && taskRecord.WhatId.getSobjectType() == Opportunity.SObjectType) {
        opportunityIds.add(taskRecord.WhatId);
      }
      if (taskRecord.WhoId != null && taskRecord.WhoId.getSobjectType() == Lead.SObjectType) {
        leadIds.add(taskRecord.WhoId);
      }
    }

    Map<Id, Opportunity> opportunityById = queryOpportunities(opportunityIds);
    Map<Id, Lead> leadById = queryLeads(leadIds);
    Set<Id> processedOpportunityIds = new Set<Id>();
    Set<Id> processedLeadIds = new Set<Id>();

    for (Task taskRecord : scope) {
      if (
        taskRecord.WhatId != null &&
        opportunityById.containsKey(taskRecord.WhatId) &&
        !processedOpportunityIds.contains(taskRecord.WhatId)
      ) {
        processedOpportunityIds.add(taskRecord.WhatId);
        queueOpportunityEmails(opportunityById.get(taskRecord.WhatId), taskRecord);
      } else if (
        taskRecord.WhoId != null &&
        leadById.containsKey(taskRecord.WhoId) &&
        !processedLeadIds.contains(taskRecord.WhoId)
      ) {
        processedLeadIds.add(taskRecord.WhoId);
        queueLeadEmails(leadById.get(taskRecord.WhoId), taskRecord);
      }
    }

    EscalationMatrixEmailService.flushQueuedEmails();

    List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
    for (Id opportunityId : processedOpportunityIds) {
      Opportunity opportunityRecord = opportunityById.get(opportunityId);
      Opportunity updateRecord = buildOpportunityUpdate(opportunityRecord);
      if (updateRecord != null) {
        opportunitiesToUpdate.add(updateRecord);
      }
    }

    List<Lead> leadsToUpdate = new List<Lead>();
    for (Id leadId : processedLeadIds) {
      Lead leadRecord = leadById.get(leadId);
      Lead updateRecord = buildLeadUpdate(leadRecord);
      if (updateRecord != null) {
        leadsToUpdate.add(updateRecord);
      }
    }

    EscalationMatrixEmailService.updateOpportunitiesAllowPartial(opportunitiesToUpdate);
    if (!leadsToUpdate.isEmpty()) {
      Database.update(leadsToUpdate, false);
    }
  }

  public void finish(Database.BatchableContext context) {
  }

  private static void queueOpportunityEmails(
    Opportunity opportunityRecord,
    Task taskRecord
  ) {
    if (opportunityRecord.FirstOverdueTaskDate__c == null) {
      EscalationMatrixEmailService.sendTaskRelatedEmail(
        taskRecord,
        TEMPLATE_OWNER,
        EscalationMatrixEmailService.RecipientGroup.OWNER,
        null,
        opportunityRecord
      );
    }

    Datetime firstOverdueDate = opportunityRecord.FirstOverdueTaskDate__c != null
      ? opportunityRecord.FirstOverdueTaskDate__c
      : System.now();
    Long hoursSinceFirstOverdue = EscalationMatrixEmailService.hoursSince(firstOverdueDate);

    if (
      opportunityRecord.OppOverdueEsc36Sent__c != true &&
      hoursSinceFirstOverdue >= 36
    ) {
      EscalationMatrixEmailService.sendTaskRelatedEmail(
        taskRecord,
        TEMPLATE_36H,
        EscalationMatrixEmailService.RecipientGroup.HOD_ONLY,
        null,
        opportunityRecord
      );
    }

    if (
      opportunityRecord.OppOverdueEsc96Sent__c != true &&
      hoursSinceFirstOverdue >= 96
    ) {
      EscalationMatrixEmailService.sendTaskRelatedEmail(
        taskRecord,
        TEMPLATE_96H,
        EscalationMatrixEmailService.RecipientGroup.CRM_HEAD_ONLY,
        null,
        opportunityRecord
      );
    }
  }

  private static void queueLeadEmails(Lead leadRecord, Task taskRecord) {
    if (leadRecord.FirstOverdueTaskDate__c == null) {
      EscalationMatrixEmailService.sendTaskRelatedEmail(
        taskRecord,
        TEMPLATE_OWNER,
        EscalationMatrixEmailService.RecipientGroup.OWNER,
        leadRecord,
        null
      );
    }

    Datetime firstOverdueDate = leadRecord.FirstOverdueTaskDate__c != null
      ? leadRecord.FirstOverdueTaskDate__c
      : System.now();
    Long hoursSinceFirstOverdue = EscalationMatrixEmailService.hoursSince(firstOverdueDate);

    if (
      leadRecord.LeadOverdueEsc36Sent__c != true &&
      hoursSinceFirstOverdue >= 36
    ) {
      EscalationMatrixEmailService.sendTaskRelatedEmail(
        taskRecord,
        TEMPLATE_36H,
        EscalationMatrixEmailService.RecipientGroup.HOD_ONLY,
        leadRecord,
        null
      );
    }

    if (
      leadRecord.LeadOverdueEsc96Sent__c != true &&
      hoursSinceFirstOverdue >= 96
    ) {
      EscalationMatrixEmailService.sendTaskRelatedEmail(
        taskRecord,
        TEMPLATE_96H,
        EscalationMatrixEmailService.RecipientGroup.CRM_HEAD_ONLY,
        leadRecord,
        null
      );
    }
  }

  private static Opportunity buildOpportunityUpdate(Opportunity opportunityRecord) {
    Opportunity updateRecord = new Opportunity(Id = opportunityRecord.Id);
    Boolean changed = false;

    // Stamp overdue anchor so 36h/96h ladder can progress even if owner email hit a limit.
    if (opportunityRecord.FirstOverdueTaskDate__c == null) {
      updateRecord.FirstOverdueTaskDate__c = System.now();
      updateRecord.OppOverdueEsc36Sent__c = false;
      updateRecord.OppOverdueEsc96Sent__c = false;
      changed = true;
    }

    Datetime firstOverdueDate = updateRecord.FirstOverdueTaskDate__c != null
      ? updateRecord.FirstOverdueTaskDate__c
      : opportunityRecord.FirstOverdueTaskDate__c;
    Long hoursSinceFirstOverdue = EscalationMatrixEmailService.hoursSince(firstOverdueDate);

    if (
      opportunityRecord.OppOverdueEsc36Sent__c != true &&
      hoursSinceFirstOverdue >= 36 &&
      EscalationMatrixEmailService.wasSendSuccessful(opportunityRecord.Id, TEMPLATE_36H)
    ) {
      updateRecord.OppOverdueEsc36Sent__c = true;
      changed = true;
    }

    if (
      opportunityRecord.OppOverdueEsc96Sent__c != true &&
      hoursSinceFirstOverdue >= 96 &&
      EscalationMatrixEmailService.wasSendSuccessful(opportunityRecord.Id, TEMPLATE_96H)
    ) {
      updateRecord.OppOverdueEsc96Sent__c = true;
      changed = true;
    }

    return changed ? updateRecord : null;
  }

  private static Lead buildLeadUpdate(Lead leadRecord) {
    Lead updateRecord = new Lead(Id = leadRecord.Id);
    Boolean changed = false;

    if (leadRecord.FirstOverdueTaskDate__c == null) {
      updateRecord.FirstOverdueTaskDate__c = System.now();
      updateRecord.LeadOverdueEsc36Sent__c = false;
      updateRecord.LeadOverdueEsc96Sent__c = false;
      changed = true;
    }

    Datetime firstOverdueDate = updateRecord.FirstOverdueTaskDate__c != null
      ? updateRecord.FirstOverdueTaskDate__c
      : leadRecord.FirstOverdueTaskDate__c;
    Long hoursSinceFirstOverdue = EscalationMatrixEmailService.hoursSince(firstOverdueDate);

    if (
      leadRecord.LeadOverdueEsc36Sent__c != true &&
      hoursSinceFirstOverdue >= 36 &&
      EscalationMatrixEmailService.wasSendSuccessful(leadRecord.Id, TEMPLATE_36H)
    ) {
      updateRecord.LeadOverdueEsc36Sent__c = true;
      changed = true;
    }

    if (
      leadRecord.LeadOverdueEsc96Sent__c != true &&
      hoursSinceFirstOverdue >= 96 &&
      EscalationMatrixEmailService.wasSendSuccessful(leadRecord.Id, TEMPLATE_96H)
    ) {
      updateRecord.LeadOverdueEsc96Sent__c = true;
      changed = true;
    }

    return changed ? updateRecord : null;
  }

  private static Map<Id, Opportunity> queryOpportunities(Set<Id> opportunityIds) {
    Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>();
    if (opportunityIds.isEmpty()) {
      return opportunityById;
    }

    for (Opportunity opportunityRecord : [
      SELECT
        Id,
        Name,
        OwnerId,
        Owner.Name,
        Owner.Email,
        Department_Name__c,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c,
        FirstOverdueTaskDate__c,
        OppOverdueEsc36Sent__c,
        OppOverdueEsc96Sent__c
      FROM Opportunity
      WHERE Id IN :opportunityIds
    ]) {
      opportunityById.put(opportunityRecord.Id, opportunityRecord);
    }
    return opportunityById;
  }

  private static Map<Id, Lead> queryLeads(Set<Id> leadIds) {
    Map<Id, Lead> leadById = new Map<Id, Lead>();
    if (leadIds.isEmpty()) {
      return leadById;
    }

    for (Lead leadRecord : [
      SELECT
        Id,
        Name,
        OwnerId,
        Owner.Name,
        Owner.Email,
        Department_Name__c,
        Department_NameFormula__c,
        CRM_User_Email_Formula__c,
        FirstOverdueTaskDate__c,
        LeadOverdueEsc36Sent__c,
        LeadOverdueEsc96Sent__c
      FROM Lead
      WHERE Id IN :leadIds
    ]) {
      leadById.put(leadRecord.Id, leadRecord);
    }
    return leadById;
  }
}