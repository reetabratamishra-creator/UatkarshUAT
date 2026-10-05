/**
 * @description   Negotiation-stage active opportunity no-activity escalation emails.
 * @author        Anshita Chanda
 * @date          2026-08-10
 */
public without sharing class OpportunityNegotiationActiveMatrixBatch implements Database.Batchable<SObject> {
  private static final String TEMPLATE_7D = 'Negotiation Active 7d Owner';
  private static final String TEMPLATE_14D = 'Negotiation Active 14d HOD';
  private static final String TEMPLATE_21D = 'Negotiation Active 21d Sir';

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Name,
          OwnerId,
          Owner.Email,
          StageName,
          CreatedDate,
          Budget_Confirmed__c,
          RecordType.DeveloperName,
          Department_Name__c,
          Department_NameFormula__c,
          CRM_User_Email_Formula__c,
          EscalationNeg7Sent__c,
          EscalationNeg14Sent__c,
          EscalationNeg21Sent__c
        FROM Opportunity
        WHERE
          StageName = 'Negotiation'
          AND IsClosed = FALSE
          AND RecordType.DeveloperName != 'Tender_Opportunity'
          AND Budget_Confirmed__c = FALSE
          AND (
            EscalationNeg7Sent__c = FALSE
            OR EscalationNeg14Sent__c = FALSE
            OR EscalationNeg21Sent__c = FALSE
          )
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<Opportunity> scope) {
    Map<Id, Date> lastActivityByOpportunityId = EscalationMatrixOpportunityHelper.getLastActivityDates(
      new Map<Id, Opportunity>(scope).keySet()
    );
    List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();

    for (Opportunity opportunityRecord : scope) {
      Date lastActivityDate = lastActivityByOpportunityId.get(opportunityRecord.Id);
      Long daysSinceActivity = EscalationMatrixEmailService.daysSince(lastActivityDate);

      Opportunity updateRecord = new Opportunity(Id = opportunityRecord.Id);
      Boolean changed = false;

      if (
        !opportunityRecord.EscalationNeg7Sent__c &&
        daysSinceActivity >= 7 &&
        EscalationMatrixEmailService.sendOpportunityEmail(
          opportunityRecord,
          TEMPLATE_7D,
          EscalationMatrixEmailService.RecipientGroup.OWNER_AND_CRM
        )
      ) {
        updateRecord.EscalationNeg7Sent__c = true;
        changed = true;
      }

      if (
        !opportunityRecord.EscalationNeg14Sent__c &&
        daysSinceActivity >= 14 &&
        EscalationMatrixEmailService.sendOpportunityEmail(
          opportunityRecord,
          TEMPLATE_14D,
          EscalationMatrixEmailService.RecipientGroup.HOD_AND_CRM_HEAD
        )
      ) {
        updateRecord.EscalationNeg14Sent__c = true;
        changed = true;
      }

      if (
        !opportunityRecord.EscalationNeg21Sent__c &&
        daysSinceActivity >= 21 &&
        EscalationMatrixEmailService.sendOpportunityEmail(
          opportunityRecord,
          TEMPLATE_21D,
          EscalationMatrixEmailService.RecipientGroup.ED_SIR
        )
      ) {
        updateRecord.EscalationNeg21Sent__c = true;
        changed = true;
      }

      if (changed) {
        opportunitiesToUpdate.add(updateRecord);
      }
    }

    EscalationMatrixEmailService.flushQueuedEmails();
    EscalationMatrixEmailService.updateOpportunitiesAllowPartial(
      confirmOpportunityUpdates(opportunitiesToUpdate)
    );
  }

  private static List<Opportunity> confirmOpportunityUpdates(
    List<Opportunity> candidates
  ) {
    List<Opportunity> confirmed = new List<Opportunity>();
    if (candidates == null || candidates.isEmpty()) {
      return confirmed;
    }
    for (Opportunity candidate : candidates) {
      if (candidate == null || candidate.Id == null) {
        continue;
      }
      Opportunity filtered = new Opportunity(Id = candidate.Id);
      Boolean changed = false;
      if (candidate.EscalationNeg7Sent__c == true &&
        EscalationMatrixEmailService.wasSendSuccessful(candidate.Id, TEMPLATE_7D)) {
        filtered.EscalationNeg7Sent__c = true;
        changed = true;
      }
      if (candidate.EscalationNeg14Sent__c == true &&
        EscalationMatrixEmailService.wasSendSuccessful(candidate.Id, TEMPLATE_14D)) {
        filtered.EscalationNeg14Sent__c = true;
        changed = true;
      }
      if (candidate.EscalationNeg21Sent__c == true &&
        EscalationMatrixEmailService.wasSendSuccessful(candidate.Id, TEMPLATE_21D)) {
        filtered.EscalationNeg21Sent__c = true;
        changed = true;
      }
      if (changed) {
        confirmed.add(filtered);
      }
    }
    return confirmed;
  }


  public void finish(Database.BatchableContext context) {
  }
}