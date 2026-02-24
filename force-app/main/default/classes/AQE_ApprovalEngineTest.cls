/**
 * @description Tests for AQE_ApprovalEngine.
 * @namespace   aqe
 */
@IsTest
private class AQE_ApprovalEngineTest {

    @TestSetup
    static void setup() {
        AQE_TestDataFactory.createApprovalPolicy(
            'High Discount Policy', 15.0, 10000, 'LEVEL 1: Sales Manager -> 24h -> LEVEL 2: VP Sales'
        );
        AQE_TestDataFactory.createApprovalPolicy(
            'Very High Value Policy', 0.0, 100000, 'LEVEL 1: VP Sales -> 12h -> LEVEL 2: CEO'
        );
    }

    @IsTest
    static void testBelowAllThresholds_noApprovalRequired() {
        AQE_QuoteDTO quote    = new AQE_QuoteDTO();
        AQE_QuoteTotalsDTO totals = new AQE_QuoteTotalsDTO(5000, 250); // 5% discount
        List<AI_Approval_Policy__c> policies = AQE_RuleEngine.getAllApprovalPolicies();

        Test.startTest();
        AQE_ApprovalEngine.ApprovalDecision decision = AQE_ApprovalEngine.evaluate(
            quote, new List<AQE_QuoteLineDTO>(), totals, policies
        );
        Test.stopTest();

        System.assertEquals(false, decision.required, 'Below thresholds — no approval should be required');
    }

    @IsTest
    static void testAboveDiscountThreshold_approvalRequired() {
        AQE_QuoteDTO quote = new AQE_QuoteDTO();
        // 20% effective discount on $50k deal
        AQE_QuoteTotalsDTO totals = new AQE_QuoteTotalsDTO(50000, 10000);
        List<AI_Approval_Policy__c> policies = AQE_RuleEngine.getAllApprovalPolicies();

        Test.startTest();
        AQE_ApprovalEngine.ApprovalDecision decision = AQE_ApprovalEngine.evaluate(
            quote, new List<AQE_QuoteLineDTO>(), totals, policies
        );
        Test.stopTest();

        System.assertEquals(true, decision.required, '20% discount on $50k should require approval');
        System.assertNotEquals(null, decision.policyName, 'Policy name should be set');
        System.assertNotEquals(null, decision.approvalChain, 'Approval chain should be set');
    }

    @IsTest
    static void testAboveDealValueThreshold_approvalRequired() {
        AQE_QuoteDTO quote = new AQE_QuoteDTO();
        // Small discount but very large deal
        AQE_QuoteTotalsDTO totals = new AQE_QuoteTotalsDTO(150000, 1500); // 1% discount
        List<AI_Approval_Policy__c> policies = AQE_RuleEngine.getAllApprovalPolicies();

        Test.startTest();
        AQE_ApprovalEngine.ApprovalDecision decision = AQE_ApprovalEngine.evaluate(
            quote, new List<AQE_QuoteLineDTO>(), totals, policies
        );
        Test.stopTest();

        System.assertEquals(true, decision.required, '$150k deal should require approval (>$100k threshold)');
    }

    @IsTest
    static void testNoPolicies_noApprovalRequired() {
        AQE_QuoteDTO quote = new AQE_QuoteDTO();
        AQE_QuoteTotalsDTO totals = new AQE_QuoteTotalsDTO(1000000, 500000);

        Test.startTest();
        AQE_ApprovalEngine.ApprovalDecision decision = AQE_ApprovalEngine.evaluate(
            quote, new List<AQE_QuoteLineDTO>(), totals, new List<AI_Approval_Policy__c>()
        );
        Test.stopTest();

        System.assertEquals(false, decision.required, 'No policies = no approval required');
    }

    @IsTest
    static void testGetActiveDelegateRole_noDelegate() {
        Test.startTest();
        String delegate = AQE_ApprovalEngine.getActiveDelegateRole('SalesManager', DateTime.now());
        Test.stopTest();

        System.assertEquals(null, delegate, 'No delegate configured — should return null');
    }

    @IsTest
    static void testGetActiveDelegateRole_activeDelegate() {
        AI_Delegate_Config__c dc = new AI_Delegate_Config__c(
            Name                    = 'Test Delegation',
            Primary_Approver_Role__c = 'SalesManager',
            Delegate_Approver_Role__c = 'RegionalDirector',
            Active__c               = true,
            Delegation_Start__c     = DateTime.now().addDays(-1),
            Delegation_End__c       = DateTime.now().addDays(1)
        );
        insert dc;

        Test.startTest();
        String delegate = AQE_ApprovalEngine.getActiveDelegateRole('SalesManager', DateTime.now());
        Test.stopTest();

        System.assertEquals('RegionalDirector', delegate, 'Active delegation should be returned');
    }
}
