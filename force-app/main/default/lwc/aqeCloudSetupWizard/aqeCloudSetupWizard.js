import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEngineStatus from '@salesforce/apex/AQE_QuoteController.getEngineStatus';
import detectAndSaveEnvironment from '@salesforce/apex/AQE_QuoteController.detectAndSaveEnvironment';

export default class AqeCloudSetupWizard extends LightningElement {

    @track engineStatus = {};
    @track isLoading    = false;
    @track isDetecting  = false;
    @track statusLoaded = false;

    get engineActive()       { return this.engineStatus.engineActive === true; }
    get cloudEnvironment()   { return this.engineStatus.cloudEnvironment || 'Not detected'; }
    get backendReachable()   { return this.engineStatus.backendReachable === true; }
    get llmModel()           { return this.engineStatus.llmModel || 'Not configured'; }
    get maxSyncLines()       { return this.engineStatus.maxSyncLines || 30; }
    get piiEnabled()         { return this.engineStatus.piiEnabled === true; }

    get engineStatusIcon()   { return this.engineActive ? 'utility:check' : 'utility:close'; }
    get backendIcon()        { return this.backendReachable ? 'utility:check' : 'utility:close'; }
    get engineStatusVariant() { return this.engineActive ? 'success' : 'error'; }
    get backendVariant()     { return this.backendReachable ? 'success' : 'error'; }

    get environmentBadge() {
        const env = this.cloudEnvironment;
        if (env === 'CPQ_Cloud') return 'Salesforce CPQ Cloud';
        if (env === 'Revenue_Cloud') return 'Revenue Cloud';
        if (env === 'Standard_Salesforce') return 'Standard Salesforce';
        return env;
    }

    connectedCallback() {
        this.loadStatus();
    }

    async loadStatus() {
        this.isLoading = true;
        try {
            this.engineStatus = await getEngineStatus();
            this.statusLoaded = true;
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Failed to load engine status: ' + (err.body?.message || err.message),
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    async handleDetectEnvironment() {
        this.isDetecting = true;
        try {
            const env = await detectAndSaveEnvironment();
            this.engineStatus = { ...this.engineStatus, cloudEnvironment: env };
            this.dispatchEvent(new ShowToastEvent({
                title: 'Environment Detected',
                message: 'Cloud environment detected and saved: ' + env,
                variant: 'success'
            }));
            await this.loadStatus(); // Reload full status
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Detection Failed',
                message: err.body?.message || err.message,
                variant: 'error'
            }));
        } finally {
            this.isDetecting = false;
        }
    }

    handleRefresh() {
        this.loadStatus();
    }
}
