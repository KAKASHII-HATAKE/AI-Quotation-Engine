/**
 * @description Cloud-neutral Data Transfer Object representing a Product.
 *              Wraps Product2 data in a format usable across all cloud adapters.
 * @namespace   aqe
 */
public class AQE_ProductDTO {

    /** Product2 Record ID */
    public Id id;

    /** Product2.Name */
    public String name;

    /** Product2.ProductCode — primary key for rule binding */
    public String productCode;

    /** Product2.Description */
    public String description;

    /** Product2.Family */
    public String family;

    /** Current list price from the active pricebook */
    public Decimal listPrice;

    /** PricebookEntry Record ID used to resolve this list price */
    public Id pricebookEntryId;

    /** Whether the product is currently active */
    public Boolean isActive;

    /** Unit of measure (e.g. 'Each', 'License', 'Month') */
    public String unitOfMeasure;

    /**
     * Extension map for product-specific attributes not in standard fields.
     * Example: cost price, minimum order quantity, lead time.
     */
    public Map<String, Object> customFields = new Map<String, Object>();

    public AQE_ProductDTO() {}
}
