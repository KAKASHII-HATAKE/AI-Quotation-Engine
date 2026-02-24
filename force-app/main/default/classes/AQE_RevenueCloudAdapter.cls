/**
 * @description Adapter for Salesforce Revenue Cloud environments.
 *              Implements AQE_IQuoteAdapter using Order and OrderItem objects
 *              (Revenue Cloud's primary quoting entities), with support for
 *              asset-based ordering and recurring revenue schedules.
 * @namespace   aqe
 */
public with sharing class AQE_RevenueCloudAdapter implements AQE_IQuoteAdapter {

    private static final String ENV = AQE_CloudDetector.ENV_REVENUE;

    // ─── Quote Header (Revenue Cloud uses Order as quote) ─────────────────────

    public Id createQuote(AQE_QuoteDTO dto) {
        AQE_SecurityUtil.checkObjectAccess('Order', AQE_SecurityUtil.DML_CREATE);
        Order o = new Order(
            AccountId    = dto.accountId,
            Pricebook2Id = dto.pricebookId,
            EffectiveDate = Date.today(),
            Status       = 'Draft',
            Type         = 'AQE_Quote'
        );
        if (dto.description != null) {
            // Use Description__c if available, otherwise use standard field
            Map<String, Schema.SObjectField> fields = Schema.SObjectType.Order.fields.getMap();
            if (fields.containsKey('description')) {
                o.put('Description', dto.description);
            }
        }
        if (dto.customFields != null) {
            for (String f : dto.customFields.keySet()) {
                try { o.put(f, dto.customFields.get(f)); } catch (Exception e) {}
            }
        }
        insert o;
        return o.Id;
    }

    public AQE_QuoteDTO getQuote(Id quoteId) {
        AQE_SecurityUtil.checkObjectAccess('Order', AQE_SecurityUtil.DML_READ);
        Order o = [
            SELECT Id, Name, AccountId, Pricebook2Id, Status
            FROM   Order
            WHERE  Id = :quoteId
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        AQE_QuoteDTO dto = new AQE_QuoteDTO();
        dto.id              = o.Id;
        dto.name            = o.Name;
        dto.accountId       = o.AccountId;
        dto.pricebookId     = o.Pricebook2Id;
        dto.status          = o.Status;
        dto.cloudEnvironment = ENV;
        return dto;
    }

    public void updateQuote(Id quoteId, AQE_QuoteDTO dto) {
        AQE_SecurityUtil.checkObjectAccess('Order', AQE_SecurityUtil.DML_UPDATE);
        Order o = new Order(Id = quoteId);
        if (dto.status != null) o.Status = dto.status;
        if (dto.customFields != null) {
            for (String f : dto.customFields.keySet()) {
                try { o.put(f, dto.customFields.get(f)); } catch (Exception e) {}
            }
        }
        update o;
    }

    // ─── Quote Lines (OrderItem) ───────────────────────────────────────────────

    public List<Id> createQuoteLines(Id quoteId, List<AQE_QuoteLineDTO> lines) {
        AQE_SecurityUtil.checkObjectAccess('OrderItem', AQE_SecurityUtil.DML_CREATE);
        List<OrderItem> items = new List<OrderItem>();
        for (AQE_QuoteLineDTO line : lines) {
            OrderItem oi = new OrderItem(
                OrderId         = quoteId,
                Product2Id      = line.product2Id,
                PricebookEntryId = line.pricebookEntryId,
                Quantity        = line.quantity,
                UnitPrice       = line.unitPrice,
                Description     = line.description
            );
            if (line.customFields != null) {
                for (String f : line.customFields.keySet()) {
                    try { oi.put(f, line.customFields.get(f)); } catch (Exception e) {}
                }
            }
            items.add(oi);
        }
        insert items;
        List<Id> ids = new List<Id>();
        for (OrderItem oi : items) { ids.add(oi.Id); }
        return ids;
    }

    public List<AQE_QuoteLineDTO> getQuoteLines(Id quoteId) {
        AQE_SecurityUtil.checkObjectAccess('OrderItem', AQE_SecurityUtil.DML_READ);
        List<OrderItem> items = [
            SELECT Id, OrderId, Product2Id, Product2.ProductCode, Product2.Name,
                   PricebookEntryId, Quantity, UnitPrice, TotalPrice, Description
            FROM   OrderItem
            WHERE  OrderId = :quoteId
            WITH   SECURITY_ENFORCED
        ];
        List<AQE_QuoteLineDTO> dtos = new List<AQE_QuoteLineDTO>();
        for (OrderItem oi : items) {
            AQE_QuoteLineDTO dto = new AQE_QuoteLineDTO();
            dto.id               = oi.Id;
            dto.quoteId          = oi.OrderId;
            dto.product2Id       = oi.Product2Id;
            dto.productCode      = oi.Product2.ProductCode;
            dto.productName      = oi.Product2.Name;
            dto.pricebookEntryId = oi.PricebookEntryId;
            dto.quantity         = oi.Quantity;
            dto.unitPrice        = oi.UnitPrice;
            dto.totalPrice       = oi.TotalPrice;
            dto.description      = oi.Description;
            dtos.add(dto);
        }
        return dtos;
    }

    public void updateQuoteLines(List<AQE_QuoteLineDTO> lines) {
        AQE_SecurityUtil.checkObjectAccess('OrderItem', AQE_SecurityUtil.DML_UPDATE);
        List<OrderItem> items = new List<OrderItem>();
        for (AQE_QuoteLineDTO line : lines) {
            OrderItem oi = new OrderItem(Id = line.id);
            if (line.quantity  != null) oi.Quantity  = line.quantity;
            if (line.unitPrice != null) oi.UnitPrice = line.unitPrice;
            items.add(oi);
        }
        update items;
    }

    public void deleteQuoteLines(List<Id> lineIds) {
        AQE_SecurityUtil.checkObjectAccess('OrderItem', AQE_SecurityUtil.DML_DELETE);
        List<OrderItem> toDelete = new List<OrderItem>();
        for (Id lid : lineIds) { toDelete.add(new OrderItem(Id = lid)); }
        delete toDelete;
    }

    // ─── Products & Pricing ───────────────────────────────────────────────────

    public List<AQE_ProductDTO> getProducts(List<String> productCodes) {
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
        List<OrderItem> items = [
            SELECT Quantity, UnitPrice, TotalPrice
            FROM   OrderItem
            WHERE  OrderId = :quoteId
            WITH   SECURITY_ENFORCED
        ];
        Decimal subtotal = 0, netTotal = 0;
        for (OrderItem oi : items) {
            subtotal += (oi.Quantity * oi.UnitPrice);
            netTotal += oi.TotalPrice;
        }
        AQE_QuoteTotalsDTO totals = new AQE_QuoteTotalsDTO(subtotal, subtotal - netTotal);
        totals.lineCount = items.size();
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
}
