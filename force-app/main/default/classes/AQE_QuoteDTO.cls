/**
 * @description Cloud-neutral Data Transfer Object representing a Quote header.
 *              Used by all adapters so business logic is decoupled from the
 *              underlying Salesforce object (Quote, SBQQ__Quote__c, or Order).
 * @namespace   aqe
 */
public class AQE_QuoteDTO {

    /** Salesforce Record ID — null for new quotes */
    public Id id;

    /** Quote name / reference number */
    public String name;

    /** Salesforce Account Record ID */
    public Id accountId;

    /** Salesforce Opportunity Record ID (optional) */
    public Id opportunityId;

    /** Salesforce Pricebook2 Record ID */
    public Id pricebookId;

    /** Quote expiry date */
    public Date expirationDate;

    /** Quote status (Draft, Presented, Accepted, etc.) */
    public String status;

    /** Currency ISO code (e.g. 'USD', 'GBP') */
    public String currencyIsoCode;

    /** Special terms / notes for this quote */
    public String description;

    /** Payment terms (e.g. 'Net 30', 'Net 60') */
    public String paymentTerms;

    /** AQE-specific: ID of the AI Transaction Log record for this quote session */
    public Id transactionLogId;

    /** AQE-specific: cloud environment that created this quote */
    public String cloudEnvironment;

    /**
     * Extension map for cloud-specific fields that don't have a standard mapping.
     * Key = field API name on the native object, Value = field value.
     * Example: {'SBQQ__Primary__c' => true} for CPQ quotes.
     */
    public Map<String, Object> customFields = new Map<String, Object>();

    /** Line items associated with this quote (populated on getQuote calls) */
    public List<AQE_QuoteLineDTO> lines = new List<AQE_QuoteLineDTO>();

    /** Quote totals (populated after calculation) */
    public AQE_QuoteTotalsDTO totals;

    public AQE_QuoteDTO() {}

    public AQE_QuoteDTO(Id accountId, Id pricebookId) {
        this.accountId   = accountId;
        this.pricebookId = pricebookId;
        this.status      = 'Draft';
    }
}
