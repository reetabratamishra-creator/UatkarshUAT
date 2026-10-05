public without sharing class CaseResolvedLockHandler {

    private static final String RESOLVED_STATUS = 'Resolved';

    /** Only these profiles may edit a Case once it is Resolved. */
    private static final Set<String> ALLOWED_PROFILES = new Set<String>{
        'System Administrator', 'Utkarsh Admin'
    };

    /**
     * Blocks any edit to a Case whose Status was already 'Resolved' before this save,
     * unless the running user's profile is System Administrator or Utkarsh Admin.
     * Runs in before update so the error is attached before any DML happens -
     * no records are saved, no other trigger logic runs for that record.
     */
    public static void handleBeforeUpdate(List<Case> newCases, Map<Id, Case> oldCasesById) {
        System.debug('--- CaseResolvedLockHandler.handleBeforeUpdate START ---');

        // Print who is actually running this - no SOQL involved, so this
        // always succeeds even if the Profile query below fails.
        System.debug('CaseResolvedLockHandler: Running User Id = ' + UserInfo.getUserId());
        System.debug('CaseResolvedLockHandler: Running Username = ' + UserInfo.getUserName());
        System.debug('CaseResolvedLockHandler: Running Profile Id = ' + UserInfo.getProfileId());

        if (newCases == null || newCases.isEmpty() || oldCasesById == null) {
            System.debug('CaseResolvedLockHandler: newCases or oldCasesById is null/empty, exiting.');
            return;
        }

        String runningProfile = currentUserProfileName();
        System.debug('CaseResolvedLockHandler: Running user profile = "' + runningProfile + '"');

        // Admins are exempt - skip the whole check for them.
        if (ALLOWED_PROFILES.contains(runningProfile)) {
            System.debug('CaseResolvedLockHandler: Profile is in ALLOWED_PROFILES, skipping lock check entirely.');
            return;
        }

        for (Case caseRecord : newCases) {
            Case previous = oldCasesById.get(caseRecord.Id);

            System.debug(
                'CaseResolvedLockHandler: Case Id=' + caseRecord.Id +
                ' | Previous Status="' + (previous != null ? previous.Status : 'NULL') + '"' +
                ' | New Status="' + caseRecord.Status + '"'
            );

            if (previous != null && previous.Status == RESOLVED_STATUS) {
                System.debug('CaseResolvedLockHandler: 🔒 BLOCKING edit on Case Id=' + caseRecord.Id);
                caseRecord.addError('This case is Resolved and can no longer be edited.');
            } else {
                System.debug('CaseResolvedLockHandler: ✅ Case Id=' + caseRecord.Id + ' not previously Resolved, allowing edit.');
            }
        }

        System.debug('--- CaseResolvedLockHandler.handleBeforeUpdate END ---');
    }

    /**
     * UPDATED: queries Profile directly by Id (UserInfo.getProfileId()) instead of
     * traversing User.Profile.Name. The User -> Profile relationship query fails
     * in some running-user contexts (Automated Process user, Guest User, certain
     * integration/system contexts) with "sObject type 'Profile' is not supported"
     * or "No such relation 'Profile' on entity 'User'". Querying Profile directly
     * avoids that relationship entirely and works across those contexts.
     *
     * Wrapped in try/catch so that if this lookup ever fails for an unforeseen
     * reason, it degrades to null rather than throwing and blocking the trigger.
     * A null profileName is not in ALLOWED_PROFILES, so the lock check still
     * applies (fails safe/closed) rather than silently letting the edit through.
     */
    private static String currentUserProfileName() {
        String profileName;
        try {
            profileName = [
                SELECT Name
                FROM Profile
                WHERE Id = :UserInfo.getProfileId() 
                WITH SYSTEM_MODE
            ].Name;
            System.debug('CaseResolvedLockHandler.currentUserProfileName: resolved to "' + profileName + '"');
        } catch (Exception e) {
            System.debug('CaseResolvedLockHandler.currentUserProfileName: query failed - ' + e.getMessage());
        }
        return profileName;
    }
}