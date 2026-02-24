/**
 * @description Tests for AQE_SecurityUtil.
 * @namespace   aqe
 */
@IsTest
private class AQE_SecurityUtilTest {

    @IsTest
    static void testCheckObjectAccess_validRead() {
        // Quote object should be accessible to any Salesforce user
        Test.startTest();
        try {
            AQE_SecurityUtil.checkObjectAccess('Quote', AQE_SecurityUtil.DML_READ);
            System.assert(true, 'Quote READ access should succeed');
        } catch (AQE_Exception e) {
            System.assert(false, 'Unexpected exception: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testCheckObjectAccess_invalidObject() {
        Test.startTest();
        try {
            AQE_SecurityUtil.checkObjectAccess('NonExistentObject__xyz', AQE_SecurityUtil.DML_READ);
            System.assert(false, 'Should throw AQE_Exception for non-existent object');
        } catch (AQE_Exception e) {
            System.assert(e.getMessage().contains('not found'), 'Exception message should mention not found');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSanitiseForSoql_escapesQuotes() {
        Test.startTest();
        String input  = 'O\'Brien';
        String output = AQE_SecurityUtil.sanitiseForSoql(input);
        Test.stopTest();

        System.assertEquals('O\\\'Brien', output, 'Single quotes should be escaped');
    }

    @IsTest
    static void testSanitiseForSoql_handlesNull() {
        Test.startTest();
        String output = AQE_SecurityUtil.sanitiseForSoql(null);
        Test.stopTest();

        System.assertEquals(null, output, 'Null input should return null');
    }

    @IsTest
    static void testIsValidSalesforceId_validId() {
        Id testId = UserInfo.getUserId();
        Test.startTest();
        Boolean valid = AQE_SecurityUtil.isValidSalesforceId(testId);
        Test.stopTest();

        System.assertEquals(true, valid, 'Valid Salesforce ID should return true');
    }

    @IsTest
    static void testIsValidSalesforceId_invalidId() {
        Test.startTest();
        Boolean valid = AQE_SecurityUtil.isValidSalesforceId('notanid');
        Test.stopTest();

        System.assertEquals(false, valid, 'Invalid ID string should return false');
    }

    @IsTest
    static void testIsValidSalesforceId_null() {
        Test.startTest();
        Boolean valid = AQE_SecurityUtil.isValidSalesforceId(null);
        Test.stopTest();

        System.assertEquals(false, valid, 'Null should return false');
    }

    @IsTest
    static void testCheckGovernorLimits_withinLimits() {
        Test.startTest();
        try {
            AQE_SecurityUtil.checkGovernorLimits();
            System.assert(true, 'Should not throw when limits are not near threshold');
        } catch (AQE_Exception e) {
            System.assert(false, 'Should not throw exception at start of test: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
