/**
 * @description Cloud-neutral Data Transfer Object representing a single Quote Line Item.
 *              Maps across QuoteLineItem (Standard), SBQQ__QuoteLine__c (CPQ),
 *              and OrderItem / Revenue Cloud line equivalents.
 * @namespace   aqe
 */
public class AQE_QuoteLineDTO {

    /** Salesforce Record ID — null for new lines */
    public Id id;

    /** Parent Quote Record ID */
    public Id quoteId;

    /** Product2 Record ID */
    public Id product2Id;

    /** Product2.ProductCode — primary rule-binding key */
    public String productCode;

    /** Product2.Name */
    public String productName;

    /** PricebookEntry Record ID */
    public Id pricebookEntryId;

    /** Ordered quantity */
    public Decimal quantity;

    /** List price from pricebook (before any discounts) */
    public Decimal listPrice;

    /** Unit price after all pricing rules applied */
    public Decimal unitPrice;

    /** Total discount percentage applied (0-100) */
    public Decimal discountPercent;

    /** Total price = unitPrice * quantity */
    public Decimal totalPrice;

    /** Sort order within the quote */
    public Integer sortOrder;

    /** Description / notes for this line */
    public String description;

    /** AQE-specific: External reference for bulk processing idempotency */
    public String externalRef;

    /** AQE-specific: Comma-separated names of pricing rules applied to this line */
    public String rulesApplied;

    /** AQE-specific: Whether this line was auto-added by a product dependency rule */
    public Boolean autoAdded = false;

    /**
     * Extension map for cloud-specific fields that don't have a standard mapping.
     * Example: {'SBQQ__Discount__c' => 15.0} for CPQ lines.
     */
    public Map<String, Object> customFields = new Map<String, Object>();

    public AQE_QuoteLineDTO() {}

    public AQE_QuoteLineDTO(String productCode, Decimal quantity, Decimal listPrice) {
        this.productCode = productCode;
        this.quantity    = quantity;
        this.listPrice   = listPrice;
        this.unitPrice   = listPrice;
        this.totalPrice  = listPrice * quantity;
    }
}
