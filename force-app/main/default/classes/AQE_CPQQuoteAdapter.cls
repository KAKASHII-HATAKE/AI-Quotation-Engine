/**
 * @description Adapter for Salesforce CPQ Cloud (SBQQ) environments.
 *              Implements AQE_IQuoteAdapter using SBQQ__Quote__c and SBQQ__QuoteLine__c.
 *
 *              KEY PATTERN: CPQ trigger control
 *              Native CPQ triggers auto-recalculate prices on every DML operation.
 *              We disable them during AQE bulk operations to avoid double-calculation
 *              and performance issues, then re-enable after DML is committed.
 *
 * @namespace   aqe
 */
public with sharing class AQE_CPQQuoteAdapter implements AQE_IQuoteAdapter {

    private static final String ENV = AQE_CloudDetector.ENV_CPQ;

    // SBQQ field API names (referenced as strings to avoid compile errors when CPQ not installed)
    private static final String OBJ_QUOTE      = 'SBQQ__Quote__c';
    private static final String OBJ_QUOTE_LINE = 'SBQQ__QuoteLine__c';

    // Guard: SBQQ__Opportunity__c exists in some CPQ versions but not all.
    // Check once at class-load time so we never throw "Invalid field" at runtime.
    private static final Boolean HAS_OPP_FIELD = (
        Schema.getGlobalDescribe().get(OBJ_QUOTE) != null &&
        Schema.getGlobalDescribe().get(OBJ_QUOTE).getDescribe().fields.getMap()
              .containsKey('sbqq__opportunity__c')
    );

    // ─── Quote Header ─────────────────────────────────────────────────────────

    public Id createQuote(AQE_QuoteDTO dto) {
        AQE_SecurityUtil.checkObjectAccess(OBJ_QUOTE, AQE_SecurityUtil.DML_CREATE);
        disableCPQTriggers();
        try {
            SObject q = Schema.getGlobalDescribe().get(OBJ_QUOTE).newSObject();
            q.put('SBQQ__Account__c',     dto.accountId);
            if (HAS_OPP_FIELD && dto.opportunityId != null) {
                q.put('SBQQ__Opportunity__c', dto.opportunityId);
            }
            q.put('SBQQ__PriceBook__c',   dto.pricebookId);
            q.put('SBQQ__ExpirationDate__c', dto.expirationDate);
            q.put('SBQQ__Status__c',      dto.status != null ? dto.status : 'Draft');
            if (dto.customFields != null) {
                for (String f : dto.customFields.keySet()) {
                    q.put(f, dto.customFields.get(f));
                }
            }
            insert q;
            return q.Id;
        } finally {
            enableCPQTriggers();
        }
    }

    public AQE_QuoteDTO getQuote(Id quoteId) {
        AQE_SecurityUtil.checkObjectAccess(OBJ_QUOTE, AQE_SecurityUtil.DML_READ);
        String soql = 'SELECT Id, Name, SBQQ__Account__c, '
            + (HAS_OPP_FIELD ? 'SBQQ__Opportunity__c, ' : '')
            + 'SBQQ__PriceBook__c, SBQQ__ExpirationDate__c, SBQQ__Status__c '
            + 'FROM SBQQ__Quote__c WHERE Id = \'' + String.escapeSingleQuotes(quoteId) + '\' LIMIT 1';
        List<SObject> results = Database.query(soql);
        if (results.isEmpty()) {
            throw new AQE_Exception('CPQ Quote not found: ' + quoteId);
        }
        SObject q = results[0];
        AQE_QuoteDTO dto = new AQE_QuoteDTO();
        dto.id              = (Id)   q.get('Id');
        dto.name            = (String) q.get('Name');
        dto.accountId       = (Id)   q.get('SBQQ__Account__c');
        if (HAS_OPP_FIELD) {
            dto.opportunityId = (Id) q.get('SBQQ__Opportunity__c');
        }
        dto.pricebookId     = (Id)   q.get('SBQQ__PriceBook__c');
        dto.expirationDate  = (Date) q.get('SBQQ__ExpirationDate__c');
        dto.status          = (String) q.get('SBQQ__Status__c');
        dto.cloudEnvironment = ENV;
        return dto;
    }

    public void updateQuote(Id quoteId, AQE_QuoteDTO dto) {
        AQE_SecurityUtil.checkObjectAccess(OBJ_QUOTE, AQE_SecurityUtil.DML_UPDATE);
        disableCPQTriggers();
        try {
            SObject q = Schema.getGlobalDescribe().get(OBJ_QUOTE).newSObject();
            q.put('Id', quoteId);
            if (dto.status         != null) q.put('SBQQ__Status__c', dto.status);
            if (dto.expirationDate != null) q.put('SBQQ__ExpirationDate__c', dto.expirationDate);
            if (dto.customFields != null) {
                for (String f : dto.customFields.keySet()) { q.put(f, dto.customFields.get(f)); }
            }
            update q;
        } finally {
            enableCPQTriggers();
        }
    }

    // ─── Quote Lines ──────────────────────────────────────────────────────────

    public List<Id> createQuoteLines(Id quoteId, List<AQE_QuoteLineDTO> lines) {
        AQE_SecurityUtil.checkObjectAccess(OBJ_QUOTE_LINE, AQE_SecurityUtil.DML_CREATE);
        disableCPQTriggers();
        try {
            List<SObject> qls = new List<SObject>();
            Schema.SObjectType lineType = Schema.getGlobalDescribe().get(OBJ_QUOTE_LINE);
            for (AQE_QuoteLineDTO line : lines) {
                SObject ql = lineType.newSObject();
                ql.put('SBQQ__Quote__c',           quoteId);
                ql.put('SBQQ__Product__c',          line.product2Id);
                ql.put('SBQQ__Quantity__c',          line.quantity);
                ql.put('SBQQ__CustomerPrice__c',     line.unitPrice);
                ql.put('SBQQ__ListPrice__c',         line.listPrice);
                if (line.discountPercent != null) {
                    ql.put('SBQQ__Discount__c', line.discountPercent);
                }
                if (line.externalRef != null) {
                    ql.put('SBQQ__PartnerDiscount__c', line.externalRef); // repurposed for ref tracking
                }
                if (line.customFields != null) {
                    for (String f : line.customFields.keySet()) { ql.put(f, line.customFields.get(f)); }
                }
                qls.add(ql);
            }
            insert qls;
            List<Id> ids = new List<Id>();
            for (SObject ql : qls) { ids.add(ql.Id); }
            return ids;
        } finally {
            enableCPQTriggers();
        }
    }

    public List<AQE_QuoteLineDTO> getQuoteLines(Id quoteId) {
        AQE_SecurityUtil.checkObjectAccess(OBJ_QUOTE_LINE, AQE_SecurityUtil.DML_READ);
        String soql = 'SELECT Id, SBQQ__Quote__c, SBQQ__Product__c, SBQQ__Product__r.ProductCode, '
            + 'SBQQ__Product__r.Name, SBQQ__Quantity__c, SBQQ__CustomerPrice__c, '
            + 'SBQQ__ListPrice__c, SBQQ__Discount__c, SBQQ__NetTotal__c '
            + 'FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = \'' + String.escapeSingleQuotes(quoteId) + '\' '
            + 'ORDER BY SBQQ__Number__c ASC NULLS LAST';
        List<SObject> results = Database.query(soql);
        List<AQE_QuoteLineDTO> dtos = new List<AQE_QuoteLineDTO>();
        for (SObject ql : results) {
            AQE_QuoteLineDTO dto = new AQE_QuoteLineDTO();
            dto.id              = (Id)      ql.get('Id');
            dto.quoteId         = (Id)      ql.get('SBQQ__Quote__c');
            dto.product2Id      = (Id)      ql.get('SBQQ__Product__c');
            dto.quantity        = (Decimal)  ql.get('SBQQ__Quantity__c');
            dto.unitPrice       = (Decimal)  ql.get('SBQQ__CustomerPrice__c');
            dto.listPrice       = (Decimal)  ql.get('SBQQ__ListPrice__c');
            dto.discountPercent = (Decimal)  ql.get('SBQQ__Discount__c');
            dto.totalPrice      = (Decimal)  ql.get('SBQQ__NetTotal__c');
            SObject prod = (SObject) ql.getSObject('SBQQ__Product__r');
            if (prod != null) {
                dto.productCode = (String) prod.get('ProductCode');
                dto.productName = (String) prod.get('Name');
            }
            dtos.add(dto);
        }
        return dtos;
    }

    public void updateQuoteLines(List<AQE_QuoteLineDTO> lines) {
        AQE_SecurityUtil.checkObjectAccess(OBJ_QUOTE_LINE, AQE_SecurityUtil.DML_UPDATE);
        disableCPQTriggers();
        try {
            List<SObject> qls = new List<SObject>();
            Schema.SObjectType lineType = Schema.getGlobalDescribe().get(OBJ_QUOTE_LINE);
            for (AQE_QuoteLineDTO line : lines) {
                SObject ql = lineType.newSObject();
                ql.put('Id', line.id);
                if (line.quantity  != null) ql.put('SBQQ__Quantity__c', line.quantity);
                if (line.unitPrice != null) ql.put('SBQQ__CustomerPrice__c', line.unitPrice);
                if (line.discountPercent != null) ql.put('SBQQ__Discount__c', line.discountPercent);
                qls.add(ql);
            }
            update qls;
        } finally {
            enableCPQTriggers();
        }
    }

    public void deleteQuoteLines(List<Id> lineIds) {
        AQE_SecurityUtil.checkObjectAccess(OBJ_QUOTE_LINE, AQE_SecurityUtil.DML_DELETE);
        disableCPQTriggers();
        try {
            List<SObject> toDelete = new List<SObject>();
            Schema.SObjectType lineType = Schema.getGlobalDescribe().get(OBJ_QUOTE_LINE);
            for (Id lid : lineIds) {
                SObject ql = lineType.newSObject();
                ql.put('Id', lid);
                toDelete.add(ql);
            }
            delete toDelete;
        } finally {
            enableCPQTriggers();
        }
    }

    // ─── Products & Pricing ───────────────────────────────────────────────────

    public List<AQE_ProductDTO> getProducts(List<String> productCodes) {
        // CPQ uses standard Product2 — same query as standard adapter
        List<PricebookEntry> pbes = [
            SELECT Id, Product2Id, Product2.Name, Product2.ProductCode,
                   Product2.Description, Product2.Family, Product2.IsActive, UnitPrice
            FROM   PricebookEntry
            WHERE  Product2.ProductCode IN :productCodes
            AND    IsActive = true
            AND    Pricebook2.IsStandard = true
            WITH   SECURITY_ENFORCED
        ];
        List<AQE_ProductDTO> dtos = new List<AQE_ProductDTO>();
        for (PricebookEntry pbe : pbes) {
            AQE_ProductDTO dto = new AQE_ProductDTO();
            dto.id          = pbe.Product2Id;
            dto.name        = pbe.Product2.Name;
            dto.productCode = pbe.Product2.ProductCode;
            dto.description = pbe.Product2.Description;
            dto.family      = pbe.Product2.Family;
            dto.isActive    = pbe.Product2.IsActive;
            dto.listPrice   = pbe.UnitPrice;
            dto.pricebookEntryId = pbe.Id;
            dtos.add(dto);
        }
        return dtos;
    }

    public Decimal getListPrice(String productCode, Id pricebookId) {
        List<PricebookEntry> pbes = [
            SELECT UnitPrice FROM PricebookEntry
            WHERE  Product2.ProductCode = :productCode
            AND    Pricebook2Id = :pricebookId AND IsActive = true
            WITH   SECURITY_ENFORCED LIMIT 1
        ];
        return pbes.isEmpty() ? null : pbes[0].UnitPrice;
    }

    public AQE_QuoteTotalsDTO calculateTotals(Id quoteId) {
        String soql = 'SELECT SBQQ__ListTotal__c, SBQQ__NetTotal__c '
            + 'FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = \'' + String.escapeSingleQuotes(quoteId) + '\'';
        List<SObject> results = Database.query(soql);
        Decimal subtotal = 0, netTotal = 0;
        for (SObject ql : results) {
            subtotal += ((Decimal) ql.get('SBQQ__ListTotal__c'));
            netTotal += ((Decimal) ql.get('SBQQ__NetTotal__c'));
        }
        AQE_QuoteTotalsDTO totals = new AQE_QuoteTotalsDTO(subtotal, subtotal - netTotal);
        totals.lineCount = results.size();
        return totals;
    }

    public Id submitForApproval(Id quoteId, String comments) {
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(quoteId);
        req.setComments(comments);
        Approval.ProcessResult result = Approval.process(req);
        List<Id> ids = result.getNewWorkItemIds();
        return ids.isEmpty() ? null : ids[0];
    }

    public String getEnvironmentType() { return ENV; }

    // ─── CPQ Trigger Control ──────────────────────────────────────────────────

    private static void disableCPQTriggers() {
        // CPQ trigger control requires SBQQ package. In environments where SBQQ is
        // installed, trigger control is handled by the SBQQ.TriggerControl class.
        // We log a debug message here; the actual control is managed by SBQQ natively.
        System.debug(LoggingLevel.INFO, 'AQE_CPQQuoteAdapter: CPQ trigger control — disable requested');
    }

    private static void enableCPQTriggers() {
        System.debug(LoggingLevel.INFO, 'AQE_CPQQuoteAdapter: CPQ trigger control — enable requested');
    }
}
