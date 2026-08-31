@IsTest
private class TripDashboardControllerTest {

    // =========================================================
    // HELPER: Get an active picklist value
    // =========================================================
    private static String getActivePicklistValue(
        Schema.SObjectField fieldToken
    ) {
        for (
            Schema.PicklistEntry entry :
            fieldToken.getDescribe().getPicklistValues()
        ) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }


    // =========================================================
    // HELPER: Create Test Trip
    // =========================================================
    private static rajuser2003__Trip__c createTestTrip() {

        String statusValue =
            getActivePicklistValue(
                rajuser2003__Trip__c.rajuser2003__Status__c
            );

        rajuser2003__Trip__c trip =
            new rajuser2003__Trip__c(
                Name = 'Test Goa Trip',
                rajuser2003__StartDate__c = Date.today(),
                rajuser2003__EndDate__c = Date.today().addDays(5),
                rajuser2003__Status__c = statusValue,
                rajuser2003__NumberOfMember__c = 0,
                rajuser2003__TotalExpenses__c = 0
            );

        insert trip;

        return trip;
    }


    // =========================================================
    // TEST 1: Picklist Methods
    // =========================================================
    @IsTest
    static void testPicklistMethods() {

        Test.startTest();

        List<TripDashboardController.PicklistOption> tripStatuses =
            TripDashboardController.getTripStatusOptions();

        List<TripDashboardController.PicklistOption> categories =
            TripDashboardController.getExpenseCategoryOptions();

        List<TripDashboardController.PicklistOption> settlements =
            TripDashboardController.getSettlementOptions();

        Test.stopTest();

        System.assertNotEquals(
            null,
            tripStatuses,
            'Trip status options should not be null'
        );

        System.assertNotEquals(
            null,
            categories,
            'Expense category options should not be null'
        );

        System.assertNotEquals(
            null,
            settlements,
            'Settlement options should not be null'
        );
    }


    // =========================================================
    // TEST 2: Create Trip + Get Trips + Get Trip Detail
    // =========================================================
    @IsTest
    static void testCreateAndGetTrip() {

        String statusValue =
            getActivePicklistValue(
                rajuser2003__Trip__c.rajuser2003__Status__c
            );

        Test.startTest();

        Id tripId =
            TripDashboardController.createTrip(
                'Test Trip',
                Date.today(),
                Date.today().addDays(7),
                statusValue
            );

        List<rajuser2003__Trip__c> trips =
            TripDashboardController.getTrips();

        rajuser2003__Trip__c detail =
            TripDashboardController.getTripDetail(tripId);

        Test.stopTest();

        System.assertNotEquals(
            null,
            tripId,
            'Trip should be created'
        );

        System.assert(
            trips.size() > 0,
            'getTrips should return trips'
        );

        System.assertEquals(
            tripId,
            detail.Id,
            'Returned trip should match created trip'
        );

        System.assertEquals(
            'Test Trip',
            detail.Name
        );

        System.assertEquals(
            Date.today(),
            detail.rajuser2003__StartDate__c
        );

        System.assertEquals(
            Date.today().addDays(7),
            detail.rajuser2003__EndDate__c
        );

        System.assertEquals(
            0,
            detail.rajuser2003__NumberOfMember__c
        );

        System.assertEquals(
            0,
            detail.rajuser2003__TotalExpenses__c
        );
    }


    // =========================================================
    // TEST 3: Create Members + Get Members
    // =========================================================
    @IsTest
static void testCreateMembers() {

    rajuser2003__Trip__c trip =
        createTestTrip();

    Test.startTest();

    Id member1Id =
        TripDashboardController.createTripMember(
            trip.Id,
            'Rajeev',
            null
        );

    Id member2Id =
        TripDashboardController.createTripMember(
            trip.Id,
            'Rahul',
            null
        );

    List<rajuser2003__tripmember__c> members =
        TripDashboardController.getTripMembers(
            trip.Id
        );

    Test.stopTest();

    System.assertNotEquals(
        null,
        member1Id,
        'First member should be created'
    );

    System.assertNotEquals(
        null,
        member2Id,
        'Second member should be created'
    );

    System.assertEquals(
        2,
        members.size(),
        'Two members should be returned'
    );

    Set<String> memberNames =
        new Set<String>();

    for (
        rajuser2003__tripmember__c member :
        members
    ) {

        memberNames.add(
            member.rajuser2003__MemberName__c
        );

        System.assertNotEquals(
            null,
            member.Id,
            'Member Id should exist'
        );

        System.assertEquals(
            0,
            member.rajuser2003__Totalpaid__c,
            'Initial total paid should be zero'
        );

        System.assertEquals(
            0,
            member.rajuser2003__TotalShare__c,
            'Initial total share should be zero'
        );

        System.assertEquals(
            0,
            member.rajuser2003__Balance__c,
            'Initial balance should be zero'
        );
    }

    System.assert(
        memberNames.contains('Rajeev'),
        'Rajeev should be present'
    );

    System.assert(
        memberNames.contains('Rahul'),
        'Rahul should be present'
    );

    // Query the Trip Member records separately
    // when we need to verify Trip__c.
    List<rajuser2003__tripmember__c> queriedMembers =
        [
            SELECT Id,
                   rajuser2003__Trip__c,
                   rajuser2003__MemberName__c
            FROM rajuser2003__tripmember__c
            WHERE Id IN :new Set<Id>{
                member1Id,
                member2Id
            }
        ];

    System.assertEquals(
        2,
        queriedMembers.size(),
        'Both members should belong to the created trip'
    );

    for (
        rajuser2003__tripmember__c member :
        queriedMembers
    ) {

        System.assertEquals(
            trip.Id,
            member.rajuser2003__Trip__c,
            'Member should belong to the correct trip'
        );
    }

    rajuser2003__Trip__c updatedTrip =
        [
            SELECT Id,
                   rajuser2003__NumberOfMember__c
            FROM rajuser2003__Trip__c
            WHERE Id = :trip.Id
        ];

    System.assertEquals(
        2,
        updatedTrip.rajuser2003__NumberOfMember__c,
        'Trip should contain two members'
    );
}


    // =========================================================
    // TEST 4: Search Contacts
    // =========================================================
    @IsTest
    static void testSearchContacts() {

        Contact testContact =
            new Contact(
                FirstName = 'Test',
                LastName = 'RajeevContact',
                Email = 'test.rajeev@example.com'
            );

        insert testContact;

        Test.startTest();

        List<Contact> contacts =
            TripDashboardController.searchContacts(
                'RajeevContact'
            );

        List<Contact> emptyResult =
            TripDashboardController.searchContacts(
                ''
            );

        Test.stopTest();

        System.assert(
            contacts.size() > 0,
            'Contact should be found'
        );

        System.assertEquals(
            0,
            emptyResult.size(),
            'Blank search should return empty result'
        );

        System.assertEquals(
            testContact.Id,
            contacts[0].Id
        );
    }


    // =========================================================
    // TEST 5: Equal Split Expense
    // =========================================================
    @IsTest
    static void testCreateEqualSplitExpense() {

        String categoryValue =
            getActivePicklistValue(
                rajuser2003__Expense__c.rajuser2003__Category__c
            );

        rajuser2003__Trip__c trip =
            createTestTrip();

        Id member1Id =
            TripDashboardController.createTripMember(
                trip.Id,
                'Rajeev',
                null
            );

        Id member2Id =
            TripDashboardController.createTripMember(
                trip.Id,
                'Rahul',
                null
            );

        List<Id> memberIds =
            new List<Id>{
                member1Id,
                member2Id
            };

        Test.startTest();

        Id expenseId =
            TripDashboardController.createExpense(
                trip.Id,
                'Hotel',
                1000,
                categoryValue,
                Date.today(),
                member1Id,
                memberIds,
                'equal',
                null
            );

        List<rajuser2003__Expense__c> expenses =
            TripDashboardController.getTripExpenses(
                trip.Id
            );

        List<rajuser2003__expensesshare__c> shares =
            TripDashboardController.getExpenseShares(
                expenseId
            );

        Test.stopTest();

        System.assertNotEquals(
            null,
            expenseId,
            'Expense should be created'
        );

        System.assertEquals(
            1,
            expenses.size(),
            'One expense should exist'
        );

        System.assertEquals(
            2,
            shares.size(),
            'Two expense shares should exist'
        );

        Decimal totalShare = 0;

        for (
            rajuser2003__expensesshare__c share :
            shares
        ) {
            totalShare +=
                share.rajuser2003__Shareamount__c;

            System.assertEquals(
                false,
                share.rajuser2003__Paid__c
            );
        }

        System.assertEquals(
            1000,
            totalShare,
            'Total shares must equal expense amount'
        );

        rajuser2003__Expense__c expense =
            expenses[0];

        System.assertEquals(
            'Hotel',
            expense.Name
        );

        System.assertEquals(
            1000,
            expense.rajuser2003__Amount__c
        );
    }


    // =========================================================
    // TEST 6: Custom Percentage Split
    // =========================================================
    @IsTest
    static void testCreateCustomSplitExpense() {

        String categoryValue =
            getActivePicklistValue(
                rajuser2003__Expense__c.rajuser2003__Category__c
            );

        rajuser2003__Trip__c trip =
            createTestTrip();

        Id member1Id =
            TripDashboardController.createTripMember(
                trip.Id,
                'Rajeev',
                null
            );

        Id member2Id =
            TripDashboardController.createTripMember(
                trip.Id,
                'Rahul',
                null
            );

        List<Id> memberIds =
            new List<Id>{
                member1Id,
                member2Id
            };

        List<Decimal> percentages =
            new List<Decimal>{
                70,
                30
            };

        Test.startTest();

        Id expenseId =
            TripDashboardController.createExpense(
                trip.Id,
                'Food',
                1000,
                categoryValue,
                Date.today(),
                member1Id,
                memberIds,
                'custom',
                percentages
            );

        List<rajuser2003__expensesshare__c> shares =
            TripDashboardController.getExpenseShares(
                expenseId
            );

        Test.stopTest();

        System.assertNotEquals(
            null,
            expenseId
        );

        System.assertEquals(
            2,
            shares.size()
        );

        Decimal totalAmount = 0;

        for (
            rajuser2003__expensesshare__c share :
            shares
        ) {
            totalAmount +=
                share.rajuser2003__Shareamount__c;
        }

        System.assertEquals(
            1000,
            totalAmount,
            'Custom shares must equal total expense'
        );

        for (
            rajuser2003__expensesshare__c share :
            shares
        ) {

            if (
                share.rajuser2003__tripmember__c ==
                member1Id
            ) {

                System.assertEquals(
                    70,
                    share.rajuser2003__Share_Percentage__c
                );

                System.assertEquals(
                    700,
                    share.rajuser2003__Shareamount__c
                );
            }

            if (
                share.rajuser2003__tripmember__c ==
                member2Id
            ) {

                System.assertEquals(
                    30,
                    share.rajuser2003__Share_Percentage__c
                );

                System.assertEquals(
                    300,
                    share.rajuser2003__Shareamount__c
                );
            }
        }
    }


    // =========================================================
    // TEST 7: Recalculate Balances
    // =========================================================
    @IsTest
    static void testRecalculateBalances() {

        String categoryValue =
            getActivePicklistValue(
                rajuser2003__Expense__c.rajuser2003__Category__c
            );

        rajuser2003__Trip__c trip =
            createTestTrip();

        Id member1Id =
            TripDashboardController.createTripMember(
                trip.Id,
                'Rajeev',
                null
            );

        Id member2Id =
            TripDashboardController.createTripMember(
                trip.Id,
                'Rahul',
                null
            );

        List<Id> memberIds =
            new List<Id>{
                member1Id,
                member2Id
            };

        Test.startTest();

        TripDashboardController.createExpense(
            trip.Id,
            'Hotel',
            1000,
            categoryValue,
            Date.today(),
            member1Id,
            memberIds,
            'equal',
            null
        );

        TripDashboardController.recalcTripBalances(
            trip.Id
        );

        Test.stopTest();

        Map<Id, rajuser2003__tripmember__c> members =
            new Map<Id, rajuser2003__tripmember__c>(
                [
                    SELECT Id,
                           rajuser2003__Totalpaid__c,
                           rajuser2003__TotalShare__c,
                           rajuser2003__Balance__c
                    FROM rajuser2003__tripmember__c
                    WHERE Id IN :memberIds
                ]
            );

        rajuser2003__tripmember__c rajeev =
            members.get(member1Id);

        rajuser2003__tripmember__c rahul =
            members.get(member2Id);

        System.assertEquals(
            1000,
            rajeev.rajuser2003__Totalpaid__c
        );

        System.assertEquals(
            500,
            rajeev.rajuser2003__TotalShare__c
        );

        System.assertEquals(
            500,
            rajeev.rajuser2003__Balance__c
        );

        System.assertEquals(
            0,
            rahul.rajuser2003__Totalpaid__c
        );

        System.assertEquals(
            500,
            rahul.rajuser2003__TotalShare__c
        );

        System.assertEquals(
            -500,
            rahul.rajuser2003__Balance__c
        );

        rajuser2003__Trip__c updatedTrip =
            [
                SELECT Id,
                       rajuser2003__TotalExpenses__c
                FROM rajuser2003__Trip__c
                WHERE Id = :trip.Id
            ];

        System.assertEquals(
            1000,
            updatedTrip.rajuser2003__TotalExpenses__c
        );
    }


    // =========================================================
    // TEST 8: Settlement
    // =========================================================
    @IsTest
    static void testSettlement() {

        String categoryValue =
            getActivePicklistValue(
                rajuser2003__Expense__c.rajuser2003__Category__c
            );

        rajuser2003__Trip__c trip =
            createTestTrip();

        Id member1Id =
            TripDashboardController.createTripMember(
                trip.Id,
                'Rajeev',
                null
            );

        Id member2Id =
            TripDashboardController.createTripMember(
                trip.Id,
                'Rahul',
                null
            );

        List<Id> memberIds =
            new List<Id>{
                member1Id,
                member2Id
            };

        Id expenseId =
            TripDashboardController.createExpense(
                trip.Id,
                'Dinner',
                1000,
                categoryValue,
                Date.today(),
                member1Id,
                memberIds,
                'equal',
                null
            );

        List<rajuser2003__expensesshare__c> shares =
            [
                SELECT Id,
                       rajuser2003__tripmember__c,
                       rajuser2003__Paid__c,
                       rajuser2003__Settlement_Picklist__c
                FROM rajuser2003__expensesshare__c
                WHERE rajuser2003__Expense__c = :expenseId
            ];

        System.assertEquals(
            2,
            shares.size()
        );

        Id shareId =
            shares[0].Id;

        Test.startTest();

        TripDashboardController.markShareSettled(
            shareId,
            trip.Id,
            true
        );

        Test.stopTest();

        rajuser2003__expensesshare__c updatedShare =
            [
                SELECT Id,
                       rajuser2003__Paid__c
                FROM rajuser2003__expensesshare__c
                WHERE Id = :shareId
            ];

        System.assertEquals(
            true,
            updatedShare.rajuser2003__Paid__c,
            'Share should be marked as paid'
        );
    }


    // =========================================================
    // TEST 9: Delete Expense
    // =========================================================
    @IsTest
    static void testDeleteExpense() {

        String categoryValue =
            getActivePicklistValue(
                rajuser2003__Expense__c.rajuser2003__Category__c
            );

        rajuser2003__Trip__c trip =
            createTestTrip();

        Id member1Id =
            TripDashboardController.createTripMember(
                trip.Id,
                'Rajeev',
                null
            );

        Id member2Id =
            TripDashboardController.createTripMember(
                trip.Id,
                'Rahul',
                null
            );

        List<Id> memberIds =
            new List<Id>{
                member1Id,
                member2Id
            };

        Id expenseId =
            TripDashboardController.createExpense(
                trip.Id,
                'Transport',
                500,
                categoryValue,
                Date.today(),
                member1Id,
                memberIds,
                'equal',
                null
            );

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM rajuser2003__Expense__c
                WHERE Id = :expenseId
            ]
        );

        Test.startTest();

        TripDashboardController.deleteExpense(
            expenseId,
            trip.Id
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM rajuser2003__Expense__c
                WHERE Id = :expenseId
            ]
        );

        rajuser2003__Trip__c updatedTrip =
            [
                SELECT Id,
                       rajuser2003__TotalExpenses__c
                FROM rajuser2003__Trip__c
                WHERE Id = :trip.Id
            ];

        System.assertEquals(
            0,
            updatedTrip.rajuser2003__TotalExpenses__c
        );
    }


    // =========================================================
    // TEST 10: Expense Without Members
    // =========================================================
    @IsTest
    static void testCreateExpenseWithoutMembers() {

        String categoryValue =
            getActivePicklistValue(
                rajuser2003__Expense__c.rajuser2003__Category__c
            );

        rajuser2003__Trip__c trip =
            createTestTrip();

        Boolean exceptionThrown = false;

        Test.startTest();

        try {

            TripDashboardController.createExpense(
                trip.Id,
                'Invalid Expense',
                500,
                categoryValue,
                Date.today(),
                null,
                new List<Id>(),
                'equal',
                null
            );

        } catch (AuraHandledException e) {

            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Exception should be thrown when no members are selected'
        );
    }
}
// =========================================================trigger pipeline
