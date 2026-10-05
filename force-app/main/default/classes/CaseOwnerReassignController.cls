/**
 * Controller for the caseOwnerReassign LWC (Case Quick Action).
 *
 * Escalation rules (Internal_Ticket_Matrix__c.Name = Case.Module__c):
 *   - Owner = L1__c  -> options are L2__c and L3__c of that matrix row
 *   - Owner = L2__c  -> options are L1__c and L3__c of that matrix row
 *   - Owner = L3__c  -> options are every unique L1__c / L2__c across ALL matrix rows
 *   - Owner = anyone else (manual reassign / queue) -> L1, L2, L3 of that matrix row
 *
 * On a successful owner change, every open Task and every current/upcoming Event
 * related to the Case (WhatId) is moved to the new owner as well. Closed Tasks and
 * past Events are left untouched so history stays with whoever did the work.
 *
 * All SOQL uses WITH SYSTEM_MODE and DML uses AccessLevel.SYSTEM_MODE,
 * so this class REQUIRES API version 61.0 or higher.
 */
/*public without sharing class CaseOwnerReassignController {

    @TestVisible private static final String LVL_L1    = 'L1';
    @TestVisible private static final String LVL_L2    = 'L2';
    @TestVisible private static final String LVL_L3    = 'L3';
    @TestVisible private static final String LVL_OTHER = 'OTHER';

    public class OwnerOption implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String level;

        public OwnerOption(Id userId, String userName, String level) {
            this.value = String.valueOf(userId);
            this.level = level;
            this.label = userName;
        }

        public Integer compareTo(Object other) {
            return this.label.compareTo(((OwnerOption) other).label);
        }
    }

    public class ReassignContext {
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String moduleName;
        @AuraEnabled public String currentOwnerId;
        @AuraEnabled public String currentOwnerName;
        @AuraEnabled public String currentLevel;
        @AuraEnabled public List<OwnerOption> options = new List<OwnerOption>();
        @AuraEnabled public String blockReason;
    }

    @AuraEnabled
    public static ReassignContext getReassignContext(Id caseId) {
        try {
            return buildContext(caseId);
        } catch (Exception e) {
            throw auraError('Could not load the escalation options: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String reassignOwner(Id caseId, Id newOwnerId) {
        try {
            // Re-derive the allowed set on the server. Never trust the value posted by the client.
            ReassignContext ctx = buildContext(caseId);

            if (String.isNotBlank(ctx.blockReason)) {
                throw auraError(ctx.blockReason);
            }

            Boolean allowed = false;
            for (OwnerOption opt : ctx.options) {
                if (opt.value == String.valueOf(newOwnerId)) {
                    allowed = true;
                    break;
                }
            }
            if (!allowed) {
                throw auraError('That user is not a valid escalation target for this Case. Reopen the action and pick again.');
            }

            Database.update(new Case(Id = caseId, OwnerId = newOwnerId), AccessLevel.SYSTEM_MODE);
            reassignOpenActivities(caseId, newOwnerId);

            List<User> newOwner = [
                SELECT Id, Name
                FROM User
                WHERE Id = :newOwnerId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return newOwner.isEmpty() ? '' : newOwner[0].Name;

        } catch (AuraHandledException ahe) {
            throw ahe;                       // keep the real message, do not swallow it
        } catch (Exception e) {
            throw auraError('The owner change did not save: ' + e.getMessage());
        }
    }


    @TestVisible
    private static ReassignContext buildContext(Id caseId) {
        ReassignContext ctx = new ReassignContext();

        List<Case> cases = [
            SELECT Id, CaseNumber, Module__c, OwnerId, Owner.Name
            FROM Case
            WHERE Id = :caseId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            ctx.blockReason = 'This Case record no longer exists.';
            return ctx;
        }

        Case cs = cases[0];
        ctx.caseNumber       = cs.CaseNumber;
        ctx.moduleName       = cs.Module__c;
        ctx.currentOwnerId   = cs.OwnerId;
        ctx.currentOwnerName = cs.Owner.Name;
        ctx.currentLevel     = LVL_OTHER;

        if (String.isBlank(cs.Module__c)) {
            ctx.blockReason = 'Set the Module on this Case first. The escalation matrix is resolved from it.';
            return ctx;
        }

        List<Internal_Ticket_Matrix__c> matrixList = [
            SELECT Id, Name,
                   L1__c, L1__r.Name,
                   L2__c, L2__r.Name,
                   L3__c, L3__r.Name
            FROM Internal_Ticket_Matrix__c
            WHERE Name = :cs.Module__c
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        if (matrixList.isEmpty()) {
            ctx.blockReason = 'No Internal Ticket Matrix record matches the module "' + cs.Module__c + '".';
            return ctx;
        }

        Internal_Ticket_Matrix__c mtx = matrixList[0];
        Id ownerId = cs.OwnerId;

        if (ownerId == mtx.L1__c) {
            ctx.currentLevel = LVL_L1;
        } else if (ownerId == mtx.L2__c) {
            ctx.currentLevel = LVL_L2;
        } else if (ownerId == mtx.L3__c) {
            ctx.currentLevel = LVL_L3;
        }

        Map<Id, OwnerOption> optionsByUser = new Map<Id, OwnerOption>();

        if (ctx.currentLevel == LVL_L3) {
            // Owner sits at the top of this module's ladder -> offer every L1 / L2 in the org.
            for (Internal_Ticket_Matrix__c row : [
                SELECT Name, L1__c, L1__r.Name, L2__c, L2__r.Name
                FROM Internal_Ticket_Matrix__c
                WHERE (L1__c != NULL OR L2__c != NULL)
                WITH SYSTEM_MODE
                ORDER BY Name ASC
            ]) {
                addOption(optionsByUser, row.L1__c, row.L1__r?.Name, LVL_L1, ownerId);
                addOption(optionsByUser, row.L2__c, row.L2__r?.Name, LVL_L2, ownerId);
            }
        } else if (ctx.currentLevel == LVL_L1) {
            addOption(optionsByUser, mtx.L2__c, mtx.L2__r?.Name, LVL_L2, ownerId);
            addOption(optionsByUser, mtx.L3__c, mtx.L3__r?.Name, LVL_L3, ownerId);
        } else if (ctx.currentLevel == LVL_L2) {
            addOption(optionsByUser, mtx.L1__c, mtx.L1__r?.Name, LVL_L1, ownerId);
            addOption(optionsByUser, mtx.L3__c, mtx.L3__r?.Name, LVL_L3, ownerId);
        } else {
            // Owner is a queue or a user outside this module's matrix -> offer the whole ladder.
            addOption(optionsByUser, mtx.L1__c, mtx.L1__r?.Name, LVL_L1, ownerId);
            addOption(optionsByUser, mtx.L2__c, mtx.L2__r?.Name, LVL_L2, ownerId);
            addOption(optionsByUser, mtx.L3__c, mtx.L3__r?.Name, LVL_L3, ownerId);
        }

        ctx.options = optionsByUser.values();
        ctx.options.sort();

        if (ctx.options.isEmpty()) {
            ctx.blockReason = 'The Internal Ticket Matrix for "' + cs.Module__c
                + '" has no other escalation user configured.';
        }
        return ctx;
    }


    @TestVisible
    private static void reassignOpenActivities(Id caseId, Id newOwnerId) {
        List<SObject> toUpdate = new List<SObject>();

        for (Task t : [
            SELECT Id
            FROM Task
            WHERE WhatId = :caseId
              AND IsClosed = false
              AND OwnerId != :newOwnerId
            WITH SYSTEM_MODE
        ]) {
            toUpdate.add(new Task(Id = t.Id, OwnerId = newOwnerId));
        }

        DateTime now   = System.now();
        Date     today = Date.today();
        for (Event ev : [
            SELECT Id
            FROM Event
            WHERE WhatId = :caseId
              AND OwnerId != :newOwnerId
              AND (EndDateTime >= :now OR (IsAllDayEvent = true AND ActivityDate >= :today))
            WITH SYSTEM_MODE
        ]) {
            toUpdate.add(new Event(Id = ev.Id, OwnerId = newOwnerId));
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void addOption(Map<Id, OwnerOption> acc, Id userId, String userName, String level, Id currentOwnerId) {
        if (userId == null || userId == currentOwnerId || acc.containsKey(userId)) {
            return;
        }
        acc.put(userId, new OwnerOption(userId, String.isBlank(userName) ? 'Unknown User' : userName, level));
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}*/
/**
 * Controller for the caseOwnerReassign LWC (Case Quick Action).
 *
 * Escalation rules (Internal_Ticket_Matrix__c.Name = Case.Module__c):
 *   - Owner = L1__c  -> options are L2__c and L3__c of that matrix row
 *   - Owner = L2__c  -> options are L1__c and L3__c of that matrix row
 *   - Running user is one of the unique L3__c users across ALL matrix rows
 *        -> options are every unique L1__c / L2__c across ALL matrix rows
 *   - Owner = anyone else (manual reassign / queue) -> L1, L2, L3 of that matrix row
 *
 * On a successful owner change, every open Task and every current/upcoming Event
 * related to the Case (WhatId) is moved to the new owner as well. Closed Tasks and
 * past Events are left untouched so history stays with whoever did the work.
 *
 * All SOQL uses WITH SYSTEM_MODE and DML uses AccessLevel.SYSTEM_MODE,
 * so this class REQUIRES API version 61.0 or higher.
 */
public without sharing class CaseOwnerReassignController {

    @TestVisible private static final String LVL_L1    = 'L1';
    @TestVisible private static final String LVL_L2    = 'L2';
    @TestVisible private static final String LVL_L3    = 'L3';
    @TestVisible private static final String LVL_OTHER = 'OTHER';

    /* ------------------------------------------------------------------ */
    /*  Wrappers                                                          */
    /* ------------------------------------------------------------------ */

    public class OwnerOption implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String level;

        public OwnerOption(Id userId, String userName, String level) {
            this.value = String.valueOf(userId);
            this.level = level;
            this.label = userName;
        }

        public Integer compareTo(Object other) {
            return this.label.compareTo(((OwnerOption) other).label);
        }
    }

    public class ReassignContext {
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String moduleName;
        @AuraEnabled public String currentOwnerId;
        @AuraEnabled public String currentOwnerName;
        @AuraEnabled public String currentLevel;
        @AuraEnabled public List<OwnerOption> options = new List<OwnerOption>();
        /** Non-null means the screen cannot offer a reassignment; show this text instead. */
        @AuraEnabled public String blockReason;
    }

    /* ------------------------------------------------------------------ */
    /*  Entry points                                                      */
    /* ------------------------------------------------------------------ */

    @AuraEnabled
    public static ReassignContext getReassignContext(Id caseId) {
        System.debug('>>> getReassignContext called. caseId=' + caseId);
        try {
            ReassignContext ctx = buildContext(caseId);
            System.debug('>>> getReassignContext SUCCESS. currentLevel=' + ctx.currentLevel
                + ' | blockReason=' + ctx.blockReason
                + ' | optionCount=' + (ctx.options == null ? 0 : ctx.options.size()));
            return ctx;
        } catch (Exception e) {
            System.debug('>>> getReassignContext EXCEPTION: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            throw auraError('Could not load the escalation options: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String reassignOwner(Id caseId, Id newOwnerId) {
        System.debug('>>> reassignOwner called. caseId=' + caseId + ' | newOwnerId=' + newOwnerId);
        try {
            // Re-derive the allowed set on the server. Never trust the value posted by the client.
            ReassignContext ctx = buildContext(caseId);
            System.debug('>>> reassignOwner re-derived context. currentLevel=' + ctx.currentLevel
                + ' | blockReason=' + ctx.blockReason
                + ' | optionCount=' + (ctx.options == null ? 0 : ctx.options.size()));

            if (String.isNotBlank(ctx.blockReason)) {
                System.debug('>>> reassignOwner BLOCKED: ' + ctx.blockReason);
                throw auraError(ctx.blockReason);
            }

            Boolean allowed = false;
            for (OwnerOption opt : ctx.options) {
                System.debug('>>> reassignOwner checking option value=' + opt.value + ' level=' + opt.level + ' label=' + opt.label);
                if (opt.value == String.valueOf(newOwnerId)) {
                    allowed = true;
                    break;
                }
            }
            System.debug('>>> reassignOwner allowed=' + allowed);
            if (!allowed) {
                throw auraError('That user is not a valid escalation target for this Case. Reopen the action and pick again.');
            }

            Database.update(new Case(Id = caseId, OwnerId = newOwnerId), AccessLevel.SYSTEM_MODE);
            System.debug('>>> reassignOwner Case OwnerId updated to ' + newOwnerId);

            reassignOpenActivities(caseId, newOwnerId);

            List<User> newOwner = [
                SELECT Id, Name
                FROM User
                WHERE Id = :newOwnerId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            System.debug('>>> reassignOwner new owner name=' + (newOwner.isEmpty() ? '(not found)' : newOwner[0].Name));
            return newOwner.isEmpty() ? '' : newOwner[0].Name;

        } catch (AuraHandledException ahe) {
            System.debug('>>> reassignOwner AuraHandledException: ' + ahe.getMessage());
            throw ahe;                       // keep the real message, do not swallow it
        } catch (Exception e) {
            System.debug('>>> reassignOwner EXCEPTION: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            throw auraError('The owner change did not save: ' + e.getMessage());
        }
    }

    /* ------------------------------------------------------------------ */
    /*  Core logic                                                        */
    /* ------------------------------------------------------------------ */

    @TestVisible
    private static ReassignContext buildContext(Id caseId) {
        System.debug('>>> buildContext START. caseId=' + caseId);
        ReassignContext ctx = new ReassignContext();

        List<Case> cases = [
            SELECT Id, CaseNumber, Module__c, OwnerId, Owner.Name
            FROM Case
            WHERE Id = :caseId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            System.debug('>>> buildContext: Case not found for id=' + caseId);
            ctx.blockReason = 'This Case record no longer exists.';
            return ctx;
        }

        Case cs = cases[0];
        System.debug('>>> buildContext: Case loaded. CaseNumber=' + cs.CaseNumber
            + ' | Module__c=' + cs.Module__c
            + ' | OwnerId=' + cs.OwnerId
            + ' | OwnerName=' + cs.Owner.Name);

        ctx.caseNumber       = cs.CaseNumber;
        ctx.moduleName       = cs.Module__c;
        ctx.currentOwnerId   = cs.OwnerId;
        ctx.currentOwnerName = cs.Owner.Name;
        ctx.currentLevel     = LVL_OTHER;

        if (String.isBlank(cs.Module__c)) {
            System.debug('>>> buildContext: Module__c is blank, blocking.');
            ctx.blockReason = 'Set the Module on this Case first. The escalation matrix is resolved from it.';
            return ctx;
        }

        // Pull every matrix row once. We need the full set both to find this
        // Case's own module row AND to build the org-wide unique L3 user set.
        List<Internal_Ticket_Matrix__c> allMatrixRows = [
            SELECT Id, Name,
                   L1__c, L1__r.Name,
                   L2__c, L2__r.Name,
                   L3__c, L3__r.Name
            FROM Internal_Ticket_Matrix__c
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ];
        System.debug('>>> buildContext: allMatrixRows count=' + allMatrixRows.size());

        Internal_Ticket_Matrix__c mtx;
        for (Internal_Ticket_Matrix__c row : allMatrixRows) {
            if (row.Name == cs.Module__c) {
                mtx = row;
                break;
            }
        }
        if (mtx == null) {
            System.debug('>>> buildContext: No matrix row matched Module__c=' + cs.Module__c);
            ctx.blockReason = 'No Internal Ticket Matrix record matches the module "' + cs.Module__c + '".';
            return ctx;
        }
        System.debug('>>> buildContext: matched matrix row Name=' + mtx.Name
            + ' | L1=' + mtx.L1__c + ' (' + mtx.L1__r?.Name + ')'
            + ' | L2=' + mtx.L2__c + ' (' + mtx.L2__r?.Name + ')'
            + ' | L3=' + mtx.L3__c + ' (' + mtx.L3__r?.Name + ')');

        // Unique L3 users across ALL matrix rows (org-wide top-of-ladder pool).
        Set<Id> globalL3Ids = new Set<Id>();
        for (Internal_Ticket_Matrix__c row : allMatrixRows) {
            if (row.L3__c != null) {
                globalL3Ids.add(row.L3__c);
            }
        }
        System.debug('>>> buildContext: globalL3Ids=' + globalL3Ids);

        /*
        Id ownerId       = cs.OwnerId;
        Id runningUserId = UserInfo.getUserId();
        System.debug('>>> buildContext: ownerId=' + ownerId + ' | runningUserId=' + runningUserId
            + ' | runningUserIsGlobalL3=' + globalL3Ids.contains(runningUserId));

        
        if (globalL3Ids.contains(runningUserId)) {
            // Running user is an org-wide L3 -> this check wins regardless of who the Case Owner is.
            ctx.currentLevel = LVL_L3;
        } else if (ownerId == mtx.L1__c) {
            ctx.currentLevel = LVL_L1;
        } else if (ownerId == mtx.L2__c) {
            ctx.currentLevel = LVL_L2;
        }
        System.debug('>>> buildContext: resolved currentLevel=' + ctx.currentLevel);
        
        
        

        Map<Id, OwnerOption> optionsByUser = new Map<Id, OwnerOption>();

        if (ctx.currentLevel == LVL_L3) {
            // Running user is an org-wide L3 -> offer every L1 / L2 across all rows.
            System.debug('>>> buildContext: branch=L3, building org-wide L1/L2 options');
            for (Internal_Ticket_Matrix__c row : allMatrixRows) {
                addOption(optionsByUser, row.L1__c, row.L1__r?.Name, LVL_L1, ownerId);
                addOption(optionsByUser, row.L2__c, row.L2__r?.Name, LVL_L2, ownerId);
            }
        } else if (ctx.currentLevel == LVL_L1) {
            System.debug('>>> buildContext: branch=L1, offering L2/L3 of this module');
            addOption(optionsByUser, mtx.L2__c, mtx.L2__r?.Name, LVL_L2, ownerId);
            addOption(optionsByUser, mtx.L3__c, mtx.L3__r?.Name, LVL_L3, ownerId);
        } else if (ctx.currentLevel == LVL_L2) {
            System.debug('>>> buildContext: branch=L2, offering L1/L3 of this module');
            addOption(optionsByUser, mtx.L1__c, mtx.L1__r?.Name, LVL_L1, ownerId);
            addOption(optionsByUser, mtx.L3__c, mtx.L3__r?.Name, LVL_L3, ownerId);
        } else {
            // Owner is a queue or a user outside this module's matrix -> offer the whole ladder.
            System.debug('>>> buildContext: branch=OTHER, offering full ladder of this module');
            addOption(optionsByUser, mtx.L1__c, mtx.L1__r?.Name, LVL_L1, ownerId);
            addOption(optionsByUser, mtx.L2__c, mtx.L2__r?.Name, LVL_L2, ownerId);
            addOption(optionsByUser, mtx.L3__c, mtx.L3__r?.Name, LVL_L3, ownerId);
        }
        */

                Id ownerId       = cs.OwnerId;
        Id runningUserId = UserInfo.getUserId();
        Boolean runningUserIsGlobalL3 = globalL3Ids.contains(runningUserId);
        System.debug('>>> buildContext: ownerId=' + ownerId + ' | runningUserId=' + runningUserId
            + ' | runningUserIsGlobalL3=' + runningUserIsGlobalL3);

        // 1) OWNER কে collect করে দেখা owner আসলে L1/L2/L3 এর কোনটায় আছে -> এটাই "Current owner (Level)" label এ দেখাবে
        if (ownerId == mtx.L1__c) {
            ctx.currentLevel = LVL_L1;
        } else if (ownerId == mtx.L2__c) {
            ctx.currentLevel = LVL_L2;
        } else if (globalL3Ids.contains(ownerId)) {
            ctx.currentLevel = LVL_L3;
        } else {
            ctx.currentLevel = LVL_OTHER;
        }

        // 2) VIEWER (jini login kore ache) er level -> eta dropdown options build korar jonno
        String viewerLevel;
        if (runningUserIsGlobalL3) {
            viewerLevel = LVL_L3;
        } else if (ownerId == mtx.L1__c) {
            viewerLevel = LVL_L1;
        } else if (ownerId == mtx.L2__c) {
            viewerLevel = LVL_L2;
        } else {
            viewerLevel = LVL_OTHER;
        }
        System.debug('>>> buildContext: ownerLevel(currentLevel)=' + ctx.currentLevel + ' | viewerLevel=' + viewerLevel);

        Map<Id, OwnerOption> optionsByUser = new Map<Id, OwnerOption>();

        if (viewerLevel == LVL_L3) {
            System.debug('>>> buildContext: branch=L3, building org-wide L1/L2 options');
            for (Internal_Ticket_Matrix__c row : allMatrixRows) {
                addOption(optionsByUser, row.L1__c, row.L1__r?.Name, LVL_L1, ownerId);
                addOption(optionsByUser, row.L2__c, row.L2__r?.Name, LVL_L2, ownerId);
            }
        } else if (viewerLevel == LVL_L1) {
            System.debug('>>> buildContext: branch=L1, offering L2/L3 of this module');
            addOption(optionsByUser, mtx.L2__c, mtx.L2__r?.Name, LVL_L2, ownerId);
            addOption(optionsByUser, mtx.L3__c, mtx.L3__r?.Name, LVL_L3, ownerId);
        } else if (viewerLevel == LVL_L2) {
            System.debug('>>> buildContext: branch=L2, offering L1/L3 of this module');
            addOption(optionsByUser, mtx.L1__c, mtx.L1__r?.Name, LVL_L1, ownerId);
            addOption(optionsByUser, mtx.L3__c, mtx.L3__r?.Name, LVL_L3, ownerId);
        } else {
            System.debug('>>> buildContext: branch=OTHER, offering full ladder of this module');
            addOption(optionsByUser, mtx.L1__c, mtx.L1__r?.Name, LVL_L1, ownerId);
            addOption(optionsByUser, mtx.L2__c, mtx.L2__r?.Name, LVL_L2, ownerId);
            addOption(optionsByUser, mtx.L3__c, mtx.L3__r?.Name, LVL_L3, ownerId);
        }
        ctx.options = optionsByUser.values();
        ctx.options.sort();
        System.debug('>>> buildContext: final option count=' + ctx.options.size());
        for (OwnerOption opt : ctx.options) {
            System.debug('>>> buildContext: option -> value=' + opt.value + ' level=' + opt.level + ' label=' + opt.label);
        }

        if (ctx.options.isEmpty()) {
            System.debug('>>> buildContext: no options found, blocking.');
            ctx.blockReason = 'The Internal Ticket Matrix for "' + cs.Module__c
                + '" has no other escalation user configured.';
        }
        System.debug('>>> buildContext END. blockReason=' + ctx.blockReason);
        return ctx;
    }

    /**
     * Moves every open Task and every current/upcoming Event on the Case to the new owner.
     * "Upcoming" = the Event has not ended yet (EndDateTime >= now), or it is an all-day
     * Event dated today or later. Closed Tasks and past Events are intentionally skipped.
     */
    @TestVisible
    private static void reassignOpenActivities(Id caseId, Id newOwnerId) {
        System.debug('>>> reassignOpenActivities START. caseId=' + caseId + ' | newOwnerId=' + newOwnerId);
        List<SObject> toUpdate = new List<SObject>();

        List<Task> openTasks = [
            SELECT Id
            FROM Task
            WHERE WhatId = :caseId
              AND IsClosed = false
              AND OwnerId != :newOwnerId
            WITH SYSTEM_MODE
        ];
        System.debug('>>> reassignOpenActivities: open Tasks to reassign=' + openTasks.size());
        for (Task t : openTasks) {
            toUpdate.add(new Task(Id = t.Id, OwnerId = newOwnerId));
        }

        DateTime now   = System.now();
        Date     today = Date.today();
        List<Event> upcomingEvents = [
            SELECT Id
            FROM Event
            WHERE WhatId = :caseId
              AND OwnerId != :newOwnerId
              AND (EndDateTime >= :now OR (IsAllDayEvent = true AND ActivityDate >= :today))
            WITH SYSTEM_MODE
        ];
        System.debug('>>> reassignOpenActivities: upcoming Events to reassign=' + upcomingEvents.size());
        for (Event ev : upcomingEvents) {
            toUpdate.add(new Event(Id = ev.Id, OwnerId = newOwnerId));
        }

        System.debug('>>> reassignOpenActivities: total records to update=' + toUpdate.size());
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, AccessLevel.SYSTEM_MODE);
            System.debug('>>> reassignOpenActivities: update DONE.');
        } else {
            System.debug('>>> reassignOpenActivities: nothing to update.');
        }
    }

    /** Adds a user to the option map, skipping blanks, the current owner and duplicates. */
    private static void addOption(Map<Id, OwnerOption> acc, Id userId, String userName, String level, Id currentOwnerId) {
        if (userId == null || userId == currentOwnerId || acc.containsKey(userId)) {
            System.debug('>>> addOption skipped. userId=' + userId + ' level=' + level
                + ' | isNull=' + (userId == null)
                + ' | isCurrentOwner=' + (userId == currentOwnerId)
                + ' | alreadyAdded=' + acc.containsKey(userId));
            return;
        }
        acc.put(userId, new OwnerOption(userId, String.isBlank(userName) ? 'Unknown User' : userName, level));
        System.debug('>>> addOption added. userId=' + userId + ' level=' + level + ' name=' + userName);
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}