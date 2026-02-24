/**
 * @description Interface that all cloud-specific quote adapters must implement.
 *              Provides a cloud-neutral API for all quote operations, enabling the
 *              same business logic to run across Standard Salesforce, CPQ Cloud (SBQQ),
 *              and Revenue Cloud without modification.
 * @namespace   aqe
 */
public interface AQE_IQuoteAdapter {

    /**
     * Creates a new quote header record in the target cloud environment.
     * @param quoteData Cloud-neutral quote DTO
     * @return Salesforce Record ID of the created quote
     */
    Id createQuote(AQE_QuoteDTO quoteData);

    /**
     * Retrieves a quote and maps it into a cloud-neutral DTO.
     * @param quoteId Salesforce Record ID of the quote
     * @return Cloud-neutral quote DTO
     */
    AQE_QuoteDTO getQuote(Id quoteId);

    /**
     * Updates an existing quote header record.
     * @param quoteId   Salesforce Record ID of the quote to update
     * @param quoteData Updated field values in cloud-neutral DTO
     */
    void updateQuote(Id quoteId, AQE_QuoteDTO quoteData);

    /**
     * Creates quote line items in bulk for the target cloud environment.
     * @param quoteId Salesforce Record ID of the parent quote
     * @param lines   List of cloud-neutral line DTOs
     * @return List of created line item Record IDs (in same order as input)
     */
    List<Id> createQuoteLines(Id quoteId, List<AQE_QuoteLineDTO> lines);

    /**
     * Retrieves all line items for a quote.
     * @param quoteId Salesforce Record ID of the parent quote
     * @return List of cloud-neutral line DTOs
     */
    List<AQE_QuoteLineDTO> getQuoteLines(Id quoteId);

    /**
     * Updates existing quote line items.
     * @param lines List of line DTOs with Id populated and updated field values
     */
    void updateQuoteLines(List<AQE_QuoteLineDTO> lines);

    /**
     * Deletes quote line items by ID.
     * @param lineIds List of Record IDs to delete
     */
    void deleteQuoteLines(List<Id> lineIds);

    /**
     * Retrieves product information by product codes.
     * @param productCodes List of Product2.ProductCode values
     * @return List of cloud-neutral product DTOs
     */
    List<AQE_ProductDTO> getProducts(List<String> productCodes);

    /**
     * Returns the list price for a product from the given pricebook.
     * @param productCode Product2.ProductCode
     * @param pricebookId Salesforce Record ID of the Pricebook2
     * @return List price as Decimal, or null if not found
     */
    Decimal getListPrice(String productCode, Id pricebookId);

    /**
     * Calculates and returns quote totals (subtotal, discount, net total).
     * @param quoteId Salesforce Record ID of the quote
     * @return Cloud-neutral totals DTO
     */
    AQE_QuoteTotalsDTO calculateTotals(Id quoteId);

    /**
     * Submits a quote for approval using the appropriate mechanism for the cloud environment.
     * @param quoteId  Salesforce Record ID of the quote
     * @param comments Submitter comments
     * @return ProcessInstanceWorkitem ID or equivalent approval work item ID
     */
    Id submitForApproval(Id quoteId, String comments);

    /**
     * Returns the cloud environment type string for this adapter.
     * @return One of: 'Standard_Salesforce', 'CPQ_Cloud', 'Revenue_Cloud'
     */
    String getEnvironmentType();
}
