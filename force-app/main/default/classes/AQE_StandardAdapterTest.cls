/**
 * @description Tests for AQE_StandardQuoteAdapter — verifies quote CRUD via standard objects.
 * @namespace   aqe
 */
@IsTest
private class AQE_StandardAdapterTest {

    @TestSetup
    static void setup() {
        AQE_TestDataFactory.enableEngine();
        AQE_TestDataFactory.createAccount('Test Account', 'Enterprise');
        AQE_TestDataFactory.createProduct('Laptop Pro 15', 'LAPTOP-PRO-15', 1200.00);
        AQE_TestDataFactory.createProduct('Extended Warranty', 'EXT-WARRANTY', 150.00);
    }

    @IsTest
    static void testCreateAndGetQuote() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        AQE_StandardQuoteAdapter adapter = new AQE_StandardQuoteAdapter();

        AQE_QuoteDTO dto = new AQE_QuoteDTO(acc.Id, Test.getStandardPricebookId());
        dto.name           = 'Test Quote';
        dto.expirationDate = Date.today().addDays(30);

        Test.startTest();
        Id quoteId = adapter.createQuote(dto);
        AQE_QuoteDTO retrieved = adapter.getQuote(quoteId);
        Test.stopTest();

        System.assertNotEquals(null, quoteId, 'Quote ID should be created');
        System.assertEquals('Test Quote', retrieved.name, 'Quote name should match');
        System.assertEquals(acc.Id, retrieved.accountId, 'Account ID should match');
        System.assertEquals(AQE_CloudDetector.ENV_STANDARD, retrieved.cloudEnvironment);
    }

    @IsTest
    static void testCreateAndGetQuoteLines() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'LAPTOP-PRO-15' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];

        AQE_StandardQuoteAdapter adapter = new AQE_StandardQuoteAdapter();
        AQE_QuoteDTO dto = new AQE_QuoteDTO(acc.Id, Test.getStandardPricebookId());
        Id quoteId = adapter.createQuote(dto);

        AQE_QuoteLineDTO lineDTO = new AQE_QuoteLineDTO('LAPTOP-PRO-15', 5, 1200.00);
        lineDTO.product2Id       = prod.Id;
        lineDTO.pricebookEntryId = pbe.Id;

        Test.startTest();
        List<Id> lineIds = adapter.createQuoteLines(quoteId, new List<AQE_QuoteLineDTO>{lineDTO});
        List<AQE_QuoteLineDTO> lines = adapter.getQuoteLines(quoteId);
        Test.stopTest();

        System.assertEquals(1, lineIds.size(), 'One line ID should be returned');
        System.assertEquals(1, lines.size(), 'One line should be retrieved');
        System.assertEquals(5, lines[0].quantity, 'Quantity should match');
        System.assertEquals(1200.00, lines[0].unitPrice, 'Unit price should match');
    }

    @IsTest
    static void testCalculateTotals() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'LAPTOP-PRO-15' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];

        AQE_StandardQuoteAdapter adapter = new AQE_StandardQuoteAdapter();
        Id quoteId = adapter.createQuote(new AQE_QuoteDTO(acc.Id, Test.getStandardPricebookId()));

        AQE_QuoteLineDTO line = new AQE_QuoteLineDTO('LAPTOP-PRO-15', 10, 1200.00);
        line.product2Id = prod.Id;
        line.pricebookEntryId = pbe.Id;
        adapter.createQuoteLines(quoteId, new List<AQE_QuoteLineDTO>{line});

        Test.startTest();
        AQE_QuoteTotalsDTO totals = adapter.calculateTotals(quoteId);
        Test.stopTest();

        System.assertEquals(12000.00, totals.subtotal, 'Subtotal should be 10 * 1200 = 12000');
        System.assertEquals(1, totals.lineCount, 'Line count should be 1');
    }

    @IsTest
    static void testGetProducts_returnsMatchingProducts() {
        AQE_StandardQuoteAdapter adapter = new AQE_StandardQuoteAdapter();

        Test.startTest();
        List<AQE_ProductDTO> products = adapter.getProducts(
            new List<String>{'LAPTOP-PRO-15', 'EXT-WARRANTY'}
        );
        Test.stopTest();

        System.assertEquals(2, products.size(), 'Should return 2 products');
        Set<String> codes = new Set<String>();
        for (AQE_ProductDTO p : products) { codes.add(p.productCode); }
        System.assert(codes.contains('LAPTOP-PRO-15'), 'LAPTOP-PRO-15 should be found');
        System.assert(codes.contains('EXT-WARRANTY'), 'EXT-WARRANTY should be found');
    }

    @IsTest
    static void testGetEnvironmentType() {
        AQE_StandardQuoteAdapter adapter = new AQE_StandardQuoteAdapter();
        System.assertEquals(AQE_CloudDetector.ENV_STANDARD, adapter.getEnvironmentType());
    }
}
