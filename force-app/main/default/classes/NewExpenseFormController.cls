public class NewExpenseFormController {

    @AuraEnabled(cacheable=true)
    public static Travel_Eligibility_Matrix__c getEligibility() {
        try {
            User currentUser = [
                SELECT Id, Employee_Level__c
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            if (String.isBlank(currentUser.Employee_Level__c)) {
                throw buildAuraException('Employee Level is not set on your user record. Please contact admin.');
            }

            List<Travel_Eligibility_Matrix__c> matrices = [
                SELECT Id, Name, Level__c, Grade__c, Designations__c,
                       Lodging_Tier_1__c, Lodging_Tier_2__c, Lodging_Tier_3__c,
                       Fooding_Tier_1__c, Fooding_Tier_2__c, Fooding_Tier_3__c,
                       Air_Business_Class__c, Air_Economy_Class__c,
                       Train_1AC__c, Train_2AC__c, Train_3AC__c, Train_Sleeper__c,
                       Ola_Uber_Taxi__c, Car_Rental__c, Auto__c, Bus__c,
                       Own_2_Wheeler_Rate_per_KM__c, Own_4_Wheeler_Rate_per_KM__c
                FROM Travel_Eligibility_Matrix__c
                WHERE Level__c = :currentUser.Employee_Level__c
                LIMIT 1
            ];

            if (matrices.isEmpty()) {
                throw buildAuraException(
                    'No Travel Eligibility Matrix found for level ' + currentUser.Employee_Level__c + '.'
                );
            }

            return matrices[0];
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<Expense_Line__c> getPrivateVehicleExpenseLines(Date startDate, Date endDate) {
        try {
            Id currentUserId = UserInfo.getUserId();
            if (startDate == null || endDate == null) {
                return new List<Expense_Line__c>();
            }
            DateTime startDateTime = DateTime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
            DateTime endDateTime = DateTime.newInstance(endDate, Time.newInstance(23, 59, 59, 0));

            return [
                SELECT Id, Name, Date__c, Start_Date__c, AI_Extracted_Distance__c, Manually_Extracted_Distance__c,
                       Vehicle_Type__c, Amount__c, Expense__c, Description__c, Punch_Record__c, Expense_Type__c
                FROM Expense_Line__c
                WHERE (
                    Expense__r.Employee__c = :currentUserId 
                    OR Expense__r.OwnerId = :currentUserId 
                    OR CreatedById = :currentUserId 
                    OR Expense__r.CreatedById = :currentUserId
                )
                  AND (
                      Expense__r.Status__c = 'New' 
                      OR Expense__r.Status__c = 'Draft' 
                      OR Expense__r.Status__c = null
                  )
                  AND (
                      Expense__r.Is_Private_Vehicle_Expense__c = true 
                      OR Expense_Type__c = 'Own Vehicle' 
                      OR Expense_Type__c = 'Private Vehicle'
                      OR Is_Private_Vehicle_Expense__c = true
                  )
                  AND (
                      (Date__c >= :startDate AND Date__c <= :endDate)
                      OR (Start_Date__c >= :startDate AND Start_Date__c <= :endDate)
                      OR (Date__c = null AND Start_Date__c = null AND CreatedDate >= :startDateTime AND CreatedDate <= :endDateTime)
                  )
                ORDER BY Date__c ASC, Start_Date__c ASC, CreatedDate ASC
            ];
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String saveExpenseData(String payload) {
        try {
            ExpensePayload data = (ExpensePayload) JSON.deserialize(payload, ExpensePayload.class);

            Id currentUserId = UserInfo.getUserId();
            User currentUser = [SELECT Id, Employee_Level__c, ManagerId, Department, Profile.Name FROM User WHERE Id = :currentUserId LIMIT 1];

            Id approverId = null;

            List<User> hodUser = [
                SELECT Id FROM User WHERE Department = :currentUser.Department
                AND Profile.Name = 'Utkarsh HOD' LIMIT 1
            ];

            if (!hodUser.isEmpty()) {
                approverId = hodUser[0].Id;
            }

            if (data.endDate != null) {
                Date today = Date.today();
                Integer currentYear = today.year();
                Integer currentMonth = today.month();
                Integer currentDay = today.day();

                Integer endYear = data.endDate.year();
                Integer endMonth = data.endDate.month();

                Integer monthDiff = (currentYear - endYear) * 12 + (currentMonth - endMonth);
                if (monthDiff == 1) {
                    if (currentDay > 5) {
                        throw buildAuraException('Expenses for the previous month can only be submitted up to the 5th of the current month.');
                    }
                } else if (monthDiff > 1) {
                    throw buildAuraException('Expenses for past months can only be submitted up to the 5th of the immediately following month.');
                }
            }

            String initialStatus = 'Pending HOD Approval';
            String userProfile = currentUser.Profile != null ? currentUser.Profile.Name : '';
            if (userProfile == 'Utkarsh HR') {
                initialStatus = 'Pending HR Approval';
            } else if (userProfile == 'System Administrator' || userProfile == 'Utkarsh Admin') {
                initialStatus = 'Pending ED Approval';
            }

            Expense__c exp = new Expense__c();
            exp.Subject__c = data.subject;
            exp.Travel_Start_Date__c = data.startDate;
            exp.Travel_End_Date__c = data.endDate;
            exp.Status__c = initialStatus;
            exp.Employee__c = currentUserId;
            exp.Employee_Level__c = currentUser.Employee_Level__c;
            exp.Approver__c = approverId;
            exp.User_Department__c = currentUser.Department != null ? currentUser.Department : null;
            exp.Submitted_Date__c = Date.today();

            insert exp;

            List<Expense_Line__c> linesToInsert = new List<Expense_Line__c>();
            if (data.lines != null && !data.lines.isEmpty()) {
                for (ExpenseLineWrapper lineData : data.lines) {
                    Expense_Line__c line = new Expense_Line__c();
                    line.Expense__c = exp.Id;
                    String expType = lineData.expenseType;
                    if (expType == 'Private Vehicle') {
                        expType = 'Own Vehicle';
                    }
                    line.Expense_Type__c = expType;
                    line.Amount__c = lineData.amount;
                    line.Approved_Amount__c = lineData.amount;
                    line.Start_Date__c = lineData.startDate;
                    line.End_Date__c = (lineData.expenseType == 'Lodging') ? lineData.endDate : null;
                    line.Justification__c = lineData.justification;
                    line.Miscellaneous_Cost__c = lineData.miscellaneousCost;
                    line.City__c = data.city;
                    line.City_Tier__c = data.cityTier;
                    line.Travel_Class__c = lineData.travelClass;
                    line.Vehicle_Type__c = lineData.vehicleType;
                    if (lineData.distanceKm != null) {
                        line.Distance_KM__c = lineData.distanceKm;
                    }

                    Boolean hasFiles = (lineData.files != null && !lineData.files.isEmpty()) 
                        || String.isNotBlank(lineData.documentId) 
                        || String.isNotBlank(lineData.base64Data);
                    if (hasFiles) {
                        line.Bill_Attached__c = true;
                    }
                    linesToInsert.add(line);
                }
                insert linesToInsert;

                List<ContentVersion> cvList = new List<ContentVersion>();
                List<ContentDocumentLink> cdlList = new List<ContentDocumentLink>();
                Set<Id> stagedDocIds = new Set<Id>();

                for (Integer i = 0; i < data.lines.size(); i++) {
                    ExpenseLineWrapper lineData = data.lines[i];
                    Id lineId = linesToInsert[i].Id;

                    // Handle multiple files in files array
                    if (lineData.files != null && !lineData.files.isEmpty()) {
                        for (FileWrapper fw : lineData.files) {
                            if (String.isNotBlank(fw.documentId)) {
                                try {
                                    Id docId = Id.valueOf(fw.documentId.trim());
                                    cdlList.add(new ContentDocumentLink(
                                        ContentDocumentId = docId,
                                        LinkedEntityId    = lineId,
                                        ShareType         = 'V',
                                        Visibility        = 'AllUsers'
                                    ));
                                    stagedDocIds.add(docId);
                                } catch (Exception ex) {
                                    System.debug(LoggingLevel.WARN, 'Invalid documentId: ' + fw.documentId);
                                }
                            } else if (String.isNotBlank(fw.base64Data)) {
                                ContentVersion cv = new ContentVersion();
                                cv.Title = fw.fileName;
                                String ext = String.isNotBlank(fw.extension) ? '.' + fw.extension : '';
                                cv.PathOnClient = fw.fileName + ext;
                                cv.VersionData = EncodingUtil.base64Decode(fw.base64Data);
                                cv.FirstPublishLocationId = lineId;
                                cvList.add(cv);
                            }
                        }
                    } else if (String.isNotBlank(lineData.documentId)) {
                        try {
                            Id docId = Id.valueOf(lineData.documentId.trim());
                            cdlList.add(new ContentDocumentLink(
                                ContentDocumentId = docId,
                                LinkedEntityId    = lineId,
                                ShareType         = 'V',
                                Visibility        = 'AllUsers'
                            ));
                            stagedDocIds.add(docId);
                        } catch (Exception ex) {
                            System.debug(LoggingLevel.WARN, 'Invalid documentId: ' + lineData.documentId);
                        }
                    } else if (String.isNotBlank(lineData.base64Data)) {
                        // Backward compatibility for single file
                        ContentVersion cv = new ContentVersion();
                        cv.Title = lineData.fileName;
                        String ext = String.isNotBlank(lineData.extension) ? '.' + lineData.extension : '';
                        cv.PathOnClient = lineData.fileName + ext;
                        cv.VersionData = EncodingUtil.base64Decode(lineData.base64Data);
                        cv.FirstPublishLocationId = lineId;
                        cvList.add(cv);
                    }
                }

                if (!cdlList.isEmpty()) {
                    insert cdlList;
                }
                if (!cvList.isEmpty()) {
                    insert cvList;
                }

                // Clean up staging links from user record
                if (!stagedDocIds.isEmpty()) {
                    List<ContentDocumentLink> stagingLinks = [
                        SELECT Id
                        FROM ContentDocumentLink
                        WHERE ContentDocumentId IN :stagedDocIds
                          AND LinkedEntityId = :UserInfo.getUserId()
                        WITH SYSTEM_MODE
                    ];
                    if (!stagingLinks.isEmpty()) {
                        try {
                            delete stagingLinks;
                        } catch (Exception e) {
                            System.debug(LoggingLevel.WARN, 'Staging link cleanup failed: ' + e.getMessage());
                        }
                    }
                }
            }

            // Move selected Private Vehicle lines to the newly created Expense__c
            if (data.privateVehicleLineIds != null && !data.privateVehicleLineIds.isEmpty()) {
                List<Expense_Line__c> existingLines = [
                    SELECT Id, Expense__c, Amount__c, Approved_Amount__c 
                    FROM Expense_Line__c 
                    WHERE Id IN :data.privateVehicleLineIds
                ];

                Set<Id> oldExpenseIds = new Set<Id>();
                for (Expense_Line__c el : existingLines) {
                    if (el.Expense__c != null) {
                        oldExpenseIds.add(el.Expense__c);
                    }
                    el.Expense__c = exp.Id;
                    el.Approved_Amount__c = el.Amount__c;
                }

                try {
                    ExpenseLineTriggerHandler.isLwcContext = true;
                    update existingLines;

                    // Delete old Expense__c records if they no longer have any Expense_Line__c records
                    if (!oldExpenseIds.isEmpty()) {
                        List<Expense__c> oldExpensesToDelete = [
                            SELECT Id FROM Expense__c 
                            WHERE Id IN :oldExpenseIds 
                              AND Id NOT IN (SELECT Expense__c FROM Expense_Line__c WHERE Expense__c IN :oldExpenseIds)
                        ];
                        if (!oldExpensesToDelete.isEmpty()) {
                            delete oldExpensesToDelete;
                        }
                    }
                } finally {
                    ExpenseLineTriggerHandler.isLwcContext = false;
                }
            }

            Expense__c savedExp = [SELECT Name FROM Expense__c WHERE Id = :exp.Id LIMIT 1];
            return savedExp.Name;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void discardFile(Id documentId) {
        if (documentId == null) {
            return;
        }
        try {
            delete [SELECT Id FROM ContentDocument WHERE Id = :documentId WITH SYSTEM_MODE LIMIT 1];
        } catch (Exception e) {
            throw buildAuraException('That file could not be removed: ' + e.getMessage());
        }
    }

    private static AuraHandledException buildAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    public class ExpensePayload {
        public String subject;
        public Date startDate;
        public Date endDate;
        public String city;
        public String cityTier;
        public List<ExpenseLineWrapper> lines;
        public List<Id> privateVehicleLineIds;
    }

    public class ExpenseLineWrapper {
        public String expenseType;
        public Decimal amount;
        public Date startDate;
        public Date endDate;
        public String justification;
        public String miscellaneousCost;
        public String travelClass;
        public String vehicleType;
        public Decimal distanceKm;
        public List<FileWrapper> files;
        // Backward compatibility properties
        public String fileName;
        public String base64Data;
        public String extension;
        public String documentId;
    }

    public class FileWrapper {
        public String fileName;
        public String base64Data;
        public String extension;
        public String fileType;
        public String documentId;
    }
}