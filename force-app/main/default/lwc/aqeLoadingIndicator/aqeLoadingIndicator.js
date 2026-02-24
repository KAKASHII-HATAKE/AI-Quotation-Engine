import { LightningElement, api } from 'lwc';

export default class AqeLoadingIndicator extends LightningElement {
    @api message = 'Processing...';
    @api variant = 'base'; // 'base' | 'brand'
}
