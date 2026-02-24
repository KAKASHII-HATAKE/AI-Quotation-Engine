/**
 * @description Tests for AQE_ValidationEngine — the deterministic guard layer.
 * @namespace   aqe
 */
@IsTest
private class AQE_ValidationEngineTest {

    static Map<String, AQE_ProductDTO> buildProductMap(String code, Decimal listPrice) {
        AQE_ProductDTO p = new AQE_ProductDTO();
        p.productCode = code;
        p.listPrice   = listPrice;
        p.name        = 'Test Product ' + code;
        p.isActive    = true;
        return new Map<String, AQE_ProductDTO>{ code => p };
    }

    @IsTest
    static void testValidLines_passValidation() {
        AQE_QuoteLineDTO line = AQE_TestDataFactory.createLineDTO('LAPTOP-PRO', 10, 1000, 0);
        Map<String, AQE_ProductDTO> products = buildProductMap('LAPTOP-PRO', 1000);

        Test.startTest();
        AQE_ValidationEngine.ValidationResult result = AQE_ValidationEngine.validateQuoteLines(
            new List<AQE_QuoteLineDTO>{line},
            products,
            new List<AI_Discount_Rule__c>()
        );
        Test.stopTest();

        System.assertEquals(true, result.isValid, 'Valid line should pass validation');
        System.assertEquals(0, result.errors.size(), 'No errors expected for valid line');
        System.assertEquals(1, result.lines.size(), 'One line should be in result');
    }

    @IsTest
    static void testMissingProductCode_addsError() {
        AQE_QuoteLineDTO line = new AQE_QuoteLineDTO();
        line.quantity  = 5;
        line.listPrice = 500;

        Test.startTest();
        AQE_ValidationEngine.ValidationResult result = AQE_ValidationEngine.validateQuoteLines(
            new List<AQE_QuoteLineDTO>{line},
            new Map<String, AQE_ProductDTO>(),
            new List<AI_Discount_Rule__c>()
        );
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Missing product code should fail validation');
        System.assert(result.errors[0].contains('product code'), 'Error should mention product code');
    }

    @IsTest
    static void testUnknownProduct_addsError() {
        AQE_QuoteLineDTO line = AQE_TestDataFactory.createLineDTO('UNKNOWN-CODE', 5, 500, 0);

        Test.startTest();
        AQE_ValidationEngine.ValidationResult result = AQE_ValidationEngine.validateQuoteLines(
            new List<AQE_QuoteLineDTO>{line},
            new Map<String, AQE_ProductDTO>(), // Empty — product not found
            new List<AI_Discount_Rule__c>()
        );
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Unknown product should fail validation');
    }

    @IsTest
    static void testWrongUnitPrice_isCorrected() {
        AQE_QuoteLineDTO line = AQE_TestDataFactory.createLineDTO('LAPTOP-PRO', 10, 1000, 10); // 10% discount
        line.unitPrice = 800; // Wrong — should be 900 (10% off 1000)
        line.totalPrice = 8000;
        Map<String, AQE_ProductDTO> products = buildProductMap('LAPTOP-PRO', 1000);

        Test.startTest();
        AQE_ValidationEngine.ValidationResult result = AQE_ValidationEngine.validateQuoteLines(
            new List<AQE_QuoteLineDTO>{line},
            products,
            new List<AI_Discount_Rule__c>()
        );
        Test.stopTest();

        System.assertEquals(true, result.isValid, 'Should still be valid — price corrected');
        System.assertEquals(900, result.lines[0].unitPrice, 'Unit price should be corrected to 900');
        System.assertEquals(9000, result.lines[0].totalPrice, 'Total should be corrected to 9000');
        System.assert(!result.warnings.isEmpty(), 'Should have a warning about price correction');
    }

    @IsTest
    static void testNegativeDiscount_addsError() {
        AQE_QuoteLineDTO line = AQE_TestDataFactory.createLineDTO('LAPTOP-PRO', 5, 1000, 0);
        line.discountPercent = -5;
        Map<String, AQE_ProductDTO> products = buildProductMap('LAPTOP-PRO', 1000);

        Test.startTest();
        AQE_ValidationEngine.ValidationResult result = AQE_ValidationEngine.validateQuoteLines(
            new List<AQE_QuoteLineDTO>{line},
            products,
            new List<AI_Discount_Rule__c>()
        );
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Negative discount should fail validation');
    }

    @IsTest
    static void testValidateTotals_correctionApplied() {
        List<AQE_QuoteLineDTO> lines = new List<AQE_QuoteLineDTO>{
            AQE_TestDataFactory.createLineDTO('PROD-A', 5, 100, 0),
            AQE_TestDataFactory.createLineDTO('PROD-B', 2, 500, 10)
        };
        AQE_QuoteTotalsDTO totals = new AQE_QuoteTotalsDTO();
        totals.subtotal  = 999;  // Wrong
        totals.netTotal  = 888;  // Wrong

        Test.startTest();
        AQE_ValidationEngine.ValidationResult result = AQE_ValidationEngine.validateTotals(lines, totals);
        Test.stopTest();

        System.assert(!result.warnings.isEmpty(), 'Totals correction should generate warnings');
        // subtotal: 5*100 + 2*500 = 1500; netTotal: 500 + 2*450 = 1400
        System.assertEquals(1500, totals.subtotal, 'Subtotal should be corrected to 1500');
    }
}
