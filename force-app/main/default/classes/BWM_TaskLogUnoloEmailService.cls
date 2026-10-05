/**
 * @description   Sends Client Visit Confirmation email to Task Log related Accounts
 *                with brochure attachment. Independent of Unolo WhatsApp/journey send.
 * @author        Anshita Chanda
 * @date          2026-09-11
 */
public without sharing class BWM_TaskLogUnoloEmailService {
  public static final String TRIGGER_POINT = 'Email_Task_Log_Unolo_Client_Visit';
  public static final String TEMPLATE_NAME = 'Client_Visit_Confirmation';
  public static final String EMAIL_SUBJECT = 'Client Visit Confirmation';

  private static final String BODY_TEMPLATE =
    '<html><body style="font-family: Arial, Helvetica, sans-serif; font-size: 14px; color: #1a1a1a; line-height: 1.6;">' +
    '<p>🤝 Sealing a Partnership Built to Last</p>' +
    '<p><strong>Dear Valued Customer</strong>,</p>' +
    '<p>It was a pleasure meeting you today. Every great partnership begins with a handshake — and we\'re honored that ours begins with {DEPARTMENT}.</p>' +
    '<p>For over 40 years, Utkarsh India has stood as a trusted name in India\'s infrastructure journey, backed by ISO 9001:2015 quality standards.</p>' +
    '<p>📎 Please find attached our {DEPARTMENT} Brochure for your reference.</p>' +
    '<p>🛠 For any assistance:<br/>{OWNER_NAME}<br/>📞 {OWNER_PHONE}<br/>📧 {OWNER_EMAIL}</p>' +
    '<p>Looking forward to building something lasting, together.</p>' +
    '<p>Warm regards,<br/>Team Utkarsh India<br/><em>Life Demands, We Deliver</em></p>' +
    '</body></html>';

  /**
   * @description Sends Client Visit Confirmation emails for Task Log Ids. Does not depend
   *              on WhatsApp/journey success or messaging settings.
   * @param taskLogIds Task Log record Ids eligible for Unolo client visit.
   */
  public static void sendForTaskLogIds(List<Id> taskLogIds) {
    if (taskLogIds == null || taskLogIds.isEmpty()) {
      return;
    }

    Map<Id, Task_Log__c> taskLogById = new Map<Id, Task_Log__c>(
      [
        SELECT
          Id,
          Account__c,
          OwnerId,
          Owner.Name,
          Owner.Phone,
          Owner.Email
        FROM Task_Log__c
        WHERE Id IN :taskLogIds
      ]
    );
    if (taskLogById.isEmpty()) {
      return;
    }

    Set<Id> accountIds = new Set<Id>();
    for (Task_Log__c taskLogRecord : taskLogById.values()) {
      if (taskLogRecord.Account__c != null) {
        accountIds.add(taskLogRecord.Account__c);
      }
    }
    if (accountIds.isEmpty()) {
      return;
    }

    Map<Id, Account> accountById = new Map<Id, Account>(
      [
        SELECT Id, Name, Email__c, Department_Name__c
        FROM Account
        WHERE Id IN :accountIds
      ]
    );

    BWM_Email_Settings__mdt emailSettings = BWM_EmailSettingsService.getSettings();
    List<Email_Log__c> logsToInsert = new List<Email_Log__c>();

    for (Id taskLogId : taskLogIds) {
      Task_Log__c taskLogRecord = taskLogById.get(taskLogId);
      if (taskLogRecord == null || taskLogRecord.Account__c == null) {
        continue;
      }

      Account accountRecord = accountById.get(taskLogRecord.Account__c);
      if (accountRecord == null || String.isBlank(accountRecord.Email__c)) {
        continue;
      }

      try {
        SendResult sendResult = sendClientVisitEmail(
          emailSettings,
          taskLogRecord,
          accountRecord
        );
        logsToInsert.add(
          buildEmailLog(
            taskLogRecord,
            accountRecord.Email__c.trim(),
            emailSettings,
            sendResult
          )
        );
      } catch (Exception ex) {
        System.debug(
          LoggingLevel.ERROR,
          'Unolo client visit email failed for Task Log ' +
            taskLogId +
            ': ' +
            ex.getMessage()
        );
      }
    }

    if (!logsToInsert.isEmpty()) {
      insert logsToInsert;
    }
  }

  @TestVisible
  private static SendResult sendClientVisitEmail(
    BWM_Email_Settings__mdt emailSettings,
    Task_Log__c taskLogRecord,
    Account accountRecord
  ) {
    SendResult sendResult = new SendResult();
    String departmentName = displayValue(accountRecord.Department_Name__c);
    String htmlBody = BODY_TEMPLATE
      .replace('{DEPARTMENT}', escapeHtml(departmentName))
      .replace('{OWNER_NAME}', escapeHtml(displayValue(taskLogRecord.Owner.Name)))
      .replace('{OWNER_PHONE}', escapeHtml(displayValue(taskLogRecord.Owner.Phone)))
      .replace('{OWNER_EMAIL}', escapeHtml(displayValue(taskLogRecord.Owner.Email)));

    Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
    message.setUseSignature(false);
    message.setSaveAsActivity(false);
    message.setToAddresses(new List<String>{ accountRecord.Email__c.trim() });
    message.setSubject(EMAIL_SUBJECT);
    message.setHtmlBody(htmlBody);
    message.setPlainTextBody(stripHtml(htmlBody));

    Id orgWideEmailId = resolveOrgWideEmailAddressId(
      emailSettings == null ? null : emailSettings.Central_Sender_Email__c
    );
    if (orgWideEmailId != null) {
      message.setOrgWideEmailAddressId(orgWideEmailId);
    }

    List<Messaging.EmailFileAttachment> attachments = buildBrochureAttachments(
      emailSettings,
      accountRecord
    );
    if (!attachments.isEmpty()) {
      message.setFileAttachments(attachments);
    }

    Messaging.SendEmailResult[] results = Messaging.sendEmail(
      new List<Messaging.SingleEmailMessage>{ message }
    );
    if (!results.isEmpty() && results[0].isSuccess()) {
      sendResult.success = true;
      sendResult.message = 'Sent via Salesforce Email.';
      return sendResult;
    }

    if (!results.isEmpty() && !results[0].getErrors().isEmpty()) {
      sendResult.message = results[0].getErrors()[0].getMessage();
    } else {
      sendResult.message = 'Salesforce email send failed.';
    }
    return sendResult;
  }

  @TestVisible
  private static List<Messaging.EmailFileAttachment> buildBrochureAttachments(
    BWM_Email_Settings__mdt emailSettings,
    Account accountRecord
  ) {
    List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();

    Messaging.EmailFileAttachment departmentAttachment = buildDepartmentBrochureAttachment(
      accountRecord
    );
    if (departmentAttachment != null) {
      attachments.add(departmentAttachment);
      return attachments;
    }

    BWM_Email_Template_Mapping__mdt corporateMapping = new BWM_Email_Template_Mapping__mdt(
      Brochure_Attachment_Mode__c = BWM_EmailConstants.BROCHURE_ATTACH_CORPORATE
    );
    return BWM_EmailBrochureAttachmentService.buildAttachments(
      emailSettings,
      corporateMapping,
      accountRecord
    );
  }

  private static Messaging.EmailFileAttachment buildDepartmentBrochureAttachment(
    Account accountRecord
  ) {
    if (accountRecord == null || String.isBlank(accountRecord.Department_Name__c)) {
      return null;
    }

    List<BWM_Email_Department_Brochure__mdt> brochureRows = [
      SELECT
        Static_Resource_Name__c,
        File_Name__c,
        Content_File_Title__c,
        Public_Download_Url__c
      FROM BWM_Email_Department_Brochure__mdt
      WHERE Department_Name__c = :accountRecord.Department_Name__c.trim()
      LIMIT 1
    ];
    if (brochureRows.isEmpty()) {
      return null;
    }

    BWM_Email_Department_Brochure__mdt brochureRow = brochureRows[0];
    String fileName = String.isBlank(brochureRow.File_Name__c)
      ? accountRecord.Department_Name__c.trim() + '_Brochure.pdf'
      : brochureRow.File_Name__c;

    if (String.isNotBlank(brochureRow.Content_File_Title__c)) {
      Messaging.EmailFileAttachment fileAttachment = BWM_BrochureFileService.buildEmailAttachment(
        brochureRow.Content_File_Title__c,
        fileName
      );
      if (fileAttachment != null) {
        return fileAttachment;
      }
    }

    if (String.isNotBlank(brochureRow.Public_Download_Url__c)) {
      Messaging.EmailFileAttachment urlAttachment = BWM_BrochureFileService.buildEmailAttachmentFromPublicUrl(
        brochureRow.Public_Download_Url__c,
        fileName
      );
      if (urlAttachment != null) {
        return urlAttachment;
      }
    }

    return null;
  }

  private static Email_Log__c buildEmailLog(
    Task_Log__c taskLogRecord,
    String toEmail,
    BWM_Email_Settings__mdt emailSettings,
    SendResult sendResult
  ) {
    Email_Log__c logRecord = new Email_Log__c();
    logRecord.Related_Record_Id__c = String.valueOf(taskLogRecord.Id);
    logRecord.Trigger_Point__c = TRIGGER_POINT;
    logRecord.Template_Name__c = TEMPLATE_NAME;
    logRecord.To_Email__c = toEmail;
    logRecord.From_Email__c = emailSettings == null
      ? null
      : emailSettings.Central_Sender_Email__c;
    logRecord.Status__c = sendResult != null && sendResult.success
      ? BWM_EmailConstants.LOG_STATUS_SENT
      : 'Failed';
    logRecord.Response_Message__c = sendResult == null ? null : sendResult.message;
    return logRecord;
  }

  private static Id resolveOrgWideEmailAddressId(String senderEmail) {
    if (String.isBlank(senderEmail)) {
      return null;
    }
    List<OrgWideEmailAddress> addresses = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE Address = :senderEmail.trim()
      LIMIT 1
    ];
    return addresses.isEmpty() ? null : addresses[0].Id;
  }

  private static String displayValue(String rawValue) {
    return String.isBlank(rawValue) ? 'NA' : rawValue.trim();
  }

  private static String escapeHtml(String rawValue) {
    if (rawValue == null) {
      return '';
    }
    return rawValue
      .replace('&', '&amp;')
      .replace('<', '&lt;')
      .replace('>', '&gt;')
      .replace('"', '&quot;');
  }

  private static String stripHtml(String htmlBody) {
    if (String.isBlank(htmlBody)) {
      return '';
    }
    return htmlBody
      .replaceAll('(?i)<br\\s*/?>', '\n')
      .replaceAll('<[^>]+>', ' ')
      .replaceAll('\\s+', ' ')
      .trim();
  }

  @TestVisible
  private class SendResult {
    public Boolean success = false;
    public String message;
  }
}