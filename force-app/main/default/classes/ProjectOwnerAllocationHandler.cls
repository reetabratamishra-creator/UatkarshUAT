public with sharing class ProjectOwnerAllocationHandler {
    private static final Map<String, String> DEPT_SHORT_CODE = new Map<String, String>{
        'High Mast & Polygonal'              => 'HMP',
        'Steel Pipes'                        => 'SP',
        'Polygonal Products'                 => 'PGP',
        'Crash Barrier'                       => 'CB',
        'Steel Tubular Poles'                => 'STP',
        'Polymer'                            => 'PVC',
        'HDPE'                               => 'HDPE',
        'Transmission & Telecom Tower'       => 'TTT',
        'Solar Structure'                    => 'SS',
        'Railway Electrification Structure'  => 'CORE',
        'Pre Engineering Building'           => 'PEB'
    };

    public static void handleAfterInsert(List<Project__c> newProjects) {
        
         Trigger_Enable__mdt config = Trigger_Enable__mdt.getInstance('ProjectOwnerAllocationTrigger');
        if (config == null || !config.IsEnable__c) {
             System.debug('OpportunityTriggerHandler: trigger disabled via metadata - skipping.');
            return;
        }
        
        
        List<Project__c> relevant = new List<Project__c>();
        Set<String> cities = new Set<String>();
        Set<String> states = new Set<String>();
        Set<String> depts = new Set<String>();

        for (Project__c p : newProjects) {
            if (p.Department_Name__c != null) {
                relevant.add(p);
                if (p.City_Picklist__c != null) cities.add(p.City_Picklist__c);
                if (p.State_Picklist__c != null) states.add(p.State_Picklist__c);
                depts.add(p.Department_Name__c);
            }
        }
        if (relevant.isEmpty()) return;

        Map<String, User> userByDeptCity = new Map<String, User>();
        Map<String, User> userByDeptState = new Map<String, User>();

        if (!cities.isEmpty()) {
            for (User u : [
                SELECT Id, Departments__c, City__c, State__c
                FROM User
                WHERE Departments__c IN :depts
                AND City__c IN :cities
            ]) {
                String key = u.Departments__c + '|' + u.City__c;
                if (!userByDeptCity.containsKey(key)) {
                    userByDeptCity.put(key, u);
                }
            }
        }
        if (!states.isEmpty()) {
            for (User u : [
                SELECT Id, Departments__c, City__c, State__c
                FROM User
                WHERE Departments__c IN :depts
                AND State__c IN :states
            ]) {
                String key = u.Departments__c + '|' + u.State__c;
                if (!userByDeptState.containsKey(key)) {
                    userByDeptState.put(key, u);
                }
            }
        }

        // Separate stub list — Trigger.new is read-only in after insert
        List<Project__c> toUpdate = new List<Project__c>();

        for (Project__c p : relevant) {
            Project__c stub = new Project__c(Id = p.Id);

            String shortCode = DEPT_SHORT_CODE.containsKey(p.Department_Name__c)
                ? DEPT_SHORT_CODE.get(p.Department_Name__c)
                : '';
            stub.Project_Number__c = 'PROJ/' + shortCode + '/' + p.AutoNumber__c;

            String cityKey = p.Department_Name__c + '|' + p.City_Picklist__c;
            String stateKey = p.Department_Name__c + '|' + p.State_Picklist__c;

            if (userByDeptCity.containsKey(cityKey)) {
                stub.OwnerId = userByDeptCity.get(cityKey).Id;
            } else if (userByDeptState.containsKey(stateKey)) {
                stub.OwnerId = userByDeptState.get(stateKey).Id;
            }

            toUpdate.add(stub);
        }

        update toUpdate;
    }
}