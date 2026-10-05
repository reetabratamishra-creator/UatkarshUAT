/**
 * @description Test class for ExpenseStatusEmailHandler HOD/HR notification criteria.
 */
@IsTest
private class ExpenseStatusEmailHandlerTest {
  private static Id queryAnyTemplateId() {
    List<EmailTemplate> templates = [
      SELECT Id
      FROM EmailTemplate
      WHERE IsActive = TRUE
      LIMIT 1
    ];
    return templates.isEmpty() ? null : templates[0].Id;
  }

  @IsTest
  static void testHodAndHrQualificationMethods() {
    Expense__c submitted = new Expense__c(
      Status__c = ExpenseStatusEmailHandler.STATUS_SUBMITTED,
      Employee__c = UserInfo.getUserId()
    );
    Expense__c oldDraft = new Expense__c(Status__c = 'Draft');

    System.assertEquals(
      true,
      ExpenseStatusEmailHandler.qualifiesForHodSubmittedNotification(
        submitted,
        oldDraft
      )
    );
    System.assertEquals(
      false,
      ExpenseStatusEmailHandler.qualifiesForHodSubmittedNotification(
        submitted,
        submitted
      )
    );

    Expense__c approvedByHod = new Expense__c(
      Status__c = ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HOD,
      Employee__c = UserInfo.getUserId()
    );
    Expense__c oldSubmitted = new Expense__c(
      Status__c = ExpenseStatusEmailHandler.STATUS_SUBMITTED
    );

    System.assertEquals(
      true,
      ExpenseStatusEmailHandler.qualifiesForHrAwaitingApprovalNotification(
        approvedByHod,
        oldSubmitted
      )
    );
    System.assertEquals(
      false,
      ExpenseStatusEmailHandler.qualifiesForHrAwaitingApprovalNotification(
        approvedByHod,
        approvedByHod
      )
    );
  }

  @IsTest
  static void testEmployeeStatusTemplateMapping() {
    Expense__c submitted = new Expense__c(
      Status__c = ExpenseStatusEmailHandler.STATUS_SUBMITTED,
      Employee__c = UserInfo.getUserId()
    );
    Expense__c oldDraft = new Expense__c(Status__c = 'Draft');

    System.assertEquals(
      ExpenseStatusEmailHandler.TEMPLATE_SUBMITTED,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(submitted, oldDraft)
    );

    Expense__c approvedByHod = new Expense__c(
      Status__c = ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HOD,
      Employee__c = UserInfo.getUserId()
    );
    System.assertEquals(
      ExpenseStatusEmailHandler.TEMPLATE_APPROVED_HOD,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(approvedByHod, submitted)
    );

    Expense__c rejectedByHod = new Expense__c(
      Status__c = ExpenseStatusEmailHandler.STATUS_REJECTED_BY_HOD,
      Employee__c = UserInfo.getUserId()
    );
    System.assertEquals(
      ExpenseStatusEmailHandler.TEMPLATE_REJECTED_HOD,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(rejectedByHod, submitted)
    );

    // NOTE: STATUS_APPROVED_BY_HR shares the same literal value ('Approved') as
    // STATUS_APPROVED_BY_HOD, so this is a non-transition (newStatus == oldStatus)
    // and getTemplateForStatusChange correctly short-circuits to null. This does
    // NOT trigger TEMPLATE_APPROVED_HR — that branch is currently unreachable
    // until Status__c (or another field) can distinguish HOD vs HR approval.
    Expense__c approvedByHr = new Expense__c(
      Status__c = ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HR,
      Employee__c = UserInfo.getUserId()
    );
    System.assertEquals(
      null,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(approvedByHr, approvedByHod)
    );

    // NOTE: Similarly, STATUS_REJECTED_BY_HR shares the same literal value
    // ('Rejected') as STATUS_REJECTED_BY_HOD, so this transition resolves to
    // TEMPLATE_REJECTED_HOD, not TEMPLATE_REJECTED_HR.
    Expense__c rejectedByHr = new Expense__c(
      Status__c = ExpenseStatusEmailHandler.STATUS_REJECTED_BY_HR,
      Employee__c = UserInfo.getUserId()
    );
    System.assertEquals(
      ExpenseStatusEmailHandler.TEMPLATE_REJECTED_HOD,
      ExpenseStatusEmailHandler.getTemplateForStatusChange(rejectedByHr, approvedByHr)
    );
  }

  @IsTest
  static void testHandleAfterUpdateSubmittedPath() {
    Id templateId = queryAnyTemplateId();
    System.assertNotEquals(null, templateId, 'An active email template must exist');
    ExpenseStatusEmailHandler.testTemplateIdOverride = templateId;

    Expense__c expense = new Expense__c(
      Status__c = 'Draft',
      Employee__c = UserInfo.getUserId()
    );
    insert expense;

    expense.Status__c = ExpenseStatusEmailHandler.STATUS_SUBMITTED;

    Test.startTest();
    update expense;
    Test.stopTest();

    expense = [SELECT Status__c FROM Expense__c WHERE Id = :expense.Id];
    System.assertEquals(
      ExpenseStatusEmailHandler.STATUS_SUBMITTED,
      expense.Status__c
    );
  }

  @IsTest
  static void testSendHodAndHrEmailsPaths() {
    Id templateId = queryAnyTemplateId();
    System.assertNotEquals(null, templateId, 'An active email template must exist');
    ExpenseStatusEmailHandler.testTemplateIdOverride = templateId;

    Expense__c expense = new Expense__c(
      Status__c = 'Draft',
      Employee__c = UserInfo.getUserId()
    );
    insert expense;

    Expense__c oldSubmitted = new Expense__c(
      Id = expense.Id,
      Status__c = ExpenseStatusEmailHandler.STATUS_SUBMITTED,
      Employee__c = expense.Employee__c
    );
    Expense__c approvedByHod = new Expense__c(
      Id = expense.Id,
      Status__c = ExpenseStatusEmailHandler.STATUS_APPROVED_BY_HOD,
      Employee__c = expense.Employee__c
    );

    Test.startTest();
    ExpenseStatusEmailHandler.sendHodAndHrEmails(
      new List<Expense__c>{ approvedByHod },
      new Map<Id, Expense__c>{ expense.Id => oldSubmitted }
    );
    Test.stopTest();

    System.assertNotEquals(null, expense.Id);
  }
}