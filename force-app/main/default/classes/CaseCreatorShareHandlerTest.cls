@IsTest
private class CaseCreatorShareHandlerTest {
  @IsTest
  static void testNullAndEmptyGuards() {
    CaseCreatorShareHandler.handleAfterInsert(null);
    CaseCreatorShareHandler.handleAfterInsert(new List<Case>());
    CaseCreatorShareHandler.handleAfterUpdate(null, null);
    CaseCreatorShareHandler.handleAfterUpdate(new List<Case>(), new Map<Id, Case>());
  }

  @IsTest
  static void testCreatorShareOnInsertAndOwnerChange() {
    Profile profileRecord = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];

    Long stamp = System.currentTimeMillis();
    User creatorUser = buildUser(profileRecord.Id, 'cshr1' + stamp, 'CreatorShare');
    User ownerUser = buildUser(profileRecord.Id, 'cshr2' + stamp, 'OwnerShare');
    insert new List<User>{ creatorUser, ownerUser };

    Case caseRecord = new Case(
      Subject = 'Share Handler Case',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = ownerUser.Id,
      RecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
        .get('Case')
        .getRecordTypeId()
    );

    System.runAs(creatorUser) {
      insert caseRecord;
    }

    caseRecord = [
      SELECT Id, OwnerId, CreatedById, RecordTypeId
      FROM Case
      WHERE Id = :caseRecord.Id
    ];

    CaseCreatorShareHandler.handleAfterInsert(new List<Case>{ caseRecord });

    User thirdOwner = buildUser(profileRecord.Id, 'cshr3' + stamp, 'ThirdOwner');
    insert thirdOwner;

    Case oldCase = caseRecord.clone(true, true, true, true);
    caseRecord.OwnerId = thirdOwner.Id;
    CaseCreatorShareHandler.handleAfterUpdate(
      new List<Case>{ caseRecord },
      new Map<Id, Case>{ caseRecord.Id => oldCase }
    );

    System.assertEquals(thirdOwner.Id, caseRecord.OwnerId);
  }

  private static User buildUser(Id profileId, String uniqueKey, String lastName) {
    return new User(
      Alias = uniqueKey.left(8),
      Email = uniqueKey + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = lastName,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      TimeZoneSidKey = 'Asia/Kolkata',
      Username = uniqueKey + '@example.com'
    );
  }
}