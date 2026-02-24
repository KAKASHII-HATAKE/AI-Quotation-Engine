import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

const COLUMNS = [
    { label: 'Product Code', fieldName: 'productCode', type: 'text', editable: false },
    { label: 'Product Name', fieldName: 'productName', type: 'text' },
    { label: 'Qty', fieldName: 'quantity', type: 'number',
      typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 2 },
      editable: true, cellAttributes: { alignment: 'right' } },
    { label: 'List Price', fieldName: 'listPrice', type: 'currency',
      typeAttributes: { currencyCode: 'USD', minimumFractionDigits: 2 },
      cellAttributes: { alignment: 'right' } },
    { label: 'Discount %', fieldName: 'discountPercent', type: 'number',
      typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 2 },
      editable: true, cellAttributes: { alignment: 'right' } },
    { label: 'Unit Price', fieldName: 'unitPrice', type: 'currency',
      typeAttributes: { currencyCode: 'USD', minimumFractionDigits: 2 },
      cellAttributes: { alignment: 'right' } },
    { label: 'Total Price', fieldName: 'totalPrice', type: 'currency',
      typeAttributes: { currencyCode: 'USD', minimumFractionDigits: 2 },
      cellAttributes: { alignment: 'right' } },
    { label: 'Rules Applied', fieldName: 'rulesApplied', type: 'text',
      wrapText: true, cellAttributes: { alignment: 'left' } },
    { type: 'action', typeAttributes: {
        rowActions: [{ label: 'Remove Line', name: 'remove_line' }]
    }}
];

export default class AqeQuotePreview extends NavigationMixin(LightningElement) {

    @api quoteResult = {};
    @track lines = [];
    @track draftValues = [];
    columns = COLUMNS;

    get quoteId()     { return this.quoteResult?.quoteId; }
    get totals()      { return this.quoteResult?.quoteTotals || {}; }
    get lineCount()   { return this.lines.length; }
    get isBulk()      { return this.quoteResult?.isBulk === true; }
    get approvalRequired() { return this.quoteResult?.approvalRequired === true; }
    get approvalChain()    { return this.quoteResult?.approvalChain || ''; }
    get subtotal()    { return this.totals.subtotal || 0; }
    get totalDiscount() { return this.totals.totalDiscount || 0; }
    get netTotal()    { return this.totals.netTotal || 0; }
    get effectiveDiscount() { return this.totals.effectiveDiscountPercent || 0; }

    connectedCallback() {
        this.lines = (this.quoteResult?.quoteLines || []).map((l, i) => ({ ...l, _key: i }));
    }

    handleSave(event) {
        const updatedFields = event.detail.draftValues;
        // Recalculate totals for edited lines
        this.lines = this.lines.map(line => {
            const updated = updatedFields.find(d => d._key === line._key);
            if (!updated) return line;
            const newQty       = updated.quantity        != null ? parseFloat(updated.quantity)        : line.quantity;
            const newDiscount  = updated.discountPercent != null ? parseFloat(updated.discountPercent) : line.discountPercent || 0;
            const newUnitPrice = line.listPrice * (1 - newDiscount / 100);
            return {
                ...line,
                quantity:       newQty,
                discountPercent: newDiscount,
                unitPrice:      parseFloat(newUnitPrice.toFixed(4)),
                totalPrice:     parseFloat((newUnitPrice * newQty).toFixed(2))
            };
        });
        this.draftValues = [];
        this.dispatchEvent(new CustomEvent('quoteupdated', { detail: { lines: this.lines } }));
    }

    handleRowAction(event) {
        const { name } = event.detail.action;
        const row = event.detail.row;
        if (name === 'remove_line') {
            this.lines = this.lines.filter(l => l._key !== row._key);
            this.dispatchEvent(new CustomEvent('quoteupdated', { detail: { lines: this.lines } }));
        }
    }

    handleViewQuote() {
        if (!this.quoteId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.quoteId,
                actionName: 'view'
            }
        });
    }
}
