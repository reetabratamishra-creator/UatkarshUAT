/**
 * Apex + LWC replacement for the "Custom_Account_Creation" screen flow.
 *
 * Faithful port of the flow's live (Active) behaviour, with one deliberate fix:
 * department selection for non-Admin users is driven by the running user's
 * Departments__c (multi-select) instead of the flow's 10 separate fields that
 * were each gated by the single-valued $UserRole.Name Contains "<Dept>" check
 * (which made a second department completely unselectable for a dual-department
 * user). Record Type selection intentionally remains unfiltered, matching the
 * live flow, since its profile-based filtering (Account_Record_Type_Matrix__mdt)
 * was dead/unwired code in the flow, never exercised in production.
 */
public with sharing class AccountCreationController {

    // Departments__c (multi-select picklist value) -> Account.Department_Name__c (picklist label).
    // Verified directly against both field definitions and real Account data, not assumed.
    private static final Map<String, String> DEPARTMENTS_TO_ACCOUNT_LABEL = new Map<String, String>{
        'Crash_Barrier_Department'     => 'Crash Barrier',
        'High_Mast_Department'         => 'High Mast & Polygonal',
        'Solar_Structure_Department'   => 'Solar Structure',
        'Steel_Pipes_Department'       => 'Steel Pipes',
        'Steel_Tubular_Pole_Department'=> 'Steel Tubular Poles',
        'Transmission_Tower_Department'=> 'Transmission & Telecom Tower',
        'Telecom_Tower_Department'     => 'Transmission & Telecom Tower', // legacy alias, same Account value
        'Core_Department'              => 'Railway Electrification Structure',
        'HDPE_Pipe_Department'         => 'HDPE',
        'PEB'                          => 'Pre Engineering Building',
        'PVC'                          => 'Polymer'
    };

    private static final Set<String> RESTRICTED_PROFILES_NO_DEPARTMENT = new Set<String>{
        'Utkarsh Sales', 'Utakrsh Department CRM User', 'Utkarsh CRM'
    };

    // ===================== DTOs =====================

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class InitData {
        @AuraEnabled public Boolean isAllowed;
        @AuraEnabled public Boolean isAdmin;
        @AuraEnabled public String currentUserProfile;
        @AuraEnabled public Id dealerRecordTypeId;
        @AuraEnabled public List<PicklistOption> recordTypeOptions;
        @AuraEnabled public List<PicklistOption> accountSourceOptions;
        @AuraEnabled public List<PicklistOption> industryOptions;
        @AuraEnabled public List<PicklistOption> departmentOptions;      // single-select, non-Dealer
        @AuraEnabled public List<PicklistOption> multiDepartmentOptions; // multi-select, Dealer only
        @AuraEnabled public List<PicklistOption> countryOptions;
        @AuraEnabled public List<PicklistOption> stateOptions;
        @AuraEnabled public List<PicklistOption> zoneOptions;
    }

    public class AddressInput {
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String pin;
        @AuraEnabled public String country;
        @AuraEnabled public String state;
        @AuraEnabled public String zone;
    }

    public class AccountCreationRequest {
        // Id-typed fields in @AuraEnabled input classes deserialize as null from LWC - keep these as String
        @AuraEnabled public String recordTypeId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Boolean isChildAccount;
        @AuraEnabled public String parentAccountId;
        @AuraEnabled public String accountSource;
        @AuraEnabled public String industry;
        @AuraEnabled public String departmentName;             // Account.Department_Name__c
        @AuraEnabled public String departmentNameMultiSelect;  // Account.Department_Name_MultiSelect__c, Dealer only, semicolon-delimited
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String website;
        @AuraEnabled public String pan;
        @AuraEnabled public String gstin;

        @AuraEnabled public Boolean useExistingContact;
        @AuraEnabled public String existingContactId;
        @AuraEnabled public String contactFirstName;
        @AuraEnabled public String contactLastName;
        @AuraEnabled public String contactEmail;
        @AuraEnabled public String contactPhone;

        @AuraEnabled public AddressInput primaryAddress;
        @AuraEnabled public List<AddressInput> additionalAddresses;
    }

    public class CreationResult {
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id contactId;
    }

    // ===================== Init =====================

    @AuraEnabled(cacheable=true)
    public static InitData getInitData() {
        InitData result = new InitData();

        User currentUser = [
            SELECT Id, Department, Departments__c, Profile.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        String profileName = currentUser.Profile.Name;
        result.currentUserProfile = profileName;

        result.isAllowed = isProfileAllowed(profileName);
        if (!result.isAllowed) {
            return result;
        }

        Boolean isAdmin = (profileName == 'System Administrator' || profileName == 'Utkarsh Admin');
        Boolean isCRM = (profileName == 'Utkarsh CRM' || profileName == 'Utakrsh Department CRM User');
        Boolean isCRMHeadOrHOD = (profileName == 'CRM Head' || profileName == 'Utkarsh HOD');
        Boolean isProject = (profileName == 'Utkarsh Projects');
        result.isAdmin = isAdmin;

        result.recordTypeOptions = getAccountRecordTypeOptions();
        result.dealerRecordTypeId = getDealerRecordTypeId();
        result.industryOptions = getPicklistOptions(Account.Industry);
        result.countryOptions = getPicklistOptions(Address_Book__c.Country__c);
        result.stateOptions = getPicklistOptions(Address_Book__c.State__c);
        result.zoneOptions = getPicklistOptions(Address_Book__c.Zone__c);
        result.accountSourceOptions = getAccountSourceOptions(isAdmin, isCRM, isCRMHeadOrHOD, isProject);
        result.multiDepartmentOptions = getPicklistOptions(Account.Department_Name_MultiSelect__c);
        result.departmentOptions = getDepartmentOptions(isAdmin, currentUser.Departments__c);

        return result;
    }

    private static Boolean isProfileAllowed(String profileName) {
        if (String.isBlank(profileName)) {
            return false;
        }
        for (Account_creation_allowed__mdt rule : [
            SELECT MasterLabel
            FROM Account_creation_allowed__mdt
            WHERE isActive__c = true
        ]) {
            if (rule.MasterLabel == profileName) {
                return true;
            }
        }
        return false;
    }

    private static List<PicklistOption> getAccountRecordTypeOptions() {
        // Intentionally unfiltered - matches the live flow's behaviour
        // (its profile-based Record Type matrix was dead/unwired code).
        List<PicklistOption> options = new List<PicklistOption>();
        for (RecordType rt : [
            SELECT Id, Name
            FROM RecordType
            WHERE SobjectType = 'Account'
            ORDER BY Name
        ]) {
            options.add(new PicklistOption(rt.Name, rt.Id));
        }
        return options;
    }

    private static Id getDealerRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account' AND Name = 'Dealer'
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static List<PicklistOption> getAccountSourceOptions(Boolean isAdmin, Boolean isCRM, Boolean isCRMHeadOrHOD, Boolean isProject) {
        if (isAdmin) {
            return getPicklistOptions(Account.AccountSource);
        }
        List<String> values;
        if (isCRMHeadOrHOD) {
            values = new List<String>{ 'CRM_RESOURCE', 'EMAIL_CAMPAIGNING', 'EVENT_ACTIVATION', 'INBOUND_EMAIL',
                'INBOUND_PHONE_CALL', 'OFFLINE_CRM', 'Offline_Marketing', 'OUTBOUND_PHONE_CALL', 'TENDER',
                'WHATSAPP_CAMPAIGNING', 'PROJECTS' };
        } else if (isCRM) {
            values = new List<String>{ 'CRM_RESOURCE', 'EMAIL_CAMPAIGNING', 'INBOUND_EMAIL', 'INBOUND_PHONE_CALL',
                'OFFLINE_CRM', 'Offline_Marketing', 'OUTBOUND_PHONE_CALL', 'TENDER', 'WHATSAPP_CAMPAIGNING', 'PROJECTS' };
        } else if (isProject) {
            values = new List<String>{ 'PROJECTS' };
        } else {
            // Sales / Tender / other non-admin, non-CRM, non-CRM-Head-or-HOD, non-Project profiles
            values = new List<String>{ 'Offline_Marketing', 'TENDER', 'PROJECTS' };
        }
        List<PicklistOption> options = new List<PicklistOption>();
        for (String v : values) {
            options.add(new PicklistOption(v, v));
        }
        return options;
    }

    private static List<PicklistOption> getDepartmentOptions(Boolean isAdmin, String departmentsField) {
        if (isAdmin) {
            // Admins pick from the full Account department picklist, same as the live flow.
            return getPicklistOptions(Account.Department_Name__c);
        }
        List<PicklistOption> options = new List<PicklistOption>();
        if (String.isBlank(departmentsField)) {
            return options;
        }
        Set<String> seen = new Set<String>();
        for (String token : departmentsField.split(';')) {
            String trimmed = token.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            String accountLabel = DEPARTMENTS_TO_ACCOUNT_LABEL.get(trimmed);
            if (accountLabel != null && !seen.contains(accountLabel)) {
                seen.add(accountLabel);
                options.add(new PicklistOption(accountLabel, accountLabel));
            }
        }
        return options;
    }

    private static List<PicklistOption> getPicklistOptions(Schema.SObjectField field) {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    // ===================== Server-side validation (never trust client-only checks) =====================

    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$');
    private static final Pattern PAN_PATTERN = Pattern.compile('^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
    private static final Pattern GSTIN_PATTERN = Pattern.compile('^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
    private static final Pattern WEBSITE_PATTERN = Pattern.compile('^(https?://)?([a-z0-9-]+\\.)+[a-z]{2,}(/.*)?$');

    private static void validateRequest(AccountCreationRequest req) {
        if (req == null || String.isBlank(req.recordTypeId) || String.isBlank(req.accountName)) {
            throw new AuraHandledException('Account Name and Record Type are required.');
        }
        if (String.isBlank(req.email) || !EMAIL_PATTERN.matcher(req.email).matches()) {
            throw new AuraHandledException('Please enter a valid email address.');
        }
        if (String.isNotBlank(req.pan) && !PAN_PATTERN.matcher(req.pan.toUpperCase()).matches()) {
            throw new AuraHandledException('Please enter a valid PAN number in the format ABCDE1234F.');
        }
        if (String.isNotBlank(req.gstin) && !GSTIN_PATTERN.matcher(req.gstin.toUpperCase()).matches()) {
            throw new AuraHandledException('Please enter a valid GSTIN in the format 29ABCDE1234F1Z5.');
        }
        if (String.isNotBlank(req.website) && !WEBSITE_PATTERN.matcher(req.website.toLowerCase()).matches()) {
            throw new AuraHandledException('Please enter a valid website URL (for example: www.google.com or https://www.google.com).');
        }
        if (req.primaryAddress == null || String.isBlank(req.primaryAddress.street)
                || String.isBlank(req.primaryAddress.city) || String.isBlank(req.primaryAddress.pin)
                || String.isBlank(req.primaryAddress.country)) {
            throw new AuraHandledException('Please complete the primary address (Street, City, PIN, Country).');
        }
        if (req.useExistingContact == true) {
            if (String.isBlank(req.existingContactId)) {
                throw new AuraHandledException('Please select an existing Contact.');
            }
        } else {
            if (String.isBlank(req.contactLastName) || String.isBlank(req.contactEmail)) {
                throw new AuraHandledException('Contact Last Name and Email are required.');
            }
        }
    }

    // ===================== Create =====================

    // LWC entry point. The request travels as a JSON string because the platform's
    // LWC-to-Apex deserialization of the custom type parameter arrived null in this org.
    @AuraEnabled
    public static CreationResult createAccountFromJson(String reqJson) {
        System.debug('AccountCreation raw request: ' + reqJson);
        AccountCreationRequest req;
        try {
            req = (AccountCreationRequest) JSON.deserialize(reqJson, AccountCreationRequest.class);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid request payload.');
        }
        return createAccount(req);
    }

    public static CreationResult createAccount(AccountCreationRequest req) {
        // Re-check the access gate server-side - never trust the client alone for this.
        User currentUser = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (!isProfileAllowed(currentUser.Profile.Name)) {
            throw new AuraHandledException('Your profile does not have permission to create Account manually.');
        }

        validateRequest(req);

        Savepoint sp = Database.setSavepoint();
        try {
            Id dealerRecordTypeId = getDealerRecordTypeId();
            Boolean isDealer = (dealerRecordTypeId != null && dealerRecordTypeId == req.recordTypeId);

            Account acc = new Account(
                Name = req.accountName,
                RecordTypeId = req.recordTypeId,
                AccountSource = req.accountSource,
                Industry = req.industry,
                Phone = req.phone,
                Email__c = req.email,
                Website = req.website,
                PAN__c = req.pan,
                GSTIN__c = req.gstin
            );
            if (req.isChildAccount == true && String.isNotBlank(req.parentAccountId)) {
                acc.ParentId = req.parentAccountId;
            }
            if (isDealer) {
                acc.Department_Name_MultiSelect__c = req.departmentNameMultiSelect;
            } else {
                acc.Department_Name__c = req.departmentName;
            }
            insert acc;

            Id contactId;
            if (req.useExistingContact == true) {
                Contact con = new Contact(Id = req.existingContactId, AccountId = acc.Id);
                update con;
                contactId = req.existingContactId;
            } else {
                Contact con = new Contact(
                    FirstName = req.contactFirstName,
                    LastName = req.contactLastName,
                    Email = req.contactEmail,
                    Phone = req.contactPhone,
                    AccountId = acc.Id
                );
                insert con;
                contactId = con.Id;
            }

            List<Address_Book__c> addressesToInsert = new List<Address_Book__c>();
            addressesToInsert.add(toAddressBook(req.primaryAddress, acc.Id));
            if (req.additionalAddresses != null) {
                for (AddressInput addl : req.additionalAddresses) {
                    if (addl != null && String.isNotBlank(addl.street)) {
                        addressesToInsert.add(toAddressBook(addl, acc.Id));
                    }
                }
            }
            insert addressesToInsert;

            CreationResult result = new CreationResult();
            result.accountId = acc.Id;
            result.contactId = contactId;
            return result;
        } catch (Exception ex) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, 'AccountCreationController.createAccount failed: ' + ex.getTypeName() + ': ' + ex.getMessage() + '\n' + ex.getStackTraceString());
            if (ex instanceof AuraHandledException) {
                throw ex;
            }
            AuraHandledException ahe = new AuraHandledException(ex.getMessage());
            ahe.setMessage(ex.getMessage());
            throw ahe;
        }
    }

    private static Address_Book__c toAddressBook(AddressInput input, Id accountId) {
        return new Address_Book__c(
            Account__c = accountId,
            Street__c = input.street,
            City__c = input.city,
            PIN__c = input.pin,
            Country__c = input.country,
            State__c = input.state,
            Zone__c = input.zone
        );
    }
}