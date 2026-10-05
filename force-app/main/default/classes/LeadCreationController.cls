/**
 * LeadCreationController
 * ----------------------
 * Server side for the newLeadForm LWC — a single-screen rebuild of the
 * "Lead_New_Lead_Flow" screen flow. Replicates, same-to-same:
 *   - Profile / UserRole driven branching (Admin path vs Others path)
 *   - Department-filtered Lead owner choices (User.Department CONTAINS dept)
 *   - Lead insert with the exact field mapping of Create_Lead_Admin / _Others
 *   - Child Product_Category__c inserts (Status = Active, Lead__c set)
 *   - ContentDocumentLink creation (ShareType 'V', Visibility 'AllUsers')
 *   - BWM_SendEmailInvocable  (triggerPoint 'Email_Lead_Create')
 *   - BWM_SendMessageInvocable (triggerPoint 'Lead_Create')
 *   - Post-save ListView resolution: first Lead list view whose Name
 *     contains the resolved department (flow: Get_ListViews*)
 *   - Roll Back Records on any failure (Database savepoint)
 */
public with sharing class LeadCreationController {

    /* ==================== INIT CONTEXT ==================== */

    public class InitContext {
        @AuraEnabled public Id     userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String profileName;
        @AuraEnabled public String userDepartment;
        @AuraEnabled public String roleName;
        @AuraEnabled public String roleDeveloperName;
    }

    @AuraEnabled(cacheable=true)
    public static InitContext getInitContext() {
        InitContext ctx = new InitContext();
        User u = [
            SELECT Id, Name, Department, Profile.Name,
                   UserRole.Name, UserRole.DeveloperName
            FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];
        ctx.userId            = u.Id;
        ctx.userName          = u.Name;
        ctx.profileName       = u.Profile.Name;
        ctx.userDepartment    = u.Department;
        ctx.roleName          = (u.UserRole != null) ? u.UserRole.Name : '';
        ctx.roleDeveloperName = (u.UserRole != null) ? u.UserRole.DeveloperName : '';
        return ctx;
    }

    /* ==================== OWNER OPTIONS ==================== */
    /* Flow: dynamic choice set on User with filter
       Department CONTAINS <resolved department>.
       IsActive added because an inactive OwnerId would fail DML anyway. */

    public class OwnerOption {
        @AuraEnabled public Id     value;
        @AuraEnabled public String label;
    }

    @AuraEnabled(cacheable=true)
    public static List<OwnerOption> getOwnerOptions(String department) {
        List<OwnerOption> options = new List<OwnerOption>();
        if (String.isBlank(department)) { return options; }
        String deptFilter = '%' + String.escapeSingleQuotes(department) + '%';
        for (User u : [
            SELECT Id, Name FROM User
            WHERE Department LIKE :deptFilter AND IsActive = true
            ORDER BY Name LIMIT 500
        ]) {
            OwnerOption o = new OwnerOption();
            o.value = u.Id;
            o.label = u.Name;
            options.add(o);
        }
        return options;
    }

    /* ==================== FILE UPLOAD ==================== */
    /* Flow uploads via forceContent:fileUpload BEFORE the Lead exists,
       then links docs after Create_Lead. Same here: upload unattached,
       link on submit. */

    public class UploadedFile {
        @AuraEnabled public Id     contentDocumentId;
        @AuraEnabled public String fileName;
    }

    @AuraEnabled
    public static UploadedFile uploadFile(String fileName, String base64Data) {
        if (String.isBlank(fileName) || String.isBlank(base64Data)) {
            throw new AuraHandledException('File name and content are required.');
        }
        ContentVersion cv = new ContentVersion(
            Title        = fileName,
            PathOnClient = fileName,
            VersionData  = EncodingUtil.base64Decode(base64Data)
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        UploadedFile f = new UploadedFile();
        f.contentDocumentId = cv.ContentDocumentId;
        f.fileName          = fileName;
        return f;
    }

    @AuraEnabled
    public static void deleteUploadedFile(Id contentDocumentId) {
        // Removal before submit; only docs the running user just created.
        List<ContentDocument> docs = [
            SELECT Id FROM ContentDocument
            WHERE Id = :contentDocumentId AND CreatedById = :UserInfo.getUserId()
        ];
        if (!docs.isEmpty()) { delete docs; }
    }

    /* ==================== CREATE LEAD ==================== */

    public class ProductCategoryRow {
        @AuraEnabled public String  department;
        @AuraEnabled public String  category;
        @AuraEnabled public String  uom;
        @AuraEnabled public Decimal quantity;
    }

    public class LeadPayload {
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String company;          // CompanyFormula result
        @AuraEnabled public String companyName;      // Company_Name__c
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String status;           // Lead_Stage (default Prospect)
        @AuraEnabled public String leadSource;
        @AuraEnabled public String previousSource;
        @AuraEnabled public String rating;
        @AuraEnabled public String industry;
        @AuraEnabled public String customerCategory;
        @AuraEnabled public String departmentName;
        @AuraEnabled public String zone;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String country;
        @AuraEnabled public String state;
        @AuraEnabled public String pin;
        @AuraEnabled public Id     ownerId;          // resolved on client per flow rules
        @AuraEnabled public List<ProductCategoryRow> productCategories;
        @AuraEnabled public List<Id> contentDocumentIds;
    }

    public class CreateResult {
        @AuraEnabled public Id      leadId;
        @AuraEnabled public String  listViewId;      // for /lightning/o/Lead/list?filterName=
        @AuraEnabled public Boolean notificationsQueued;
        @AuraEnabled public String  notificationError;
    }

    @AuraEnabled
    public static CreateResult createLead(String payloadJson) {
        LeadPayload p;
        try {
            p = (LeadPayload) JSON.deserialize(payloadJson, LeadPayload.class);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid payload: ' + e.getMessage());
        }
        if (p == null || String.isBlank(p.lastName) || String.isBlank(p.leadSource)) {
            throw new AuraHandledException('Name and Lead Source are required.');
        }

        Savepoint sp = Database.setSavepoint();   // flow: Roll Back Records
        CreateResult result = new CreateResult();
        try {
            /* ---- Lead (mapping mirrors Create_Lead_Admin / Create_Lead_Others) ---- */
            Lead newLead = new Lead(
                FirstName            = p.firstName,
                LastName             = p.lastName,
                Company              = p.company,
                Company_Name__c      = p.companyName,
                Email                = p.email,
                Phone                = p.phone,
                Status               = String.isBlank(p.status) ? 'Prospect' : p.status,
                LeadSource           = p.leadSource,
                Previous_Source__c   = p.previousSource,
                Rating               = p.rating,
                Industry             = p.industry,
                Customer_Category__c = p.customerCategory,
                Department_Name__c   = p.departmentName,
                Zone__c              = p.zone,
                Street__c            = p.street,
                City__c              = p.city,
                Country__c           = p.country,
                State__c             = p.state,
                PIN__c               = p.pin
            );
            if (p.ownerId != null) { newLead.OwnerId = p.ownerId; }
            insert newLead;
            result.leadId = newLead.Id;

            /* ---- ContentDocumentLinks (ShareType V / AllUsers, as in flow) ---- */
            if (p.contentDocumentIds != null && !p.contentDocumentIds.isEmpty()) {
                List<ContentDocumentLink> links = new List<ContentDocumentLink>();
                for (Id docId : p.contentDocumentIds) {
                    links.add(new ContentDocumentLink(
                        ContentDocumentId = docId,
                        LinkedEntityId    = newLead.Id,
                        ShareType         = 'V',
                        Visibility        = 'AllUsers'
                    ));
                }
                insert links;
            }

            /* ---- Product_Category__c children (Status Active, Lead__c set) ---- */
            if (p.productCategories != null && !p.productCategories.isEmpty()) {
                List<Product_Category__c> rows = new List<Product_Category__c>();
                for (ProductCategoryRow r : p.productCategories) {
                    if (r == null || String.isBlank(r.category)) { continue; }
                    rows.add(new Product_Category__c(
                        // Name is Auto Number on this object — never assigned
                        Department_Name__c  = r.department,
                        Product_Category__c = r.category,
                        UOM__c              = r.uom,
                        Quantity__c         = r.quantity,
                        Status__c           = 'Active',
                        Lead__c             = newLead.Id
                    ));
                }
                if (!rows.isEmpty()) { insert rows; }
            }

            /* ---- Notifications: exact trigger points from the flow ---- */
            result.notificationsQueued = true;
            try {
                BWM_SendEmailInvocable.Request emailReq = new BWM_SendEmailInvocable.Request();
                emailReq.recordId     = newLead.Id;
                emailReq.triggerPoint = 'Email_Lead_Create';
                BWM_SendEmailInvocable.sendEmail(
                    new List<BWM_SendEmailInvocable.Request>{ emailReq });

                BWM_SendMessageInvocable.Request msgReq = new BWM_SendMessageInvocable.Request();
                msgReq.recordId     = newLead.Id;
                msgReq.triggerPoint = 'Lead_Create';
                BWM_SendMessageInvocable.sendMessage(
                    new List<BWM_SendMessageInvocable.Request>{ msgReq });
            } catch (Exception notifyEx) {
                // The lead itself must survive a messaging hiccup.
                result.notificationsQueued = false;
                result.notificationError   = notifyEx.getMessage();
            }

            /* ---- ListView for redirect (flow: Name CONTAINS department) ---- */
            result.listViewId = resolveListViewId(p.departmentName);
            return result;

        } catch (AuraHandledException ahe) {
            Database.rollback(sp);
            throw ahe;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Lead creation failed: ' + e.getMessage());
        }
    }

    private static String resolveListViewId(String department) {
        try {
            if (String.isNotBlank(department)) {
                String deptFilter = '%' + String.escapeSingleQuotes(department) + '%';
                List<ListView> views = [
                    SELECT Id FROM ListView
                    WHERE SobjectType = 'Lead' AND Name LIKE :deptFilter
                    LIMIT 1
                ];
                if (!views.isEmpty()) { return views[0].Id; }
            }
        } catch (Exception ignored) { /* fall through */ }
        return 'Recent';
    }
}