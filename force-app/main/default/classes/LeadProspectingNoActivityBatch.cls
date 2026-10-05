/**
 * @description   Prospecting-stage 24h, 48h, 96h, and 168h no-activity escalation emails.
 * @author        Anshita Chanda
 * @date          2026-08-10
 */
public without sharing class LeadProspectingNoActivityBatch implements Database.Batchable<SObject> {
  private static final String TEMPLATE_24H = 'Lead No Activity 24h Owner';
  private static final String TEMPLATE_48H = 'Lead No Activity 48h HOD';
  private static final String TEMPLATE_96H = 'Lead No Activity 96h Sir';
  private static final String TEMPLATE_168H = 'Lead No Activity 168h Sir';

  @TestVisible
  private static Map<Id, Datetime> testLastProspectingActivityOverrides;

  public Database.QueryLocator start(Database.BatchableContext context) {
    Datetime cutoff24 = System.now().addHours(-24);

    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Name,
          OwnerId,
          Owner.Email,
          Status,
          Department_Name__c,
          Department_NameFormula__c,
          Last_Prospecting_Activity__c,
          Prospecting_Escalation_24_Sent__c,
          Prospecting_Escalation_48_Sent__c,
          Prospecting_Escalation_72_Sent__c,
          Prospecting_Escalation_168_Sent__c,
          CRM_User_Email_Formula__c
        FROM Lead
        WHERE
          Status = 'Prospecting'
          AND IsConverted = FALSE
          AND Last_Prospecting_Activity__c != NULL
          AND Last_Prospecting_Activity__c <= :cutoff24
          AND (
            Prospecting_Escalation_24_Sent__c = FALSE
            OR Prospecting_Escalation_48_Sent__c = FALSE
            OR Prospecting_Escalation_72_Sent__c = FALSE
            OR Prospecting_Escalation_168_Sent__c = FALSE
          )
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<Lead> scope) {
    for (Lead leadRecord : scope) {
      Datetime activityAnchor = resolveProspectingActivityAnchor(leadRecord);
      Long hoursSinceActivity = EscalationMatrixEmailService.hoursSince(activityAnchor);

      if (
        !leadRecord.Prospecting_Escalation_24_Sent__c &&
        hoursSinceActivity >= 24
      ) {
        EscalationMatrixEmailService.sendLeadEmail(
          leadRecord,
          TEMPLATE_24H,
          EscalationMatrixEmailService.RecipientGroup.OWNER
        );
      }

      if (
        !leadRecord.Prospecting_Escalation_48_Sent__c &&
        hoursSinceActivity >= 48
      ) {
        EscalationMatrixEmailService.sendLeadEmail(
          leadRecord,
          TEMPLATE_48H,
          EscalationMatrixEmailService.RecipientGroup.HOD_AND_CRM_HEAD
        );
      }

      if (
        !leadRecord.Prospecting_Escalation_72_Sent__c &&
        hoursSinceActivity >= 96
      ) {
        EscalationMatrixEmailService.sendLeadEmail(
          leadRecord,
          TEMPLATE_96H,
          EscalationMatrixEmailService.RecipientGroup.ED_SIR
        );
      }

      if (
        !leadRecord.Prospecting_Escalation_168_Sent__c &&
        hoursSinceActivity >= 168
      ) {
        EscalationMatrixEmailService.sendLeadEmail(
          leadRecord,
          TEMPLATE_168H,
          EscalationMatrixEmailService.RecipientGroup.ED_SIR
        );
      }
    }

    EscalationMatrixEmailService.flushQueuedEmails();

    List<Lead> leadsToUpdate = new List<Lead>();
    for (Lead leadRecord : scope) {
      Datetime activityAnchor = resolveProspectingActivityAnchor(leadRecord);
      Long hoursSinceActivity = EscalationMatrixEmailService.hoursSince(activityAnchor);

      Lead updateRecord = new Lead(Id = leadRecord.Id);
      Boolean changed = false;

      if (
        !leadRecord.Prospecting_Escalation_24_Sent__c &&
        hoursSinceActivity >= 24 &&
        EscalationMatrixEmailService.wasSendSuccessful(leadRecord.Id, TEMPLATE_24H)
      ) {
        updateRecord.Prospecting_Escalation_24_Sent__c = true;
        changed = true;
      }

      if (
        !leadRecord.Prospecting_Escalation_48_Sent__c &&
        hoursSinceActivity >= 48 &&
        EscalationMatrixEmailService.wasSendSuccessful(leadRecord.Id, TEMPLATE_48H)
      ) {
        updateRecord.Prospecting_Escalation_48_Sent__c = true;
        changed = true;
      }

      if (
        !leadRecord.Prospecting_Escalation_72_Sent__c &&
        hoursSinceActivity >= 96 &&
        EscalationMatrixEmailService.wasSendSuccessful(leadRecord.Id, TEMPLATE_96H)
      ) {
        updateRecord.Prospecting_Escalation_72_Sent__c = true;
        changed = true;
      }

      if (
        !leadRecord.Prospecting_Escalation_168_Sent__c &&
        hoursSinceActivity >= 168 &&
        EscalationMatrixEmailService.wasSendSuccessful(leadRecord.Id, TEMPLATE_168H)
      ) {
        updateRecord.Prospecting_Escalation_168_Sent__c = true;
        changed = true;
      }

      if (changed) {
        leadsToUpdate.add(updateRecord);
      }
    }

    if (!leadsToUpdate.isEmpty()) {
      Database.update(leadsToUpdate, false);
    }
  }

  public void finish(Database.BatchableContext context) {
  }

  private static Datetime resolveProspectingActivityAnchor(Lead leadRecord) {
    if (
      Test.isRunningTest() &&
      testLastProspectingActivityOverrides != null &&
      testLastProspectingActivityOverrides.containsKey(leadRecord.Id)
    ) {
      return testLastProspectingActivityOverrides.get(leadRecord.Id);
    }

    return leadRecord.Last_Prospecting_Activity__c;
  }

  @TestVisible
  static void setTestLastProspectingActivity(Id leadId, Datetime activityDate) {
    if (testLastProspectingActivityOverrides == null) {
      testLastProspectingActivityOverrides = new Map<Id, Datetime>();
    }
    testLastProspectingActivityOverrides.put(leadId, activityDate);
  }

  @TestVisible
  static void clearTestLastProspectingActivityOverrides() {
    testLastProspectingActivityOverrides = null;
  }
}