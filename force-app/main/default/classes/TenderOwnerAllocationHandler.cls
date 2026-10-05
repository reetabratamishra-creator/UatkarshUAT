public with sharing class TenderOwnerAllocationHandler {

    private static final Map<String, String> DEPT_SHORT_CODE = new Map<String, String>{
        'High Mast Products'                         => 'HMS',
        'Steel Pipes Products'                       => 'SPP',
        'Polygonal Products'                         => 'PGP',
        'Crash Barrier Products'                     => 'CBP',
        'Steel Tubular Poles Products'               => 'STPP',
        'PVC Products'                               => 'PVC',
        'HDPE Products'                              => 'HPP',
        'Telecom Tower Products'                     => 'TETP',
        'Transmission Tower Products'                => 'TRTP',
        'Railway Electrification Structure Products' => 'RESP',
        'Pre Engineering Buildings Products'         => 'PEBP'
    };

    public static void handleAfterInsert(List<Tender__c> newTenders) {

        // Check Custom Metadata to determine whether the logic is enabled
        Trigger_Enable__mdt config = Trigger_Enable__mdt.getInstance(
            'TenderOwnerAllocationTrigger'
        );

        // If metadata record does not exist OR IsEnable__c is false,
        // do not execute the allocation logic.
        if (config == null || !config.IsEnable__c) {
            return;
        }

        List<Tender__c> relevant = new List<Tender__c>();
        Set<String> cities = new Set<String>();
        Set<String> states = new Set<String>();
        Set<String> depts = new Set<String>();

        for (Tender__c t : newTenders) {

            if (t.Department_Name__c != null) {

                relevant.add(t);

                if (t.City__c != null) {
                    cities.add(t.City__c);
                }

                if (t.State__c != null) {
                    states.add(t.State__c);
                }

                depts.add(t.Department_Name__c);
            }
        }

        if (relevant.isEmpty()) {
            return;
        }

        Map<String, User> userByDeptCity = new Map<String, User>();
        Map<String, User> userByDeptState = new Map<String, User>();

        // Find users based on Department + City
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

        // Find users based on Department + State
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

        // Trigger.new is read-only in after insert,
        // so create separate records for updating.
        List<Tender__c> toUpdate = new List<Tender__c>();

        for (Tender__c t : relevant) {

            Tender__c stub = new Tender__c(
                Id = t.Id
            );

            // Generate Tender Number
            String shortCode = DEPT_SHORT_CODE.containsKey(
                t.Department_Name__c
            )
                ? DEPT_SHORT_CODE.get(t.Department_Name__c)
                : '';

            stub.Tender_Number__c =
                'TEND/' +
                shortCode +
                '/' +
                t.AutoNumber__c;

            // Department + City
            String cityKey =
                t.Department_Name__c +
                '|' +
                t.City__c;

            // Department + State
            String stateKey =
                t.Department_Name__c +
                '|' +
                t.State__c;

            // Priority:
            // 1. Department + City
            // 2. Department + State
            if (userByDeptCity.containsKey(cityKey)) {

                stub.OwnerId =
                    userByDeptCity.get(cityKey).Id;

            } else if (userByDeptState.containsKey(stateKey)) {

                stub.OwnerId =
                    userByDeptState.get(stateKey).Id;
            }

            toUpdate.add(stub);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}