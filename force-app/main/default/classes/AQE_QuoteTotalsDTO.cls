/**
 * @description Cloud-neutral Data Transfer Object representing computed Quote totals.
 *              Returned by adapter.calculateTotals() and stored on AQE_QuoteDTO.totals.
 * @namespace   aqe
 */
public class AQE_QuoteTotalsDTO {

    /** Sum of all line item list prices (before any discounts) */
    public Decimal subtotal = 0;

    /** Total currency amount discounted across all lines */
    public Decimal totalDiscount = 0;

    /** Final net total after all discounts: subtotal - totalDiscount */
    public Decimal netTotal = 0;

    /** Effective overall discount percentage: (totalDiscount / subtotal) * 100 */
    public Decimal effectiveDiscountPercent = 0;

    /** Tax amount (if applicable — environment dependent) */
    public Decimal taxAmount = 0;

    /** Grand total including tax */
    public Decimal grandTotal = 0;

    /** Number of line items included in calculation */
    public Integer lineCount = 0;

    /** Currency ISO code for all amounts */
    public String currencyIsoCode;

    public AQE_QuoteTotalsDTO() {}

    /**
     * Convenience constructor for simple cases.
     * @param subtotal      Pre-discount subtotal
     * @param totalDiscount Total discount amount
     */
    public AQE_QuoteTotalsDTO(Decimal subtotal, Decimal totalDiscount) {
        this.subtotal       = subtotal == null ? 0 : subtotal;
        this.totalDiscount  = totalDiscount == null ? 0 : totalDiscount;
        this.netTotal       = this.subtotal - this.totalDiscount;
        this.grandTotal     = this.netTotal;
        if (this.subtotal > 0) {
            this.effectiveDiscountPercent = (this.totalDiscount / this.subtotal) * 100;
        }
    }
}
