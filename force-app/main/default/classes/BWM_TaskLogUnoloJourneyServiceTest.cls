/**
 * @description   Test class for Unolo Task Log journey trigger and send service.
 * @author        Anshita Chanda
 * @date          2026-08-13
 */
@IsTest
private class BWM_TaskLogUnoloJourneyServiceTest {
  @TestSetup
  static void setupData() {
    Account accountRecord = new Account(
      Name = 'Unolo Test Account ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
      Phone = (String.valueOf(Math.abs(Crypto.getRandomInteger())) + '9123456789').right(10),
      Email__c = 'unolo.client+' +
        String.valueOf(Math.abs(Crypto.getRandomInteger())) +
        '@example.com',
      Department_Name__c = 'Crash Barrier'
    );
    insert as system accountRecord;

    Punch_Record__c punchRecord = new Punch_Record__c(
      Is_WFH_Request__c = false,
      Is_WFO_Request__c = false
    );
    insert as system punchRecord;
  }

  private static Task_Log__c buildTaskLog(Id accountId, Id punchId) {
    return new Task_Log__c(
      Account__c = accountId,
      Punch_Record__c = punchId,
      IsCheckout__c = false,
      is100mOutside__c = false,
      Manually_Created__c = false,
      Is_schedule__c = false,
      isRescheduled__c = false,
      MOM__c = 'Visited client and discussed requirements.',
      Checked_Out_Latitude__c = 22.56945,
      Checked_Out_Longitude__c = 88.34946
    );
  }

  private static Task_Log__c buildTaskLogWithoutUnoloFields(
    Id accountId,
    Id punchId
  ) {
    Task_Log__c taskLogRecord = buildTaskLog(accountId, punchId);
    taskLogRecord.MOM__c = null;
    taskLogRecord.Checked_Out_Latitude__c = null;
    taskLogRecord.Checked_Out_Longitude__c = null;
    return taskLogRecord;
  }

  @IsTest
  static void buildPayloadUsesWhatsAppAndRcsVariables() {
    BWM_TaskLogUnoloTriggerHandler.resetTestState();
    BWM_TaskLogUnoloTriggerHandler.skipForTests = true;

    Account accountRecord = [
      SELECT Id, Phone, Department_Name__c
      FROM Account
      WHERE Name LIKE 'Unolo Test Account%'
      LIMIT 1
    ];
    Task_Log__c taskLogRecord = buildTaskLog(
      accountRecord.Id,
      [SELECT Id FROM Punch_Record__c LIMIT 1].Id
    );
    insert as system taskLogRecord;

    taskLogRecord = [
      SELECT
        Id,
        Account__c,
        Punch_Record__c,
        OwnerId,
        Owner.Name,
        Owner.Phone,
        Owner.Email
      FROM Task_Log__c
      WHERE Id = :taskLogRecord.Id
    ];

    Test.startTest();
    String payload = BWM_TaskLogUnoloJourneyService.buildPayload(
      taskLogRecord,
      accountRecord,
      '917980828320'
    );
    Test.stopTest();

    Map<String, Object> payloadMap = (Map<String, Object>) JSON.deserializeUntyped(
      payload
    );
    Map<String, Object> content = (Map<String, Object>) payloadMap.get('content');
    Map<String, Object> data = (Map<String, Object>) content.get('data');
    Map<String, Object> journeyPayload = (Map<String, Object>) data.get(
      'journeypayload'
    );
    Map<String, Object> nodes = (Map<String, Object>) journeyPayload.get('nodes');
    Map<String, Object> whatsAppNode = (Map<String, Object>) nodes.get('1');
    Map<String, Object> rcsNode = (Map<String, Object>) nodes.get('2');
    Map<String, Object> whatsAppData = (Map<String, Object>) whatsAppNode.get(
      'data'
    );
    Map<String, Object> rcsData = (Map<String, Object>) rcsNode.get('data');
    Map<String, Object> rcsBodyData = (Map<String, Object>) rcsData.get(
      'bodyData'
    );

    System.assertEquals('Journey', payloadMap.get('channel'));
    System.assertEquals(
      BWM_TaskLogUnoloJourneyService.JOURNEY_NAME,
      data.get('journeyname')
    );
    System.assertEquals('917980828320', ((List<Object>) payloadMap.get('to'))[0]);
    System.assertEquals('Crash Barrier', rcsBodyData.get('{{1}}'));
    System.assertEquals('Crash Barrier', rcsBodyData.get('{{2}}'));
    System.assertNotEquals('', rcsBodyData.get('{{3}}'));
    System.assertEquals(
      BWM_TaskLogUnoloJourneyService.WHATSAPP_TEMPLATE_NAME,
      whatsAppData.get('templateName')
    );
  }

  @IsTest
  static void handleAfterInsertEnqueuesForEligibleTaskLogsOnSamePunch() {
    BWM_TaskLogUnoloTriggerHandler.resetTestState();

    Account accountRecord = [
      SELECT Id
      FROM Account
      WHERE Name LIKE 'Unolo Test Account%'
      LIMIT 1
    ];
    Id punchId = [SELECT Id FROM Punch_Record__c LIMIT 1].Id;

    Test.startTest();
    insert as system new List<Task_Log__c>{
      buildTaskLog(accountRecord.Id, punchId),
      buildTaskLog(accountRecord.Id, punchId)
    };
    Test.stopTest();

    System.assertEquals(
      1,
      BWM_TaskLogUnoloTriggerHandler.testEnqueueCount,
      'Eligible Task Logs on the same Punch should enqueue a journey send.'
    );
  }

  @IsTest
  static void handleAfterInsertSkipsWhenRequiredFieldsMissing() {
    BWM_TaskLogUnoloTriggerHandler.resetTestState();

    Account accountRecord = [
      SELECT Id
      FROM Account
      WHERE Name LIKE 'Unolo Test Account%'
      LIMIT 1
    ];
    Id punchId = [SELECT Id FROM Punch_Record__c LIMIT 1].Id;

    Test.startTest();
    insert as system buildTaskLogWithoutUnoloFields(accountRecord.Id, punchId);
    Test.stopTest();

    System.assertEquals(
      0,
      BWM_TaskLogUnoloTriggerHandler.testEnqueueCount,
      'Task Log without MOM and checkout coordinates should not enqueue a journey send.'
    );
  }

  @IsTest
  static void handleAfterUpdateEnqueuesWhenRequiredFieldsBecomePopulated() {
    BWM_TaskLogUnoloTriggerHandler.resetTestState();

    Account accountRecord = [
      SELECT Id
      FROM Account
      WHERE Name LIKE 'Unolo Test Account%'
      LIMIT 1
    ];
    Id punchId = [SELECT Id FROM Punch_Record__c LIMIT 1].Id;

    Task_Log__c taskLogRecord = buildTaskLogWithoutUnoloFields(
      accountRecord.Id,
      punchId
    );
    insert as system taskLogRecord;
    System.assertEquals(0, BWM_TaskLogUnoloTriggerHandler.testEnqueueCount);

    Test.startTest();
    taskLogRecord.MOM__c = 'Visited client and discussed requirements.';
    taskLogRecord.Checked_Out_Latitude__c = 22.56945;
    taskLogRecord.Checked_Out_Longitude__c = 88.34946;
    update as system taskLogRecord;
    Test.stopTest();

    System.assertEquals(
      1,
      BWM_TaskLogUnoloTriggerHandler.testEnqueueCount,
      'Populating MOM and checkout coordinates on update should enqueue the journey send.'
    );
  }

  @IsTest
  static void sendForTaskLogIdsUsesAccountPhone() {
    BWM_TaskLogUnoloTriggerHandler.resetTestState();
    BWM_TaskLogUnoloTriggerHandler.skipForTests = true;

    Test.setMock(
      HttpCalloutMock.class,
      new BWM_MessagingCalloutMock(
        '{"code":"200","message":"Journey request enqueued successfully."}',
        '{"code":"200","message":"unused"}'
      )
    );

    Account accountRecord = [
      SELECT Id, Phone, Department_Name__c
      FROM Account
      WHERE Name LIKE 'Unolo Test Account%'
      LIMIT 1
    ];
    Task_Log__c taskLogRecord = buildTaskLog(
      accountRecord.Id,
      [SELECT Id FROM Punch_Record__c LIMIT 1].Id
    );
    insert as system taskLogRecord;

    Test.startTest();
    BWM_TaskLogUnoloJourneyService.sendForTaskLogIds(
      new List<Id>{ taskLogRecord.Id }
    );
    Test.stopTest();

    List<Message_Log__c> logs = [
      SELECT Status__c, Template_Name__c, Phone_Number__c
      FROM Message_Log__c
      WHERE
        Trigger_Point__c = :BWM_TaskLogUnoloJourneyService.TRIGGER_POINT
        AND Related_Record_Id__c = :taskLogRecord.Id
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals('Sent', logs[0].Status__c);
    System.assertEquals(
      BWM_TaskLogUnoloJourneyService.JOURNEY_NAME,
      logs[0].Template_Name__c
    );
    System.assert(
      String.isNotBlank(logs[0].Phone_Number__c),
      'Message log should store the resolved Account phone.'
    );
    System.assert(
      logs[0].Phone_Number__c.contains(accountRecord.Phone),
      'Message log phone should be derived from the Account phone.'
    );
  }

  @IsTest
  static void selectEligibleTaskLogIdsReturnsAllEligibleRecords() {
    Account accountRecord = [
      SELECT Id
      FROM Account
      WHERE Name LIKE 'Unolo Test Account%'
      LIMIT 1
    ];
    Id punchId = [SELECT Id FROM Punch_Record__c LIMIT 1].Id;

    Task_Log__c firstTaskLog = buildTaskLog(accountRecord.Id, punchId);
    Task_Log__c secondTaskLog = buildTaskLog(accountRecord.Id, punchId);
    secondTaskLog.Manually_Created__c = true;

    BWM_TaskLogUnoloTriggerHandler.skipForTests = true;
    insert as system new List<Task_Log__c>{ firstTaskLog, secondTaskLog };

    List<Id> selectedIds = BWM_TaskLogUnoloTriggerHandler.selectEligibleTaskLogIds(
      new List<Task_Log__c>{ firstTaskLog, secondTaskLog }
    );

    System.assertEquals(2, selectedIds.size());
    System.assert(selectedIds.contains(firstTaskLog.Id));
    System.assert(selectedIds.contains(secondTaskLog.Id));
  }

  @IsTest
  static void triggerEnqueuesJourneyWhenRequiredFieldsPresent() {
    BWM_TaskLogUnoloTriggerHandler.resetTestState();

    Account accountRecord = [
      SELECT Id
      FROM Account
      WHERE Name LIKE 'Unolo Test Account%'
      LIMIT 1
    ];
    Id punchId = [SELECT Id FROM Punch_Record__c LIMIT 1].Id;

    Test.startTest();
    insert as system buildTaskLog(accountRecord.Id, punchId);
    Test.stopTest();

    System.assertEquals(
      1,
      BWM_TaskLogUnoloTriggerHandler.testEnqueueCount,
      'Trigger should enqueue Unolo journey when MOM and checkout coordinates are populated.'
    );
  }

  @IsTest
  static void sendClientVisitEmailIndependentOfJourney() {
    BWM_TaskLogUnoloTriggerHandler.resetTestState();
    BWM_TaskLogUnoloTriggerHandler.skipForTests = true;

    Account accountRecord = [
      SELECT Id, Email__c, Department_Name__c
      FROM Account
      WHERE Name LIKE 'Unolo Test Account%'
      LIMIT 1
    ];
    Task_Log__c taskLogRecord = buildTaskLog(
      accountRecord.Id,
      [SELECT Id FROM Punch_Record__c LIMIT 1].Id
    );
    insert as system taskLogRecord;

    Test.startTest();
    BWM_TaskLogUnoloEmailService.sendForTaskLogIds(
      new List<Id>{ taskLogRecord.Id }
    );
    Test.stopTest();

    List<Email_Log__c> emailLogs = [
      SELECT Status__c, Template_Name__c, To_Email__c, Trigger_Point__c
      FROM Email_Log__c
      WHERE
        Trigger_Point__c = :BWM_TaskLogUnoloEmailService.TRIGGER_POINT
        AND Related_Record_Id__c = :String.valueOf(taskLogRecord.Id)
    ];
    System.assertEquals(1, emailLogs.size());
    System.assertEquals(
      BWM_TaskLogUnoloEmailService.TEMPLATE_NAME,
      emailLogs[0].Template_Name__c
    );
    System.assertEquals(accountRecord.Email__c, emailLogs[0].To_Email__c);
    System.assertEquals(BWM_EmailConstants.LOG_STATUS_SENT, emailLogs[0].Status__c);
  }

  @IsTest
  static void sendClientVisitEmailSkipsWhenAccountEmailMissing() {
    BWM_TaskLogUnoloTriggerHandler.resetTestState();
    BWM_TaskLogUnoloTriggerHandler.skipForTests = true;

    Account accountRecord = [
      SELECT Id, Email__c
      FROM Account
      WHERE Name LIKE 'Unolo Test Account%'
      LIMIT 1
    ];
    accountRecord.Email__c = null;
    update as system accountRecord;

    Task_Log__c taskLogRecord = buildTaskLog(
      accountRecord.Id,
      [SELECT Id FROM Punch_Record__c LIMIT 1].Id
    );
    insert as system taskLogRecord;

    Test.startTest();
    BWM_TaskLogUnoloEmailService.sendForTaskLogIds(
      new List<Id>{ taskLogRecord.Id }
    );
    Test.stopTest();

    Integer emailLogCount = [
      SELECT COUNT()
      FROM Email_Log__c
      WHERE
        Trigger_Point__c = :BWM_TaskLogUnoloEmailService.TRIGGER_POINT
        AND Related_Record_Id__c = :String.valueOf(taskLogRecord.Id)
    ];
    System.assertEquals(0, emailLogCount);
  }

  @IsTest
  static void triggerHandlesHandlerException() {
    BWM_TaskLogUnoloTriggerHandler.resetTestState();
    BWM_TaskLogUnoloTriggerHandler.forceExceptionForTests = true;

    Account accountRecord = [
      SELECT Id
      FROM Account
      WHERE Name LIKE 'Unolo Test Account%'
      LIMIT 1
    ];
    Id punchId = [SELECT Id FROM Punch_Record__c LIMIT 1].Id;

    Test.startTest();
    insert as system buildTaskLog(accountRecord.Id, punchId);
    Test.stopTest();

    System.assertEquals(
      0,
      BWM_TaskLogUnoloTriggerHandler.testEnqueueCount,
      'Trigger should swallow handler exceptions without enqueueing a journey send.'
    );
  }
}