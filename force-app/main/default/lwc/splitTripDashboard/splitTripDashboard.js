import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
 
import getTrips from '@salesforce/apex/TripDashboardController.getTrips';
import getTripDetail from '@salesforce/apex/TripDashboardController.getTripDetail';
import getTripMembers from '@salesforce/apex/TripDashboardController.getTripMembers';
import getTripExpenses from '@salesforce/apex/TripDashboardController.getTripExpenses';
import getExpenseShares from '@salesforce/apex/TripDashboardController.getExpenseShares';
import searchContacts from '@salesforce/apex/TripDashboardController.searchContacts';
import createTrip from '@salesforce/apex/TripDashboardController.createTrip';
import createTripMember from '@salesforce/apex/TripDashboardController.createTripMember';
import createExpense from '@salesforce/apex/TripDashboardController.createExpense';
import deleteExpense from '@salesforce/apex/TripDashboardController.deleteExpense';
import updateShareSettlement from '@salesforce/apex/TripDashboardController.updateShareSettlement';
import getTripStatusOptions from '@salesforce/apex/TripDashboardController.getTripStatusOptions';
import getExpenseCategoryOptions from '@salesforce/apex/TripDashboardController.getExpenseCategoryOptions';
import getSettlementOptions from '@salesforce/apex/TripDashboardController.getSettlementOptions';
 
const SPLIT_OPTIONS = [
    { label: 'Split Equally', value: 'equal' },
    { label: 'Custom Percentage', value: 'custom' }
];
 
export default class TripExpenseDashboard extends LightningElement {
    /* ---------- configurable via App Builder ---------- */
    @api cardTitle = 'Trip Split Dashboard';
 
    /* ---------- reference data (loaded live from org picklist metadata) ---------- */
    @track statusOptions = [];
    @track categoryOptions = [];
    @track settlementOptions = [];
    splitOptions = SPLIT_OPTIONS;
 
    /* ---------- core state ---------- */
    @track trips = [];
    @track selectedTripId;
    @track tripDetail;
    @track members = [];
    @track expenses = [];
    @track isLoading = false;
    @track searchTerm = '';
 
    wiredTripsResult;
    wiredMembersResult;
    wiredExpensesResult;
 
    /* ---------- modal visibility ---------- */
    @track showNewTripModal = false;
    @track showAddMemberModal = false;
    @track showAddExpenseModal = false;
    @track showExpenseDetail = false;
 
    /* ---------- new trip form ---------- */
    @track newTrip = { name: '', startDate: '', endDate: '', status: 'Planned' };
 
    /* ---------- new member form ---------- */
    @track newMember = { name: '', contactId: '', contactName: '' };
    @track contactResults = [];
    contactSearchTimeout;
 
    /* ---------- new expense form ---------- */
    @track newExpense = {
        name: '',
        amount: null,
        category: 'Food',
        date: '',
        paidById: '',
        splitType: 'equal'
    };
    @track selectedShareMemberIds = [];
    @track customShareRows = [];
 
    /* ---------- expense detail ---------- */
    @track activeExpense;
    @track activeExpenseShares = [];
 
    /* ===================================================================
     *  WIRES
     * =================================================================== */
    @wire(getTripStatusOptions)
    wiredStatusOptions({ data, error }) {
        if (data) {
            this.statusOptions = data;
        } else if (error) {
            this.showError('Error loading Status picklist', error);
        }
    }
 
    @wire(getExpenseCategoryOptions)
    wiredCategoryOptions({ data, error }) {
        if (data) {
            this.categoryOptions = data;
        } else if (error) {
            this.showError('Error loading Category picklist', error);
        }
    }
 
    @wire(getSettlementOptions)
    wiredSettlementOptions({ data, error }) {
        if (data) {
            this.settlementOptions = data;
        } else if (error) {
            this.showError('Error loading Settlement picklist', error);
        }
    }
 
    @wire(getTrips)
    wiredTrips(result) {
        this.wiredTripsResult = result;
        if (result.data) {
            this.trips = result.data.map((t) => ({
                ...t,
                label: t.Name
            }));
            if (!this.selectedTripId && this.trips.length > 0) {
                this.selectedTripId = this.trips[0].Id;
                this.loadTripData();
            }
        } else if (result.error) {
            this.showError('Error loading trips', result.error);
        }
    }
 
    @wire(getTripMembers, { tripId: '$selectedTripId' })
    wiredMembers(result) {
        this.wiredMembersResult = result;
        if (result.data) {
            this.members = result.data.map((m) => this.decorateMember(m));
        } else if (result.error) {
            this.showError('Error loading members', result.error);
        }
    }
 
    @wire(getTripExpenses, { tripId: '$selectedTripId' })
    wiredExpenses(result) {
        this.wiredExpensesResult = result;
        if (result.data) {
            this.expenses = result.data.map((e) => {
                const colorKey = this.getCategoryColorKey(e.rajuser2003__Category__c);
                return {
                    ...e,
                    formattedAmount: this.formatCurrency(e.rajuser2003__Amount__c),
                    paidByName: e.rajuser2003__Paidby__r
                        ? e.rajuser2003__Paidby__r.rajuser2003__MemberName__c
                        : '—',
                    categoryIcon: this.getCategoryIcon(e.rajuser2003__Category__c),
                    categoryColorClass: `expense-cat-badge cat-${colorKey}`,
                    cardClass: `expense-card fade-in-item border-${colorKey}`
                };
            });
        } else if (result.error) {
            this.showError('Error loading expenses', result.error);
        }
    }
 
    /* ===================================================================
     *  DERIVED GETTERS
     * =================================================================== */
    get hasTrips() {
        return this.trips && this.trips.length > 0;
    }
 
    get decoratedTrips() {
        return this.trips.map((t) => ({
            ...t,
            sidebarClass: t.Id === this.selectedTripId
                ? 'sidebar-trip sidebar-trip-active'
                : 'sidebar-trip'
        }));
    }
 
    /* ---------- SEARCH (topbar) ---------- */
    handleSearchChange(event) {
        this.searchTerm = event.target.value || '';
    }
 
    get filteredMembers() {
        const term = this.searchTerm.trim().toLowerCase();
        if (!term) {
            return this.members;
        }
        return this.members.filter((m) =>
            (m.rajuser2003__MemberName__c || '').toLowerCase().includes(term)
        );
    }
 
    get filteredExpenses() {
        const term = this.searchTerm.trim().toLowerCase();
        if (!term) {
            return this.expenses;
        }
        return this.expenses.filter((e) => {
            const name = (e.Name || '').toLowerCase();
            const cat = (e.rajuser2003__Category__c || '').toLowerCase();
            const payer = (e.paidByName || '').toLowerCase();
            return name.includes(term) || cat.includes(term) || payer.includes(term);
        });
    }
 
    get hasFilteredMembers() {
        return this.filteredMembers.length > 0;
    }
 
    get hasFilteredExpenses() {
        return this.filteredExpenses.length > 0;
    }
 
 
    get hasSelectedTrip() {
        return !!this.selectedTripId;
    }
 
    get hasMembers() {
        return this.members && this.members.length > 0;
    }
 
    get hasExpenses() {
        return this.expenses && this.expenses.length > 0;
    }
 
    get memberCount() {
        return this.members ? this.members.length : 0;
    }
 
    get totalExpensesFormatted() {
        const trip = this.trips.find((t) => t.Id === this.selectedTripId);
        return trip ? this.formatCurrency(trip.rajuser2003__TotalExpenses__c) : '₹0.00';
    }
 
    get selectedTripName() {
        const trip = this.trips.find((t) => t.Id === this.selectedTripId);
        return trip ? trip.Name : '';
    }
 
    get selectedTripStatus() {
        const trip = this.trips.find((t) => t.Id === this.selectedTripId);
        return trip ? trip.rajuser2003__Status__c : '';
    }
 
    get selectedTripDates() {
        const trip = this.trips.find((t) => t.Id === this.selectedTripId);
        if (!trip) return '';
        const s = trip.rajuser2003__StartDate__c;
        const e = trip.rajuser2003__EndDate__c;
        if (s && e) return `${s} to ${e}`;
        return s || e || 'Dates not set';
    }
 
    get isEqualSplit() {
        return this.newExpense.splitType === 'equal';
    }
 
    get isCustomSplit() {
        return this.newExpense.splitType === 'custom';
    }
 
    get memberCheckboxOptions() {
        return this.members.map((m) => ({
            label: m.rajuser2003__MemberName__c,
            value: m.Id
        }));
    }
 
    get payerOptions() {
        return this.members.map((m) => ({
            label: m.rajuser2003__MemberName__c,
            value: m.Id
        }));
    }
 
    get customSplitTotalPct() {
        return this.customShareRows.reduce((sum, r) => sum + (Number(r.percentage) || 0), 0);
    }
 
    get customSplitTotalValid() {
        return Math.abs(this.customSplitTotalPct - 100) < 0.01;
    }
 
    /* ---------- SETTLE UP (debt simplification) ---------- */
    get settleUpTransactions() {
        const balances = this.members
            .map((m) => ({
                id: m.Id,
                name: m.rajuser2003__MemberName__c,
                initials: m.initials,
                balance: Number(m.rajuser2003__Balance__c || 0)
            }))
            .filter((m) => Math.abs(m.balance) > 0.005);
 
        const creditors = balances
            .filter((b) => b.balance > 0)
            .map((b) => ({ ...b }))
            .sort((a, b) => b.balance - a.balance);
        const debtors = balances
            .filter((b) => b.balance < 0)
            .map((b) => ({ ...b, balance: -b.balance }))
            .sort((a, b) => b.balance - a.balance);
 
        const transactions = [];
        let ci = 0;
        let di = 0;
        while (ci < creditors.length && di < debtors.length) {
            const c = creditors[ci];
            const d = debtors[di];
            const amt = Math.min(c.balance, d.balance);
            if (amt > 0.005) {
                transactions.push({
                    id: `${d.id}-${c.id}`,
                    fromName: d.name,
                    fromInitials: d.initials,
                    toName: c.name,
                    toInitials: c.initials,
                    amount: this.formatCurrency(amt)
                });
            }
            c.balance -= amt;
            d.balance -= amt;
            if (c.balance < 0.005) ci++;
            if (d.balance < 0.005) di++;
        }
        return transactions;
    }
 
    get hasSettleUpTransactions() {
        return this.settleUpTransactions.length > 0;
    }
 
    /* ---------- INSIGHTS (category spend breakdown) ---------- */
    get categoryBreakdown() {
        if (!this.expenses || this.expenses.length === 0) {
            return [];
        }
        const totals = {};
        let grandTotal = 0;
        this.expenses.forEach((e) => {
            const cat = e.rajuser2003__Category__c || 'Other';
            const amt = Number(e.rajuser2003__Amount__c || 0);
            totals[cat] = (totals[cat] || 0) + amt;
            grandTotal += amt;
        });
        return Object.keys(totals)
            .map((cat) => {
                const amt = totals[cat];
                const pct = grandTotal > 0 ? Math.round((amt / grandTotal) * 100) : 0;
                return {
                    category: cat,
                    formattedAmount: this.formatCurrency(amt),
                    pct,
                    barStyle: `width:${pct}%`,
                    icon: this.getCategoryIcon(cat),
                    dotClass: `legend-dot dot-${this.getCategoryColorKey(cat)}`
                };
            })
            .sort((a, b) => b.pct - a.pct);
    }
 
    get hasCategoryBreakdown() {
        return this.categoryBreakdown.length > 0;
    }
 
    /* ---------- DONUT CHART (pure CSS conic-gradient, no external lib) ---------- */
    get donutStyle() {
        const breakdown = this.categoryBreakdown;
        if (breakdown.length === 0) {
            return 'background: var(--neutral-bg);';
        }
        let cumulative = 0;
        const stops = breakdown.map((c) => {
            const start = cumulative;
            cumulative += c.pct;
            const color = this.getCategoryHexColor(c.category);
            return `${color} ${start}% ${cumulative}%`;
        });
        // fill any rounding gap with the last color so the ring is always complete
        if (cumulative < 100 && breakdown.length > 0) {
            stops.push(`${this.getCategoryHexColor(breakdown[breakdown.length - 1].category)} ${cumulative}% 100%`);
        }
        return `background: conic-gradient(${stops.join(', ')});`;
    }
 
    getCategoryHexColor(cat) {
        const map = {
            amber: '#b45309',
            blue: '#1d4ed8',
            green: '#15803d',
            pink: '#be185d',
            purple: '#5b21b6',
            gray: '#52525b'
        };
        return map[this.getCategoryColorKey(cat)] || map.gray;
    }
 
    getCategoryIcon(cat) {
        const map = {
            food: 'utility:like',
            hotel: 'utility:home',
            accommodation: 'utility:home',
            travel: 'utility:location',
            transport: 'utility:location',
            shopping: 'utility:cart',
            entertainment: 'utility:reward',
            other: 'utility:info'
        };
        const key = (cat || '').toLowerCase();
        return map[key] || 'utility:info';
    }
 
    getCategoryColorKey(cat) {
        const map = {
            food: 'amber',
            hotel: 'blue',
            accommodation: 'blue',
            travel: 'green',
            transport: 'green',
            shopping: 'pink',
            entertainment: 'purple',
            other: 'gray'
        };
        const key = (cat || '').toLowerCase();
        return map[key] || 'gray';
    }
 
    /* ===================================================================
     *  DATA HELPERS
     * =================================================================== */
    decorateMember(m) {
        const balance = m.rajuser2003__Balance__c || 0;
        const colorKey = this.getAvatarColorKey(m.rajuser2003__MemberName__c);
        return {
            ...m,
            formattedBalance: this.formatCurrency(balance),
            formattedPaid: this.formatCurrency(m.rajuser2003__Totalpaid__c),
            formattedShare: this.formatCurrency(m.rajuser2003__TotalShare__c),
            balanceClass:
                balance > 0
                    ? 'balance-pill balance-positive'
                    : balance < 0
                    ? 'balance-pill balance-negative'
                    : 'balance-pill balance-neutral',
            balanceStatus: balance > 0 ? 'gets back' : balance < 0 ? 'owes' : 'settled up',
            initials: this.getInitials(m.rajuser2003__MemberName__c),
            avatarClass: `member-avatar avatar-${colorKey}`,
            cardClass: `member-card fade-in-item border-${colorKey}`
        };
    }
 
    getAvatarColorKey(name) {
        const palette = ['purple', 'teal', 'coral', 'pink', 'blue', 'green'];
        let hash = 0;
        const str = name || '';
        for (let i = 0; i < str.length; i++) {
            hash = (hash * 31 + str.charCodeAt(i)) % palette.length;
        }
        return palette[Math.abs(hash) % palette.length];
    }
 
 
    getInitials(name) {
        if (!name) return '?';
        const parts = name.trim().split(' ');
        return parts.length > 1
            ? (parts[0][0] + parts[1][0]).toUpperCase()
            : name.substring(0, 2).toUpperCase();
    }
 
    formatCurrency(val) {
        const num = Number(val || 0);
        return num.toLocaleString('en-IN', {
            style: 'currency',
            currency: 'INR',
            minimumFractionDigits: 2
        });
    }
 
    loadTripData() {
        // wires react automatically to selectedTripId change; nothing else needed
    }
 
    refreshAll() {
        return Promise.all([
            refreshApex(this.wiredTripsResult),
            refreshApex(this.wiredMembersResult),
            refreshApex(this.wiredExpensesResult)
        ]);
    }
 
    showError(title, error) {
        const message =
            (error && error.body && error.body.message) || error.message || 'Unknown error';
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant: 'error' })
        );
    }
 
    showSuccess(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant: 'success' })
        );
    }
 
    /* ===================================================================
     *  EVENT HANDLERS — TRIP SELECTOR
     * =================================================================== */
    handleTripSelect(event) {
        this.selectedTripId = event.currentTarget.dataset.id;
    }
 
    /* ===================================================================
     *  NEW TRIP MODAL
     * =================================================================== */
    openNewTripModal() {
        const defaultStatus = this.statusOptions.length > 0 ? this.statusOptions[0].value : '';
        this.newTrip = { name: '', startDate: '', endDate: '', status: defaultStatus };
        this.showNewTripModal = true;
    }
 
    closeNewTripModal() {
        this.showNewTripModal = false;
    }
 
    handleNewTripField(event) {
        const field = event.target.dataset.field;
        this.newTrip = { ...this.newTrip, [field]: event.target.value };
    }
 
    async saveNewTrip() {
        if (!this.newTrip.name) {
            this.showError('Missing info', { message: 'Trip name is required.' });
            return;
        }
        this.isLoading = true;
        try {
            const newId = await createTrip({
                tripName: this.newTrip.name,
                startDate: this.newTrip.startDate || null,
                endDate: this.newTrip.endDate || null,
                status: this.newTrip.status
            });
            this.showSuccess('Trip created', `"${this.newTrip.name}" has been created.`);
            this.showNewTripModal = false;
            await refreshApex(this.wiredTripsResult);
            this.selectedTripId = newId;
        } catch (e) {
            this.showError('Could not create trip', e);
        } finally {
            this.isLoading = false;
        }
    }
 
    /* ===================================================================
     *  ADD MEMBER MODAL
     * =================================================================== */
    openAddMemberModal() {
        this.newMember = { name: '', contactId: '', contactName: '' };
        this.contactResults = [];
        this.showAddMemberModal = true;
    }
 
    closeAddMemberModal() {
        this.showAddMemberModal = false;
    }
 
    handleMemberNameChange(event) {
        this.newMember = { ...this.newMember, name: event.target.value };
    }
 
    handleContactSearch(event) {
        const term = event.target.value;
        window.clearTimeout(this.contactSearchTimeout);
        if (!term || term.length < 2) {
            this.contactResults = [];
            return;
        }
        this.contactSearchTimeout = setTimeout(async () => {
            try {
                const results = await searchContacts({ searchTerm: term });
                this.contactResults = results;
            } catch (e) {
                this.showError('Contact search failed', e);
            }
        }, 300);
    }
 
    selectContact(event) {
        const id = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this.newMember = { ...this.newMember, contactId: id, contactName: name };
        this.contactResults = [];
    }
 
    clearSelectedContact() {
        this.newMember = { ...this.newMember, contactId: '', contactName: '' };
    }
 
    async saveNewMember() {
        if (!this.newMember.name) {
            this.showError('Missing info', { message: 'Member name is required.' });
            return;
        }
        this.isLoading = true;
        try {
            await createTripMember({
                tripId: this.selectedTripId,
                memberName: this.newMember.name,
                contactId: this.newMember.contactId || null
            });
            this.showSuccess('Member added', `${this.newMember.name} joined the trip.`);
            this.showAddMemberModal = false;
            await this.refreshAll();
        } catch (e) {
            this.showError('Could not add member', e);
        } finally {
            this.isLoading = false;
        }
    }
 
    /* ===================================================================
     *  ADD EXPENSE MODAL
     * =================================================================== */
    openAddExpenseModal() {
        if (!this.hasMembers) {
            this.showError('No members yet', { message: 'Add at least one trip member before logging an expense.' });
            return;
        }
        const defaultCategory = this.categoryOptions.length > 0 ? this.categoryOptions[0].value : '';
        this.newExpense = {
            name: '',
            amount: null,
            category: defaultCategory,
            date: '',
            paidById: this.members[0].Id,
            splitType: 'equal'
        };
        this.selectedShareMemberIds = this.members.map((m) => m.Id);
        this.buildCustomShareRows();
        this.showAddExpenseModal = true;
    }
 
    closeAddExpenseModal() {
        this.showAddExpenseModal = false;
    }
 
    handleExpenseField(event) {
        const field = event.target.dataset.field;
        this.newExpense = { ...this.newExpense, [field]: event.target.value };
        if (field === 'splitType') {
            this.buildCustomShareRows();
        }
    }
 
    handleShareMembersChange(event) {
        this.selectedShareMemberIds = event.detail.value;
        this.buildCustomShareRows();
    }
 
    buildCustomShareRows() {
        if (this.newExpense.splitType !== 'custom') {
            this.customShareRows = [];
            return;
        }
        const n = this.selectedShareMemberIds.length || 1;
        const evenPct = +(100 / n).toFixed(2);
        this.customShareRows = this.selectedShareMemberIds.map((id) => {
            const m = this.members.find((mm) => mm.Id === id);
            return {
                id,
                name: m ? m.rajuser2003__MemberName__c : id,
                percentage: evenPct
            };
        });
    }
 
    handleCustomPctChange(event) {
        const id = event.currentTarget.dataset.id;
        const val = event.target.value;
        this.customShareRows = this.customShareRows.map((r) =>
            r.id === id ? { ...r, percentage: val } : r
        );
    }
 
    async saveNewExpense() {
        const { name, amount, category, date, paidById, splitType } = this.newExpense;
        if (!name || !amount || !date || !paidById) {
            this.showError('Missing info', { message: 'Expense name, amount, date and payer are required.' });
            return;
        }
        if (this.selectedShareMemberIds.length === 0) {
            this.showError('Missing info', { message: 'Select at least one member to split with.' });
            return;
        }
        if (splitType === 'custom' && !this.customSplitTotalValid) {
            this.showError('Invalid split', { message: 'Custom percentages must add up to 100%.' });
            return;
        }
 
        this.isLoading = true;
        try {
            const customPercentages =
                splitType === 'custom'
                    ? this.customShareRows.map((r) => Number(r.percentage))
                    : null;
 
            await createExpense({
                tripId: this.selectedTripId,
                expenseName: name,
                amount: Number(amount),
                category,
                expenseDate: date,
                paidById,
                shareMemberIds: this.selectedShareMemberIds,
                splitType,
                customPercentages
            });
            this.showSuccess('Expense added', `${name} logged for ${this.formatCurrency(amount)}.`);
            this.showAddExpenseModal = false;
            await this.refreshAll();
        } catch (e) {
            this.showError('Could not add expense', e);
        } finally {
            this.isLoading = false;
        }
    }
 
    /* ===================================================================
     *  EXPENSE DETAIL / SHARES
     * =================================================================== */
    decorateShare(s) {
        const isPaid = !!s.rajuser2003__Paid__c;
        return {
            ...s,
            memberName: s.rajuser2003__tripmember__r
                ? s.rajuser2003__tripmember__r.rajuser2003__MemberName__c
                : '—',
            formattedShare: this.formatCurrency(s.rajuser2003__Shareamount__c),
            settlementLabel: s.rajuser2003__Settlement_Picklist__c
                || (this.settlementOptions[0] ? this.settlementOptions[0].label : 'Pending'),
            paidClass: isPaid ? 'paid-pill paid-yes' : 'paid-pill paid-no'
        };
    }
 
    async openExpenseDetail(event) {
        const id = event.currentTarget.dataset.id;
        this.activeExpense = this.expenses.find((e) => e.Id === id);
        this.isLoading = true;
        try {
            const shares = await getExpenseShares({ expenseId: id });
            this.activeExpenseShares = shares.map((s) => this.decorateShare(s));
            this.showExpenseDetail = true;
        } catch (e) {
            this.showError('Could not load expense shares', e);
        } finally {
            this.isLoading = false;
        }
    }
 
    closeExpenseDetail() {
        this.showExpenseDetail = false;
        this.activeExpense = null;
        this.activeExpenseShares = [];
    }
 
    async toggleShareSettled(event) {
        const shareId = event.currentTarget.dataset.id;
        const currentValue = event.currentTarget.dataset.settlement;
        this.isLoading = true;
        try {
            // Cycle to the next real, active picklist value defined in the org
            const options = this.settlementOptions;
            let nextValue = options.length > 0 ? options[0].value : 'Paid';
            if (options.length > 0) {
                const idx = options.findIndex((o) => o.value === currentValue);
                nextValue = options[(idx + 1) % options.length].value;
            }
            await updateShareSettlement({
                shareId,
                tripId: this.selectedTripId,
                settlementValue: nextValue
            });
            const shares = await getExpenseShares({ expenseId: this.activeExpense.Id });
            this.activeExpenseShares = shares.map((s) => this.decorateShare(s));
            await this.refreshAll();
        } catch (e) {
            this.showError('Could not update settlement', e);
        } finally {
            this.isLoading = false;
        }
    }
 
    async handleDeleteExpense() {
        if (!this.activeExpense) return;
        this.isLoading = true;
        try {
            await deleteExpense({ expenseId: this.activeExpense.Id, tripId: this.selectedTripId });
            this.showSuccess('Expense removed', `${this.activeExpense.Name} was deleted.`);
            this.closeExpenseDetail();
            await this.refreshAll();
        } catch (e) {
            this.showError('Could not delete expense', e);
        } finally {
            this.isLoading = false;
        }
    }
}