import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { refreshApex } from '@salesforce/apex';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import USER_ID from '@salesforce/user/Id';

import TASK_LOG_OBJECT from '@salesforce/schema/Task_Log__c';
import VISIT_TYPE_FIELD from '@salesforce/schema/Task_Log__c.Visit_Type__c';
import REASON_FIELD from '@salesforce/schema/Task_Log__c.Reason_for_Visit__c';

import getOpenStatus from '@salesforce/apex/LeadActivityLauncherController.getOpenStatus';
import getAssignableUsers from '@salesforce/apex/LeadActivityLauncherController.getAssignableUsers';
import createCall from '@salesforce/apex/LeadActivityLauncherController.createCall';
import createEvent from '@salesforce/apex/LeadActivityLauncherController.createEvent';
import createVisit from '@salesforce/apex/LeadActivityLauncherController.createVisit';

const MENU = 'menu';

export default class LeadActivityLauncher extends LightningElement {
    @api recordId; // Lead Id (provided by the record page / quick action)

    view = MENU;
    saving = false;

    callOpen = false;
    eventOpen = false;
    visitOpen = false;
    eventVisitBlocked = false; // Lead department = Enquiry

    assignableUsers = [];

    // Assignee defaults to the running user.
    @track call = { subject: '', date: '', time: '', comments: '', assignedTo: USER_ID };
    @track event = { subject: '', comments: '', start: '', end: '', assignedTo: USER_ID };
    @track visit = { visitType: '', reason: '', scheduleDate: '', assignedTo: USER_ID };

    _statusResult;

    // ---------- wires ----------
    @wire(getOpenStatus, { leadId: '$recordId' })
    wiredStatus(result) {
        this._statusResult = result;
        if (result.data) {
            this.callOpen = result.data.callOpen;
            this.eventOpen = result.data.eventOpen;
            this.visitOpen = result.data.visitOpen;
            this.eventVisitBlocked = result.data.eventVisitBlocked;
        }
    }

    _defaultsApplied = false;

    // Assignable users are based on the running user's department (no leadId).
    @wire(getAssignableUsers)
    wiredUsers({ data, error }) {
        if (data) {
            this.assignableUsers = data;

            // Set the default assignee only after the options exist, otherwise the
            // combobox has nothing to match its value against and renders blank.
            if (!this._defaultsApplied && data.length) {
                this._defaultsApplied = true;
                const me = data.find((u) => u.id === USER_ID);
                const defaultId = me ? me.id : data[0].id;
                this.call = { ...this.call, assignedTo: defaultId };
                this.event = { ...this.event, assignedTo: defaultId };
                this.visit = { ...this.visit, assignedTo: defaultId };
            }
        } else if (error) {
            const msg = error.body && error.body.message ? error.body.message : 'Unknown error';
            this.toast('Could not load assignable users', msg, 'error');
            // eslint-disable-next-line no-console
            console.error('getAssignableUsers error', error);
        }
    }

    @wire(getObjectInfo, { objectApiName: TASK_LOG_OBJECT })
    taskLogInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$taskLogInfo.data.defaultRecordTypeId',
        fieldApiName: VISIT_TYPE_FIELD
    })
    visitTypePicklist;

    @wire(getPicklistValues, {
        recordTypeId: '$taskLogInfo.data.defaultRecordTypeId',
        fieldApiName: REASON_FIELD
    })
    reasonPicklist;

    // ---------- date/time floors (local-time aware) ----------
    // toISOString() emits UTC, which is off by the local offset (e.g. +5:30 IST).
    // Shift by the timezone offset first so the floors reflect local wall-clock time.
    get todayLocal() {
        const d = new Date();
        return new Date(d.getTime() - d.getTimezoneOffset() * 60000)
            .toISOString()
            .slice(0, 10); // YYYY-MM-DD
    }

    get nowLocalDateTime() {
        const d = new Date();
        return new Date(d.getTime() - d.getTimezoneOffset() * 60000)
            .toISOString()
            .slice(0, 16); // YYYY-MM-DDTHH:mm
    }

    isPast(value) {
        return new Date(value).getTime() < Date.now();
    }

    // ---------- view getters ----------
    get showMenu() { return this.view === MENU; }
    get showCallForm() { return this.view === 'call'; }
    get showEventForm() { return this.view === 'event'; }
    get showVisitForm() { return this.view === 'visit'; }

    get eventDisabled() { return this.eventOpen || this.eventVisitBlocked; }
    get visitDisabled() { return this.visitOpen || this.eventVisitBlocked; }

    get visitTypeOptions() {
        return this.visitTypePicklist && this.visitTypePicklist.data
            ? this.visitTypePicklist.data.values.map((v) => ({ label: v.label, value: v.value }))
            : [];
    }

    get reasonOptions() {
        return this.reasonPicklist && this.reasonPicklist.data
            ? this.reasonPicklist.data.values.map((v) => ({ label: v.label, value: v.value }))
            : [];
    }

    get assignableUserOptions() {
        return (this.assignableUsers || []).map((u) => ({ label: u.name, value: u.id }));
    }
    get hasAssignees() { return this.assignableUserOptions.length > 0; }

    // ---------- validity ----------
    get callInvalid() {
        if (!this.call.subject || !this.call.date || !this.call.time) return true;
        if (this.hasAssignees && !this.call.assignedTo) return true;
        // The date picker's min blocks earlier days, but a time earlier than now
        // on today's date still slips through — recombine and check against now.
        return this.isPast(this.combineDateTime(this.call.date, this.call.time));
    }
    get eventInvalid() {
        if (!this.event.subject || !this.event.start || !this.event.end) return true;
        if (this.hasAssignees && !this.event.assignedTo) return true;
        if (this.isPast(this.event.start)) return true;
        return new Date(this.event.end) <= new Date(this.event.start);
    }
    get visitInvalid() {
        return !this.visit.visitType || !this.visit.reason || !this.visit.scheduleDate
            || (this.hasAssignees && !this.visit.assignedTo);
    }

    // ---------- navigation ----------
    selectCall() { this.view = 'call'; }
    selectEvent() { if (!this.eventDisabled) this.view = 'event'; }
    selectVisit() { if (!this.visitDisabled) this.view = 'visit'; }
    backToMenu() { this.view = MENU; }

    // ---------- change handlers ----------
    handleCallChange(e) {
        this.call = { ...this.call, [e.target.dataset.field]: e.target.value };
    }
    handleEventChange(e) {
        this.event = { ...this.event, [e.target.dataset.field]: e.target.value };
    }
    handleVisitChange(e) {
        this.visit = { ...this.visit, [e.target.dataset.field]: e.target.value };
    }

    combineDateTime(dateStr, timeStr) {
        const [y, m, d] = dateStr.split('-').map(Number);
        const [hh, mm] = timeStr.substring(0, 5).split(':').map(Number);
        return new Date(y, m - 1, d, hh, mm).toISOString();
    }

    // ---------- save handlers ----------
    async saveCall() {
        if (this.callInvalid) return;
        this.saving = true;
        try {
            await createCall({
                leadId: this.recordId,
                subject: this.call.subject,
                followUp: this.combineDateTime(this.call.date, this.call.time),
                comments: this.call.comments,
                assignedToId: this.call.assignedTo || null
            });
            await this.finish('Call created');
        } catch (err) {
            this.fail(err);
        }
    }

    async saveEvent() {
        if (this.eventInvalid) return;
        this.saving = true;
        try {
            await createEvent({
                leadId: this.recordId,
                subject: this.event.subject,
                comments: this.event.comments,
                startDt: this.event.start,
                endDt: this.event.end,
                assignedToId: this.event.assignedTo || null
            });
            await this.finish('Event created');
        } catch (err) {
            this.fail(err);
        }
    }

    async saveVisit() {
        if (this.visitInvalid) return;
        this.saving = true;
        try {
            await createVisit({
                leadId: this.recordId,
                visitType: this.visit.visitType,
                reason: this.visit.reason,
                scheduleDate: this.visit.scheduleDate,
                assignedToId: this.visit.assignedTo || null
            });
            await this.finish('Visit created');
        } catch (err) {
            this.fail(err);
        }
    }

    // ---------- helpers ----------
    async finish(msg) {
        this.saving = false;
        this.toast('Success', msg, 'success');
        this.resetForms();
        this.view = MENU;
        if (this._statusResult) {
            await refreshApex(this._statusResult);
        }
    }

    fail(err) {
        this.saving = false;
        const msg =
            err && err.body && err.body.message ? err.body.message : 'Unexpected error';
        this.toast('Error', msg, 'error');
    }

    resetForms() {
        this.call = { subject: '', date: '', time: '', comments: '', assignedTo: USER_ID };
        this.event = { subject: '', comments: '', start: '', end: '', assignedTo: USER_ID };
        this.visit = { visitType: '', reason: '', scheduleDate: '', assignedTo: USER_ID };
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}