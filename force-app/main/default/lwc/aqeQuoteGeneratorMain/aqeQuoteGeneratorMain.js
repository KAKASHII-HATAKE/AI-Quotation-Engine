import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import generateQuote from '@salesforce/apex/AQE_QuoteController.generateQuote';
import getEngineStatus from '@salesforce/apex/AQE_QuoteController.getEngineStatus';

// Account fields needed for context
const ACCOUNT_FIELDS = ['Account.Name', 'Account.Type', 'Account.Industry'];

export default class AqeQuoteGeneratorMain extends LightningElement {

    // ─── Public properties (passed from record page) ─────────────────────────
    @api recordId;      // Account or Opportunity record ID
    @api objectApiName; // 'Account' or 'Opportunity'

    // ─── State ───────────────────────────────────────────────────────────────
    @track userPrompt      = '';
    @track isProcessing    = false;
    @track engineActive    = false;
    @track engineStatus    = {};
    @track quoteResult     = null;
    @track errors          = [];
    @track warnings        = [];
    @track showPreview     = false;

    // ─── Derived IDs ─────────────────────────────────────────────────────────
    get accountId() {
        return this.objectApiName === 'Account' ? this.recordId : null;
    }
    get opportunityId() {
        return this.objectApiName === 'Opportunity' ? this.recordId : null;
    }

    // ─── Getters for template logic ───────────────────────────────────────────
    get isDisabled() {
        return !this.engineActive || this.isProcessing || !this.userPrompt.trim();
    }
    get promptLabel() {
        return 'Describe your quote (e.g. "50 Laptop Pro units with 15% enterprise discount for Q4")';
    }
    get hasErrors() { return this.errors.length > 0; }
    get hasWarnings() { return this.warnings.length > 0; }
    get engineStatusLabel() {
        if (!this.engineActive) return 'AI Engine Disabled';
        return 'AI Engine Ready · ' + (this.engineStatus.cloudEnvironment || '');
    }
    get engineStatusClass() {
        return this.engineActive ? 'engine-badge engine-active' : 'engine-badge engine-disabled';
    }
    get engineIconName() {
        return this.engineActive ? 'utility:check' : 'utility:warning';
    }

    // ─── Lifecycle ────────────────────────────────────────────────────────────
    connectedCallback() {
        this.loadEngineStatus();
    }

    // ─── Event handlers ───────────────────────────────────────────────────────
    handlePromptChange(event) {
        this.userPrompt = event.target.value;
    }

    async handleGenerateClick() {
        this.isProcessing = true;
        this.errors       = [];
        this.warnings     = [];
        this.quoteResult  = null;
        this.showPreview  = false;

        try {
            const result = await generateQuote({
                userPrompt:    this.userPrompt,
                accountId:     this.accountId,
                opportunityId: this.opportunityId
            });

            if (result.success) {
                this.quoteResult = result;
                this.warnings    = result.warnings || [];
                this.showPreview = true;

                if (result.isBulk) {
                    this.dispatchEvent(new ShowToastEvent({
                        title:   'Bulk Processing Started',
                        message: 'Your quote has ' + result.quoteLines.length + ' lines and is being created asynchronously. Batch ID: ' + result.batchTransactionId,
                        variant: 'info',
                        mode:    'sticky'
                    }));
                } else {
                    this.dispatchEvent(new ShowToastEvent({
                        title:   'Quote Generated',
                        message: 'Quote created successfully with ' + result.quoteLines.length + ' lines.',
                        variant: 'success'
                    }));
                }

                if (result.approvalRequired) {
                    this.dispatchEvent(new ShowToastEvent({
                        title:   'Approval Required',
                        message: result.approvalReason || 'This quote requires approval.',
                        variant: 'warning',
                        mode:    'sticky'
                    }));
                }
            } else {
                this.errors = result.errors || ['Quote generation failed. Please try again.'];
            }
        } catch (err) {
            this.errors = [err.body?.message || err.message || 'An unexpected error occurred.'];
        } finally {
            this.isProcessing = false;
        }
    }

    handleClear() {
        this.userPrompt  = '';
        this.quoteResult = null;
        this.errors      = [];
        this.warnings    = [];
        this.showPreview = false;
        this.template.querySelector('lightning-textarea').value = '';
    }

    handleQuoteUpdated(event) {
        // Refresh quote data from child preview component
        this.quoteResult = { ...this.quoteResult, quoteLines: event.detail.lines };
    }

    // ─── Private methods ──────────────────────────────────────────────────────
    async loadEngineStatus() {
        try {
            this.engineStatus = await getEngineStatus();
            this.engineActive = this.engineStatus.engineActive === true;
            if (!this.engineActive) {
                this.errors = ['The AI Quotation Engine is not currently active. Please contact your administrator.'];
            }
        } catch (err) {
            this.engineActive = false;
            this.errors = ['Could not connect to AQE engine. Check setup configuration.'];
        }
    }
}
