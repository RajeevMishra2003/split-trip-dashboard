/**
 * TripDashboardController
 * Backend controller for the tripExpenseDashboard LWC.
 * Handles Trip / Trip Member / Expense / Expense Share CRUD and
 * automatic recalculation of member balances + trip totals.
 */
public with sharing class TripDashboardController {

    /* ============================================================
     *  PICKLIST METADATA (reads real, active values from the org
     *  so the UI never guesses at restricted picklist values)
     * ============================================================ */

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getTripStatusOptions() {
        return getPicklistOptions(rajuser2003__Trip__c.rajuser2003__Status__c);
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getExpenseCategoryOptions() {
        return getPicklistOptions(rajuser2003__Expense__c.rajuser2003__Category__c);
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getSettlementOptions() {
        return getPicklistOptions(rajuser2003__expensesshare__c.rajuser2003__Settlement_Picklist__c);
    }

    private static List<PicklistOption> getPicklistOptions(Schema.SObjectField field) {
        List<PicklistOption> options = new List<PicklistOption>();
        Schema.DescribeFieldResult fieldResult = field.getDescribe();
        for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    /* ============================================================
     *  READ METHODS
     * ============================================================ */

    @AuraEnabled(cacheable=true)
    public static List<rajuser2003__Trip__c> getTrips() {
        return [
            SELECT Id, Name, rajuser2003__StartDate__c, rajuser2003__EndDate__c,
                   rajuser2003__Status__c, rajuser2003__NumberOfMember__c,
                   rajuser2003__TotalExpenses__c
            FROM rajuser2003__Trip__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static rajuser2003__Trip__c getTripDetail(Id tripId) {
        return [
            SELECT Id, Name, rajuser2003__StartDate__c, rajuser2003__EndDate__c,
                   rajuser2003__Status__c, rajuser2003__NumberOfMember__c,
                   rajuser2003__TotalExpenses__c, rajuser2003__expenses__c
            FROM rajuser2003__Trip__c
            WHERE Id = :tripId
            WITH USER_MODE
            LIMIT 1
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<rajuser2003__tripmember__c> getTripMembers(Id tripId) {
        return [
            SELECT Id, Name, rajuser2003__MemberName__c, rajuser2003__Contact__c,
                   rajuser2003__Contact__r.Name, rajuser2003__Balance__c,
                   rajuser2003__Totalpaid__c, rajuser2003__TotalShare__c
            FROM rajuser2003__tripmember__c
            WHERE rajuser2003__Trip__c = :tripId
            WITH USER_MODE
            ORDER BY rajuser2003__MemberName__c ASC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<rajuser2003__Expense__c> getTripExpenses(Id tripId) {
        return [
            SELECT Id, Name, rajuser2003__Amount__c, rajuser2003__Category__c,
                   rajuser2003__Expensesdate__c, rajuser2003__Paidby__c,
                   rajuser2003__Paidby__r.rajuser2003__MemberName__c, rajuser2003__Trip__c
            FROM rajuser2003__Expense__c
            WHERE rajuser2003__Trip__c = :tripId
            WITH USER_MODE
            ORDER BY rajuser2003__Expensesdate__c DESC, CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<rajuser2003__expensesshare__c> getExpenseShares(Id expenseId) {
        return [
            SELECT Id, Name, rajuser2003__tripmember__c,
                   rajuser2003__tripmember__r.rajuser2003__MemberName__c,
                   rajuser2003__Shareamount__c, rajuser2003__Share_Percentage__c,
                   rajuser2003__Paid__c, rajuser2003__Settlement_Picklist__c
            FROM rajuser2003__expensesshare__c
            WHERE rajuser2003__Expense__c = :expenseId
            WITH USER_MODE
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Contact> searchContacts(String searchTerm) {
        if (String.isBlank(searchTerm)) {
            return new List<Contact>();
        }
        String term = '%' + searchTerm + '%';
        return [
            SELECT Id, Name, Email
            FROM Contact
            WHERE Name LIKE :term
            WITH USER_MODE
            LIMIT 10
        ];
    }

    /* ============================================================
     *  CREATE METHODS
     * ============================================================ */

    @AuraEnabled
    public static Id createTrip(String tripName, Date startDate, Date endDate, String status) {
        try {
            rajuser2003__Trip__c t = new rajuser2003__Trip__c(
                Name = tripName,
                rajuser2003__StartDate__c = startDate,
                rajuser2003__EndDate__c = endDate,
                rajuser2003__Status__c = status,
                rajuser2003__NumberOfMember__c = 0,
                rajuser2003__TotalExpenses__c = 0
            );
            insert t;
            return t.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to create trip: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Id createTripMember(Id tripId, String memberName, Id contactId) {
        try {
            rajuser2003__tripmember__c m = new rajuser2003__tripmember__c(
                rajuser2003__Trip__c = tripId,
                rajuser2003__MemberName__c = memberName,
                rajuser2003__Contact__c = contactId,
                rajuser2003__Totalpaid__c = 0,
                rajuser2003__TotalShare__c = 0,
                rajuser2003__Balance__c = 0
            );
            insert m;
            refreshMemberCount(tripId);
            return m.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to add member: ' + e.getMessage());
        }
    }

    /**
     * Creates an Expense record and its related Expense Share records
     * (equal split or custom percentage split), then recalculates
     * every member's balance for the trip.
     */
    @AuraEnabled
    public static Id createExpense(Id tripId, String expenseName, Decimal amount, String category,
                                    Date expenseDate, Id paidById, List<Id> shareMemberIds,
                                    String splitType, List<Decimal> customPercentages) {
        try {
            if (shareMemberIds == null || shareMemberIds.isEmpty()) {
                throw new AuraHandledException('Select at least one member to split the expense with.');
            }

            rajuser2003__Expense__c exp = new rajuser2003__Expense__c(
                Name = expenseName,
                rajuser2003__Amount__c = amount,
                rajuser2003__Category__c = category,
                rajuser2003__Expensesdate__c = expenseDate,
                rajuser2003__Paidby__c = paidById,
                rajuser2003__Trip__c = tripId
            );
            insert exp;

            List<rajuser2003__expensesshare__c> shares = new List<rajuser2003__expensesshare__c>();
            Integer n = shareMemberIds.size();

            if (splitType == 'custom' && customPercentages != null && customPercentages.size() == n) {
                for (Integer i = 0; i < n; i++) {
                    Decimal pct = customPercentages[i];
                    Decimal shareAmt = (amount * pct / 100).setScale(2, System.RoundingMode.HALF_UP);
                    shares.add(new rajuser2003__expensesshare__c(
                        rajuser2003__Expense__c = exp.Id,
                        rajuser2003__tripmember__c = shareMemberIds[i],
                        rajuser2003__Shareamount__c = shareAmt,
                        rajuser2003__Share_Percentage__c = pct,
                        rajuser2003__Paid__c = false
                    ));
                }
            } else {
                // Equal split, last share absorbs rounding remainder
                Decimal each = (amount / n).setScale(2, System.RoundingMode.HALF_UP);
                Decimal pctEach = (100.0 / n).setScale(2, System.RoundingMode.HALF_UP);
                Decimal runningTotal = 0;
                for (Integer i = 0; i < n; i++) {
                    Decimal shareAmt = (i == n - 1) ? (amount - runningTotal) : each;
                    runningTotal += shareAmt;
                    shares.add(new rajuser2003__expensesshare__c(
                        rajuser2003__Expense__c = exp.Id,
                        rajuser2003__tripmember__c = shareMemberIds[i],
                        rajuser2003__Shareamount__c = shareAmt,
                        rajuser2003__Share_Percentage__c = pctEach,
                        rajuser2003__Paid__c = false
                    ));
                }
            }
            insert shares;

            recalcTripBalances(tripId);
            return exp.Id;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to create expense: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void markShareSettled(Id shareId, Id tripId, Boolean paid) {
        try {
            update new rajuser2003__expensesshare__c(
                Id = shareId,
                rajuser2003__Paid__c = paid
            );
            if (tripId != null) {
                recalcTripBalances(tripId);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Unable to update settlement: ' + e.getMessage());
        }
    }

    /**
     * Updates the Settlement_Picklist__c value on a share (using the org's real
     * active picklist values, cycled through from the LWC) and keeps the
     * Paid__c checkbox in sync based on whether the chosen value represents "paid".
     */
    @AuraEnabled
    public static void updateShareSettlement(Id shareId, Id tripId, String settlementValue) {
        try {
            Boolean isPaid = settlementValue != null && settlementValue.toLowerCase().contains('paid');
            update new rajuser2003__expensesshare__c(
                Id = shareId,
                rajuser2003__Settlement_Picklist__c = settlementValue,
                rajuser2003__Paid__c = isPaid
            );
            if (tripId != null) {
                recalcTripBalances(tripId);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Unable to update settlement: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteExpense(Id expenseId, Id tripId) {
        try {
            delete new rajuser2003__Expense__c(Id = expenseId);
            recalcTripBalances(tripId);
        } catch (Exception e) {
            throw new AuraHandledException('Unable to delete expense: ' + e.getMessage());
        }
    }

    /* ============================================================
     *  INTERNAL HELPERS
     * ============================================================ */

    private static void refreshMemberCount(Id tripId) {
        Integer cnt = [
            SELECT COUNT()
            FROM rajuser2003__tripmember__c
            WHERE rajuser2003__Trip__c = :tripId
        ];
        update new rajuser2003__Trip__c(
            Id = tripId,
            rajuser2003__NumberOfMember__c = cnt
        );
    }

    /**
     * Recomputes Totalpaid / TotalShare / Balance on every member of the trip,
     * and refreshes the Trip's rollup of total expenses.
     */
    @AuraEnabled
    public static void recalcTripBalances(Id tripId) {
        List<rajuser2003__tripmember__c> members = [
            SELECT Id, rajuser2003__Totalpaid__c, rajuser2003__TotalShare__c, rajuser2003__Balance__c
            FROM rajuser2003__tripmember__c
            WHERE rajuser2003__Trip__c = :tripId
        ];
        if (members.isEmpty()) {
            return;
        }
        Map<Id, rajuser2003__tripmember__c> memberMap = new Map<Id, rajuser2003__tripmember__c>(members);
        for (rajuser2003__tripmember__c m : memberMap.values()) {
            m.rajuser2003__Totalpaid__c = 0;
            m.rajuser2003__TotalShare__c = 0;
        }

        List<rajuser2003__Expense__c> expenses = [
            SELECT Id, rajuser2003__Amount__c, rajuser2003__Paidby__c
            FROM rajuser2003__Expense__c
            WHERE rajuser2003__Trip__c = :tripId
        ];

        Decimal totalExpenses = 0;
        Set<Id> expenseIds = new Set<Id>();
        for (rajuser2003__Expense__c e : expenses) {
            totalExpenses += (e.rajuser2003__Amount__c == null ? 0 : e.rajuser2003__Amount__c);
            expenseIds.add(e.Id);
            if (memberMap.containsKey(e.rajuser2003__Paidby__c)) {
                memberMap.get(e.rajuser2003__Paidby__c).rajuser2003__Totalpaid__c += e.rajuser2003__Amount__c;
            }
        }

        if (!expenseIds.isEmpty()) {
            List<rajuser2003__expensesshare__c> shares = [
                SELECT rajuser2003__tripmember__c, rajuser2003__Shareamount__c
                FROM rajuser2003__expensesshare__c
                WHERE rajuser2003__Expense__c IN :expenseIds
            ];
            for (rajuser2003__expensesshare__c s : shares) {
                if (memberMap.containsKey(s.rajuser2003__tripmember__c)) {
                    memberMap.get(s.rajuser2003__tripmember__c).rajuser2003__TotalShare__c += s.rajuser2003__Shareamount__c;
                }
            }
        }

        for (rajuser2003__tripmember__c m : memberMap.values()) {
            m.rajuser2003__Balance__c = (m.rajuser2003__Totalpaid__c == null ? 0 : m.rajuser2003__Totalpaid__c)
                                       - (m.rajuser2003__TotalShare__c == null ? 0 : m.rajuser2003__TotalShare__c);
        }
        update memberMap.values();

        update new rajuser2003__Trip__c(
            Id = tripId,
            rajuser2003__TotalExpenses__c = totalExpenses
        );
    }
}