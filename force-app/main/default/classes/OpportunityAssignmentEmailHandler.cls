/**
 * @description Sends emails to the Opportunity Owner (Employee/Sales User) when
 *              an Opportunity is assigned, or when L1 Bidder is declared.
 * @author Rani Mate
 * @date 2026-08-14
 *
 * ASSUMPTIONS (verify / adjust to match your org):
 *  - Recipient ("Employee") = OwnerId (standard User lookup on Opportunity)
 *  - "New Project Opportunity Assigned" fires:
 *      - on insert (new Opportunity created with an owner), and
 *      - on update, whenever OwnerId changes (re-assignment)
 *  - "L1 Bidder Declared" fires when StageName changes to 'L1 Bidder Declared'.
 *    If L1 Bidder is actually tracked via a custom field
 *    (e.g. L1_Bidder_Declared__c Checkbox, or a different picklist value),
 *    swap the check in getTemplateForChange() accordingly.
 */
public without sharing class OpportunityAssignmentEmailHandler {
    // ===== Stage value for L1 Bidder Declared (adjust if this is a custom field instead) =====
    public static final String STAGE_L1_BIDDER_DECLARED = 'L1 Bidder Declared';
    // ===== Templates (DeveloperName) =====
    public static final String TEMPLATE_NEW_OPPORTUNITY_ASSIGNED =
        'New_Project_Opportunity_Assigned_1786616028589';
    public static final String TEMPLATE_L1_BIDDER_DECLARED =
        'L1_Bidder_Declared_1786616437038';
    public static final String ORG_WIDE_SENDER_EMAIL = 'noreply@utkarshindialimited.in';
    // ===== ADDED: Department CRM Head templates (DeveloperName) =====
    // "Created" fires only on insert (unlike TEMPLATE_NEW_OPPORTUNITY_ASSIGNED,
    // which also covers reassignment for the Owner). L1 Bidder Declared mirrors
    // the same transition as the Owner-facing template, just a second recipient.
    public static final String TEMPLATE_CRM_HEAD_OPPORTUNITY_CREATED =
        'Project_Opportunity_Created_1786620843232';
    public static final String TEMPLATE_CRM_HEAD_L1_BIDDER_DECLARED =
        'L1_Bidder_Declared_Confirmed_Opportunity_1786621328010';
    // ===== ADDED: Department HOD templates (Project record type only) =====
    public static final String TEMPLATE_HOD_PROJECT_CREATED =
        'New_Project_Opportunity_Created_1786620185112';
    public static final String TEMPLATE_HOD_L1_BIDDER_DECLARED =
        'L1_Bidder_Declared_1786620559286';
    public static final String PROJECT_RECORD_TYPE_DEVELOPER_NAME = 'Project_Opportunity';
    private static Id projectRecordTypeId;
    private static Map<String, String> crmEmailByDepartment;
    private static Map<String, String> hodEmailByDepartment;
    @TestVisible
    private static Id testTemplateIdOverride;
    public static void handleAfterInsert(List<Opportunity> newRecords) {
        processRecords(newRecords, null);
    }
    public static void handleAfterUpdate(
        List<Opportunity> newRecords,
        Map<Id, Opportunity> oldRecordsById
    ) {
        processRecords(newRecords, oldRecordsById);
    }
    @TestVisible
    private static void processRecords(
        List<Opportunity> newRecords,
        Map<Id, Opportunity> oldRecordsById
    ) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }
        Boolean isInsert = oldRecordsById == null;
        Map<String, List<Opportunity>> oppsByTemplate = new Map<String, List<Opportunity>>();
        for (Opportunity opp : newRecords) {
            // Only Project Opportunity
            if (!isProjectOpportunity(opp)) {
                continue;
            }
            Opportunity oldOpp = isInsert ? null : oldRecordsById.get(opp.Id);
            String templateName = getTemplateForChange(opp, oldOpp, isInsert);
            if (templateName == null) {
                continue;
            }
            if (!oppsByTemplate.containsKey(templateName)) {
                oppsByTemplate.put(templateName, new List<Opportunity>());
            }
            oppsByTemplate.get(templateName).add(opp);
        }
        List<EmailSendRequest> emailSendRequests = new List<EmailSendRequest>();
        for (String templateName : oppsByTemplate.keySet()) {
            emailSendRequests.add(
                new EmailSendRequest('OWNER', oppsByTemplate.get(templateName), templateName)
            );
        }
        // ADDED: parallel notification to the Department CRM Head.
        // Detected separately (not reused from oppsByTemplate) because
        // "Created" must exclude reassignments, which share
        // TEMPLATE_NEW_OPPORTUNITY_ASSIGNED with inserts in the branch above.
        List<Opportunity> createdOpportunities = new List<Opportunity>();
        List<Opportunity> l1BidderDeclaredOpportunities = new List<Opportunity>();
        for (Opportunity opp : newRecords) {
            // Only Project Opportunity
            if (!isProjectOpportunity(opp)) {
                continue;
            }
            Opportunity oldOpp = isInsert ? null : oldRecordsById.get(opp.Id);
            if (isInsert && opp.OwnerId != null) {
                createdOpportunities.add(opp);
            }
            if (qualifiesAsL1BidderDeclared(opp, oldOpp)) {
                l1BidderDeclaredOpportunities.add(opp);
            }
        }
        if (!createdOpportunities.isEmpty()) {
            emailSendRequests.add(
                new EmailSendRequest(
                    'CRM_HEAD',
                    createdOpportunities,
                    TEMPLATE_CRM_HEAD_OPPORTUNITY_CREATED
                )
            );
        }
        if (!l1BidderDeclaredOpportunities.isEmpty()) {
            emailSendRequests.add(
                new EmailSendRequest(
                    'CRM_HEAD',
                    l1BidderDeclaredOpportunities,
                    TEMPLATE_CRM_HEAD_L1_BIDDER_DECLARED
                )
            );
        }
        // ADDED: parallel notification to the Department HOD (Project record type only).
        List<Opportunity> projectCreatedOpportunities = filterProjectOpportunities(
            createdOpportunities
        );
        List<Opportunity> projectL1Opportunities = filterProjectOpportunities(
            l1BidderDeclaredOpportunities
        );
        if (!projectCreatedOpportunities.isEmpty()) {
            emailSendRequests.add(
                new EmailSendRequest(
                    'HOD',
                    projectCreatedOpportunities,
                    TEMPLATE_HOD_PROJECT_CREATED
                )
            );
        }
        if (!projectL1Opportunities.isEmpty()) {
            emailSendRequests.add(
                new EmailSendRequest(
                    'HOD',
                    projectL1Opportunities,
                    TEMPLATE_HOD_L1_BIDDER_DECLARED
                )
            );
        }
        enqueueEmailSends(emailSendRequests);
    }
    private static void enqueueEmailSends(List<EmailSendRequest> emailSendRequests) {
        if (emailSendRequests == null || emailSendRequests.isEmpty()) {
            return;
        }
        System.enqueueJob(new EmailSendQueueable(emailSendRequests));
    }
    private class EmailSendRequest {
        private String recipientType;
        private String templateDeveloperName;
        private List<Id> opportunityIds;
        private EmailSendRequest(
            String recipientType,
            List<Opportunity> opps,
            String templateDeveloperName
        ) {
            this.recipientType = recipientType;
            this.templateDeveloperName = templateDeveloperName;
            this.opportunityIds = new List<Id>();
            if (opps == null) {
                return;
            }
            for (Opportunity opp : opps) {
                if (opp != null && opp.Id != null) {
                    this.opportunityIds.add(opp.Id);
                }
            }
        }
        private List<Opportunity> toOpportunityStubs() {
            List<Opportunity> stubs = new List<Opportunity>();
            for (Id opportunityId : opportunityIds) {
                stubs.add(new Opportunity(Id = opportunityId));
            }
            return stubs;
        }
    }
    private class EmailSendQueueable implements Queueable {
        private List<EmailSendRequest> emailSendRequests;
        private EmailSendQueueable(List<EmailSendRequest> emailSendRequests) {
            this.emailSendRequests = emailSendRequests;
        }
        public void execute(QueueableContext context) {
            if (emailSendRequests == null || emailSendRequests.isEmpty()) {
                return;
            }
            for (EmailSendRequest request : emailSendRequests) {
                if (request == null || String.isBlank(request.templateDeveloperName)) {
                    continue;
                }
                List<Opportunity> opps = request.toOpportunityStubs();
                if (opps.isEmpty()) {
                    continue;
                }
                if (request.recipientType == 'OWNER') {
                    sendEmails(opps, request.templateDeveloperName);
                } else if (request.recipientType == 'CRM_HEAD') {
                    sendCrmHeadEmails(opps, request.templateDeveloperName);
                } else if (request.recipientType == 'HOD') {
                    sendHodEmails(opps, request.templateDeveloperName);
                }
            }
        }
    }
    // ADDED: mirrors branch 3 of getTemplateForChange(), extracted so it can be
    // reused here without altering the existing method.
    @TestVisible
    private static Boolean qualifiesAsL1BidderDeclared(Opportunity opp, Opportunity oldOpp) {
        if (opp == null || oldOpp == null) {
            return false;
        }
        return opp.StageName == STAGE_L1_BIDDER_DECLARED
            && oldOpp.StageName != STAGE_L1_BIDDER_DECLARED;
    }
    // ADDED
    @TestVisible
    private static List<Opportunity> filterProjectOpportunities(List<Opportunity> opps) {
        List<Opportunity> filtered = new List<Opportunity>();
        Id projectRtId = getProjectRecordTypeId();
        if (projectRtId == null) {
            return filtered;
        }
        for (Opportunity opp : opps) {
            if (opp.RecordTypeId == projectRtId) {
                filtered.add(opp);
            }
        }
        return filtered;
    }
    // ADDED: true only for Project Opportunity record type
    @TestVisible
    private static Boolean isProjectOpportunity(Opportunity opp) {
        if (opp == null) {
            return false;
        }
        Id projectRtId = getProjectRecordTypeId();
        return projectRtId != null && opp.RecordTypeId == projectRtId;
    }
    // ADDED
    private static Id getProjectRecordTypeId() {
        if (projectRecordTypeId != null) {
            return projectRecordTypeId;
        }
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Opportunity'
            AND DeveloperName = :PROJECT_RECORD_TYPE_DEVELOPER_NAME
            AND IsActive = TRUE
            LIMIT 1
        ];
        projectRecordTypeId = recordTypes.isEmpty() ? null : recordTypes[0].Id;
        return projectRecordTypeId;
    }
    @TestVisible
    private static String getTemplateForChange(Opportunity opp, Opportunity oldOpp, Boolean isInsert) {
        if (opp == null || opp.OwnerId == null) {
            return null;
        }
        // 1) New Opportunity Assigned - on insert
        if (isInsert) {
            return TEMPLATE_NEW_OPPORTUNITY_ASSIGNED;
        }
        if (oldOpp == null) {
            return null;
        }
        // 2) Re-assignment - OwnerId changed
        if (opp.OwnerId != oldOpp.OwnerId) {
            return TEMPLATE_NEW_OPPORTUNITY_ASSIGNED;
        }
        // 3) L1 Bidder Declared - StageName transitioned into the L1 Bidder stage
        if (opp.StageName == STAGE_L1_BIDDER_DECLARED
            && oldOpp.StageName != STAGE_L1_BIDDER_DECLARED) {
            return TEMPLATE_L1_BIDDER_DECLARED;
        }
        return null;
    }
    private static void sendEmails(List<Opportunity> opps, String templateDeveloperName) {
        Id templateId = resolveTemplateId(templateDeveloperName);
        if (templateId == null) {
            System.debug('Template not found: ' + templateDeveloperName);
            return;
        }
        Id oweaId = getOrgWideEmailAddressId();
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity opp : opps) {
            oppIds.add(opp.Id);
        }
        List<Opportunity> oppsWithDetails = [
            SELECT Id, OwnerId, Owner.Email
            FROM Opportunity
            WHERE Id IN :oppIds
            AND Owner.Email != null
        ];
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Opportunity opp : oppsWithDetails) {
            // Salesforce does not allow WhatId when TargetObjectId is a User.
            // Render the Opportunity template, then send to the Owner email.
            Messaging.SingleEmailMessage mail = buildFormulaRecipientMessage(
                templateId,
                opp.Id,
                opp.Owner.Email.trim(),
                oweaId
            );
            if (mail != null) {
                messages.add(mail);
            }
        }
        sendMessageBatch(messages, 'Opportunity Owner');
    }
    // ADDED: sends to the Department CRM Head. Recipient isn't a Salesforce
    // Contact/Lead/User, so setTargetObjectId isn't usable - the email comes
    // directly from CRM_User_Email_Formula__c on Opportunity itself.
    private static void sendCrmHeadEmails(List<Opportunity> opps, String templateDeveloperName) {
        Id templateId = resolveTemplateId(templateDeveloperName);
        if (templateId == null) {
            System.debug('CRM Head template not found: ' + templateDeveloperName);
            return;
        }
        Id oweaId = getOrgWideEmailAddressId();
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity opp : opps) {
            oppIds.add(opp.Id);
        }
        List<Opportunity> oppsWithDetails = [
            SELECT Id, Department_Name__c, CRM_User_Email_Formula__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ];
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Opportunity opp : oppsWithDetails) {
            String crmHeadEmail = resolveCrmHeadEmail(opp);
            if (String.isBlank(crmHeadEmail)) {
                System.debug(
                    'CRM Head email not resolved for Opportunity ' +
                    opp.Id +
                    ' (Department_Name__c=' +
                    opp.Department_Name__c +
                    ')'
                );
                continue;
            }
            Messaging.SingleEmailMessage mail = buildFormulaRecipientMessage(
                templateId,
                opp.Id,
                crmHeadEmail.trim(),
                oweaId
            );
            if (mail != null) {
                messages.add(mail);
            }
        }
        sendMessageBatch(messages, 'Opportunity CRM Head');
    }
    // ADDED: sends to the Department HOD resolved via HOD_User_Email_Formula__c.
    private static void sendHodEmails(List<Opportunity> opps, String templateDeveloperName) {
        Id templateId = resolveTemplateId(templateDeveloperName);
        if (templateId == null) {
            System.debug('HOD template not found: ' + templateDeveloperName);
            return;
        }
        Id oweaId = getOrgWideEmailAddressId();
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity opp : opps) {
            oppIds.add(opp.Id);
        }
        List<Opportunity> oppsWithDetails = [
            SELECT Id, Department_Name__c, HOD_User_Email_Formula__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ];
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Opportunity opp : oppsWithDetails) {
            String hodEmail = resolveHodEmail(opp);
            if (String.isBlank(hodEmail)) {
                System.debug(
                    'HOD email not resolved for Opportunity ' +
                    opp.Id +
                    ' (Department_Name__c=' +
                    opp.Department_Name__c +
                    ')'
                );
                continue;
            }
            Messaging.SingleEmailMessage mail = buildFormulaRecipientMessage(
                templateId,
                opp.Id,
                hodEmail.trim(),
                oweaId
            );
            if (mail != null) {
                messages.add(mail);
            }
        }
        sendMessageBatch(messages, 'Opportunity HOD');
    }
    @TestVisible
    private static String resolveCrmHeadEmail(Opportunity opp) {
        if (opp == null) {
            return null;
        }
        if (String.isNotBlank(opp.CRM_User_Email_Formula__c)) {
            return opp.CRM_User_Email_Formula__c.trim();
        }
        return lookupDepartmentEmail(opp.Department_Name__c, getCrmEmailByDepartment());
    }
    @TestVisible
    private static String resolveHodEmail(Opportunity opp) {
        if (opp == null) {
            return null;
        }
        if (String.isNotBlank(opp.HOD_User_Email_Formula__c)) {
            return opp.HOD_User_Email_Formula__c.trim();
        }
        return lookupDepartmentEmail(opp.Department_Name__c, getHodEmailByDepartment());
    }
    private static String lookupDepartmentEmail(
        String departmentName,
        Map<String, String> emailByDepartment
    ) {
        if (String.isBlank(departmentName) || emailByDepartment == null || emailByDepartment.isEmpty()) {
            return null;
        }
        return emailByDepartment.get(departmentName.trim().toLowerCase());
    }
    private static Map<String, String> getCrmEmailByDepartment() {
        if (crmEmailByDepartment != null) {
            return crmEmailByDepartment;
        }
        crmEmailByDepartment = new Map<String, String>();
        for (Department_CRM_Person__mdt record : [
            SELECT Department_Name__c, CRM_Person_Email__c
            FROM Department_CRM_Person__mdt
        ]) {
            if (
                String.isBlank(record.Department_Name__c) ||
                String.isBlank(record.CRM_Person_Email__c)
            ) {
                continue;
            }
            crmEmailByDepartment.put(
                record.Department_Name__c.trim().toLowerCase(),
                record.CRM_Person_Email__c.trim()
            );
        }
        return crmEmailByDepartment;
    }
    private static Map<String, String> getHodEmailByDepartment() {
        if (hodEmailByDepartment != null) {
            return hodEmailByDepartment;
        }
        hodEmailByDepartment = new Map<String, String>();
        for (Department_HOD_Person__mdt record : [
            SELECT Department_Name__c, HOD_Person_Email__c
            FROM Department_HOD_Person__mdt
        ]) {
            if (
                String.isBlank(record.Department_Name__c) ||
                String.isBlank(record.HOD_Person_Email__c)
            ) {
                continue;
            }
            hodEmailByDepartment.put(
                record.Department_Name__c.trim().toLowerCase(),
                record.HOD_Person_Email__c.trim()
            );
        }
        return hodEmailByDepartment;
    }
    private static void sendMessageBatch(
        List<Messaging.SingleEmailMessage> messages,
        String recipientLabel
    ) {
        if (messages == null || messages.isEmpty()) {
            return;
        }
        try {
            Messaging.sendEmail(messages, false);
        } catch (Exception e) {
            System.debug('Error sending ' + recipientLabel + ' emails: ' + e.getMessage());
        }
    }
    // ADDED
    private static Messaging.SingleEmailMessage buildFormulaRecipientMessage(
        Id templateId,
        Id opportunityId,
        String recipientEmail,
        Id oweaId
    ) {
        if (templateId == null || opportunityId == null || String.isBlank(recipientEmail)) {
            return null;
        }
        Messaging.SingleEmailMessage mail;
        try {
            mail = Messaging.renderStoredEmailTemplate(templateId, null, opportunityId);
        } catch (Exception e) {
            System.debug('Formula recipient template render failed: ' + e.getMessage());
            return null;
        }
        mail.setTargetObjectId(null);
        mail.setToAddresses(new List<String>{ recipientEmail });
        mail.setSaveAsActivity(false);
        mail.setTreatTargetObjectAsRecipient(false);
        if (oweaId != null) {
            mail.setOrgWideEmailAddressId(oweaId);
        }
        return mail;
    }
    private static Id resolveTemplateId(String developerName) {
        if (Test.isRunningTest() && testTemplateIdOverride != null) {
            return testTemplateIdOverride;
        }
        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Id;
    }
    private static Id getOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_SENDER_EMAIL
            LIMIT 1
        ];
        return owea.isEmpty() ? null : owea[0].Id;
    }
}