/**
 * @description Adapter for standard Salesforce Quote objects.
 *              Implements AQE_IQuoteAdapter using Quote, QuoteLineItem,
 *              and standard Pricebook2 / PricebookEntry objects.
 * @namespace   aqe
 */
public with sharing class AQE_StandardQuoteAdapter implements AQE_IQuoteAdapter {

    private static final String ENV = AQE_CloudDetector.ENV_STANDARD;

    // ─── Quote Header ─────────────────────────────────────────────────────────

    public Id createQuote(AQE_QuoteDTO dto) {
        AQE_SecurityUtil.checkObjectAccess('Quote', AQE_SecurityUtil.DML_CREATE);
        Quote q = new Quote(
            Name            = dto.name != null ? dto.name : 'AQE Quote - ' + System.now().format(),
            AccountId       = dto.accountId,
            OpportunityId   = dto.opportunityId,
            Pricebook2Id    = dto.pricebookId,
            ExpirationDate  = dto.expirationDate,
            Status          = dto.status != null ? dto.status : 'Draft',
            Description     = dto.description
        );
        // Apply any extra fields from customFields map
        applyCustomFields(q, dto.customFields);
        insert q;
        return q.Id;
    }

    public AQE_QuoteDTO getQuote(Id quoteId) {
        AQE_SecurityUtil.checkObjectAccess('Quote', AQE_SecurityUtil.DML_READ);
        Quote q = [
            SELECT Id, Name, AccountId, OpportunityId, Pricebook2Id,
                   ExpirationDate, Status, Description, CurrencyIsoCode
            FROM   Quote
            WHERE  Id = :quoteId
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        AQE_QuoteDTO dto = new AQE_QuoteDTO();
        dto.id              = q.Id;
        dto.name            = q.Name;
        dto.accountId       = q.AccountId;
        dto.opportunityId   = q.OpportunityId;
        dto.pricebookId     = q.Pricebook2Id;
        dto.expirationDate  = q.ExpirationDate;
        dto.status          = q.Status;
        dto.description     = q.Description;
        dto.currencyIsoCode = q.CurrencyIsoCode;
        dto.cloudEnvironment = ENV;
        return dto;
    }

    public void updateQuote(Id quoteId, AQE_QuoteDTO dto) {
        AQE_SecurityUtil.checkObjectAccess('Quote', AQE_SecurityUtil.DML_UPDATE);
        Quote q = new Quote(Id = quoteId);
        if (dto.name            != null) q.Name           = dto.name;
        if (dto.status          != null) q.Status         = dto.status;
        if (dto.expirationDate  != null) q.ExpirationDate = dto.expirationDate;
        if (dto.description     != null) q.Description    = dto.description;
        applyCustomFields(q, dto.customFields);
        update q;
    }

    // ─── Quote Lines ──────────────────────────────────────────────────────────

    public List<Id> createQuoteLines(Id quoteId, List<AQE_QuoteLineDTO> lines) {
        AQE_SecurityUtil.checkObjectAccess('QuoteLineItem', AQE_SecurityUtil.DML_CREATE);
        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        for (AQE_QuoteLineDTO line : lines) {
            QuoteLineItem qli = new QuoteLineItem(
                QuoteId         = quoteId,
                Product2Id      = line.product2Id,
                PricebookEntryId = line.pricebookEntryId,
                Quantity        = line.quantity,
                UnitPrice       = line.unitPrice,
                Description     = line.description
            );
            applyCustomFields(qli, line.customFields);
            qlis.add(qli);
        }
        insert qlis;
        List<Id> ids = new List<Id>();
        for (QuoteLineItem qli : qlis) { ids.add(qli.Id); }
        return ids;
    }

    public List<AQE_QuoteLineDTO> getQuoteLines(Id quoteId) {
        AQE_SecurityUtil.checkObjectAccess('QuoteLineItem', AQE_SecurityUtil.DML_READ);
        List<QuoteLineItem> qlis = [
            SELECT Id, QuoteId, Product2Id, Product2.ProductCode, Product2.Name,
                   PricebookEntryId, Quantity, UnitPrice, TotalPrice, Description
            FROM   QuoteLineItem
            WHERE  QuoteId = :quoteId
            WITH   SECURITY_ENFORCED
            ORDER BY SortOrder ASC NULLS LAST
        ];
        List<AQE_QuoteLineDTO> dtos = new List<AQE_QuoteLineDTO>();
        for (QuoteLineItem qli : qlis) {
            AQE_QuoteLineDTO dto = new AQE_QuoteLineDTO();
            dto.id               = qli.Id;
            dto.quoteId          = qli.QuoteId;
            dto.product2Id       = qli.Product2Id;
            dto.productCode      = qli.Product2.ProductCode;
            dto.productName      = qli.Product2.Name;
            dto.pricebookEntryId = qli.PricebookEntryId;
            dto.quantity         = qli.Quantity;
            dto.unitPrice        = qli.UnitPrice;
            dto.totalPrice       = qli.TotalPrice;
            dto.description      = qli.Description;
            dtos.add(dto);
        }
        return dtos;
    }

    public void updateQuoteLines(List<AQE_QuoteLineDTO> lines) {
        AQE_SecurityUtil.checkObjectAccess('QuoteLineItem', AQE_SecurityUtil.DML_UPDATE);
        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        for (AQE_QuoteLineDTO line : lines) {
            QuoteLineItem qli = new QuoteLineItem(Id = line.id);
            if (line.quantity  != null) qli.Quantity  = line.quantity;
            if (line.unitPrice != null) qli.UnitPrice = line.unitPrice;
            if (line.description != null) qli.Description = line.description;
            applyCustomFields(qli, line.customFields);
            qlis.add(qli);
        }
        update qlis;
    }

    public void deleteQuoteLines(List<Id> lineIds) {
        AQE_SecurityUtil.checkObjectAccess('QuoteLineItem', AQE_SecurityUtil.DML_DELETE);
        List<QuoteLineItem> toDelete = new List<QuoteLineItem>();
        for (Id lid : lineIds) { toDelete.add(new QuoteLineItem(Id = lid)); }
        delete toDelete;
    }

    // ─── Products & Pricing ───────────────────────────────────────────────────

    public List<AQE_ProductDTO> getProducts(List<String> productCodes) {
        List<PricebookEntry> pbes = [
            SELECT Id, Product2Id, Product2.Name, Product2.ProductCode,
                   Product2.Description, Product2.Family, Product2.IsActive,
                   UnitPrice, Pricebook2Id
            FROM   PricebookEntry
            WHERE  Product2.ProductCode IN :productCodes
            AND    IsActive = true
            AND    Pricebook2.IsStandard = true
            WITH   SECURITY_ENFORCED
        ];
        List<AQE_ProductDTO> dtos = new List<AQE_ProductDTO>();
        for (PricebookEntry pbe : pbes) {
            AQE_ProductDTO dto = new AQE_ProductDTO();
            dto.id               = pbe.Product2Id;
            dto.name             = pbe.Product2.Name;
            dto.productCode      = pbe.Product2.ProductCode;
            dto.description      = pbe.Product2.Description;
            dto.family           = pbe.Product2.Family;
            dto.isActive         = pbe.Product2.IsActive;
            dto.listPrice        = pbe.UnitPrice;
            dto.pricebookEntryId = pbe.Id;
            dtos.add(dto);
        }
        return dtos;
    }

    public Decimal getListPrice(String productCode, Id pricebookId) {
        List<PricebookEntry> pbes = [
            SELECT UnitPrice
            FROM   PricebookEntry
            WHERE  Product2.ProductCode = :productCode
            AND    Pricebook2Id = :pricebookId
            AND    IsActive = true
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        return pbes.isEmpty() ? null : pbes[0].UnitPrice;
    }

    public AQE_QuoteTotalsDTO calculateTotals(Id quoteId) {
        List<QuoteLineItem> qlis = [
            SELECT Quantity, UnitPrice, TotalPrice
            FROM   QuoteLineItem
            WHERE  QuoteId = :quoteId
            WITH   SECURITY_ENFORCED
        ];
        Decimal subtotal = 0, netTotal = 0;
        for (QuoteLineItem qli : qlis) {
            Decimal lineList = (qli.Quantity * qli.UnitPrice);
            subtotal += lineList;
            netTotal += qli.TotalPrice;
        }
        AQE_QuoteTotalsDTO totals = new AQE_QuoteTotalsDTO(subtotal, subtotal - netTotal);
        totals.lineCount = qlis.size();
        return totals;
    }

    // ─── Approval ─────────────────────────────────────────────────────────────

    public Id submitForApproval(Id quoteId, String comments) {
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(quoteId);
        req.setComments(comments);
        req.setSkipEntryCriteria(false);
        Approval.ProcessResult result = Approval.process(req);
        List<Id> workItemIds = result.getNewWorkItemIds();
        return workItemIds.isEmpty() ? null : workItemIds[0];
    }

    public String getEnvironmentType() {
        return ENV;
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static void applyCustomFields(SObject record, Map<String, Object> customFields) {
        if (customFields == null || customFields.isEmpty()) return;
        for (String fieldName : customFields.keySet()) {
            try {
                record.put(fieldName, customFields.get(fieldName));
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'AQE_StandardQuoteAdapter: Could not apply custom field ' + fieldName + ' — ' + e.getMessage());
            }
        }
    }
}
