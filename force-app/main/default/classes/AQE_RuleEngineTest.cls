/**
 * @description Tests for AQE_RuleEngine.
 * @namespace   aqe
 */
@IsTest
private class AQE_RuleEngineTest {

    @TestSetup
    static void setup() {
        // Active pricing rule
        AQE_TestDataFactory.createPricingRule(
            'Test Volume Rule', 'LAPTOP-PRO', 'WHEN {Quantity} >= 100', 'DISCOUNT 15%', 1
        );
        // Expired pricing rule (should not appear)
        AI_Pricing_Rule__c expired = new AI_Pricing_Rule__c(
            Name             = 'Expired Rule',
            Product_Code__c  = 'LAPTOP-PRO',
            Active__c        = true,
            Expiry_Date__c   = Date.today().addDays(-1)
        );
        insert expired;
        // Inactive rule (should not appear)
        AI_Pricing_Rule__c inactive = new AI_Pricing_Rule__c(
            Name             = 'Inactive Rule',
            Product_Code__c  = 'LAPTOP-PRO',
            Active__c        = false
        );
        insert inactive;

        // Discount rules
        AQE_TestDataFactory.createDiscountRule('Standard Discount', 20, 15, false);

        // Approval policy
        AQE_TestDataFactory.createApprovalPolicy('High Value Policy', 15, 50000, 'LEVEL 1: Sales Manager');
    }

    @IsTest
    static void testGetApplicablePricingRules_matchesProductCode() {
        Test.startTest();
        List<AI_Pricing_Rule__c> rules = AQE_RuleEngine.getApplicablePricingRules(
            new List<String>{'LAPTOP-PRO'}, Date.today()
        );
        Test.stopTest();

        System.assertEquals(1, rules.size(), 'Only the active, non-expired rule should be returned');
        System.assertEquals('Test Volume Rule', rules[0].Name);
    }

    @IsTest
    static void testGetApplicablePricingRules_noMatch() {
        Test.startTest();
        List<AI_Pricing_Rule__c> rules = AQE_RuleEngine.getApplicablePricingRules(
            new List<String>{'NONEXISTENT-CODE'}, Date.today()
        );
        Test.stopTest();

        System.assertEquals(0, rules.size(), 'No rules should match an unknown product code');
    }

    @IsTest
    static void testGetApplicablePricingRules_emptyList() {
        Test.startTest();
        List<AI_Pricing_Rule__c> rules = AQE_RuleEngine.getApplicablePricingRules(
            new List<String>(), Date.today()
        );
        Test.stopTest();

        System.assertEquals(0, rules.size(), 'Empty product list should return empty rules');
    }

    @IsTest
    static void testGetApplicableDiscountRules() {
        Test.startTest();
        List<AI_Discount_Rule__c> rules = AQE_RuleEngine.getApplicableDiscountRules(Date.today());
        Test.stopTest();

        System.assert(!rules.isEmpty(), 'Should return active discount rules');
        System.assertEquals('Standard Discount', rules[0].Name);
    }

    @IsTest
    static void testGetAllApprovalPolicies() {
        Test.startTest();
        List<AI_Approval_Policy__c> policies = AQE_RuleEngine.getAllApprovalPolicies();
        Test.stopTest();

        System.assertEquals(1, policies.size(), 'Should return 1 active approval policy');
        System.assertEquals('High Value Policy', policies[0].Name);
    }

    @IsTest
    static void testBuildRuleContext_serializesAllRuleTypes() {
        List<AI_Pricing_Rule__c> pr = AQE_RuleEngine.getApplicablePricingRules(
            new List<String>{'LAPTOP-PRO'}, Date.today()
        );
        List<AI_Product_Rule__c> prodr = new List<AI_Product_Rule__c>();
        List<AI_Discount_Rule__c> dr = AQE_RuleEngine.getApplicableDiscountRules(Date.today());

        Test.startTest();
        String context = AQE_RuleEngine.buildRuleContext(pr, prodr, dr);
        Test.stopTest();

        System.assertNotEquals(null, context, 'Rule context should not be null');
        System.assert(context.contains('pricing_rules'), 'Context should include pricing_rules key');
        System.assert(context.contains('discount_rules'), 'Context should include discount_rules key');
    }
}
