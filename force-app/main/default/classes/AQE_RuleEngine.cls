/**
 * @description Evaluates AI_Pricing_Rule__c, AI_Product_Rule__c, and AI_Discount_Rule__c
 *              records against quote context and returns applicable rules.
 *
 *              Rules are loaded from Salesforce custom objects (no hardcoding).
 *              Context evaluation uses a token-replacement approach where
 *              {FieldName} placeholders in rule text are replaced with actual quote values.
 *
 *              The LLM handles natural language parsing of rule text.
 *              This engine handles deterministic pre/post filtering:
 *              - Effective date range checks
 *              - Active flag checks
 *              - Product code matching
 *
 * @namespace   aqe
 */
public with sharing class AQE_RuleEngine {

    /**
     * Loads all active pricing rules applicable to the given product codes.
     * Filters by Active__c = true, date range, and product code match.
     * @param productCodes  List of Product2.ProductCode values from the quote
     * @param quoteDate     Quote date for effective date range evaluation
     * @return List of matching AI_Pricing_Rule__c records
     */
    public static List<AI_Pricing_Rule__c> getApplicablePricingRules(
        List<String> productCodes, Date quoteDate
    ) {
        if (productCodes == null || productCodes.isEmpty()) {
            return new List<AI_Pricing_Rule__c>();
        }

        List<AI_Pricing_Rule__c> allRules = [
            SELECT Id, Name, Product_Code__c, Condition_Text__c, Formula_Text__c,
                   Rule_Category__c, Priority__c, Effective_Date__c, Expiry_Date__c
            FROM   AI_Pricing_Rule__c
            WHERE  Active__c = true
            AND    (Effective_Date__c = null OR Effective_Date__c <= :quoteDate)
            AND    (Expiry_Date__c    = null OR Expiry_Date__c    >= :quoteDate)
            WITH   SECURITY_ENFORCED
            ORDER BY Priority__c ASC NULLS LAST
        ];

        return filterByProductCodes(allRules, productCodes);
    }

    /**
     * Loads all active product rules applicable to the given product codes.
     * @param productCodes List of Product2.ProductCode values in the quote
     * @return List of matching AI_Product_Rule__c records
     */
    public static List<AI_Product_Rule__c> getApplicableProductRules(List<String> productCodes) {
        if (productCodes == null || productCodes.isEmpty()) {
            return new List<AI_Product_Rule__c>();
        }

        return [
            SELECT Id, Name, Rule_Type__c, Primary_Product_Code__c, Related_Product_Codes__c,
                   Rule_Text__c, Bundle_Discount_Percent__c, Priority__c
            FROM   AI_Product_Rule__c
            WHERE  Active__c = true
            AND    Primary_Product_Code__c IN :productCodes
            WITH   SECURITY_ENFORCED
            ORDER BY Priority__c ASC NULLS LAST
        ];
    }

    /**
     * Loads all active discount rules applicable on the given date.
     * @param quoteDate Quote date for effective date range evaluation
     * @return List of matching AI_Discount_Rule__c records, ordered by priority
     */
    public static List<AI_Discount_Rule__c> getApplicableDiscountRules(Date quoteDate) {
        return [
            SELECT Id, Name, Discount_Type__c, Discount_Value__c, Max_Discount_Percent__c,
                   Approval_Required_Threshold__c, Stackable__c, Condition_Text__c,
                   Effective_Date__c, Expiry_Date__c
            FROM   AI_Discount_Rule__c
            WHERE  Active__c = true
            AND    (Effective_Date__c = null OR Effective_Date__c <= :quoteDate)
            AND    (Expiry_Date__c    = null OR Expiry_Date__c    >= :quoteDate)
            WITH   SECURITY_ENFORCED
            ORDER BY Discount_Value__c DESC NULLS LAST
        ];
    }

    /**
     * Loads all active approval policies, ordered by priority.
     * @return List of AI_Approval_Policy__c records
     */
    public static List<AI_Approval_Policy__c> getAllApprovalPolicies() {
        return [
            SELECT Id, Name, Trigger_Condition__c, Approval_Chain__c,
                   Auto_Approve_Condition__c, Min_Discount_Threshold__c,
                   Min_Deal_Value__c, Priority__c
            FROM   AI_Approval_Policy__c
            WHERE  Active__c = true
            WITH   SECURITY_ENFORCED
            ORDER BY Priority__c ASC NULLS LAST
        ];
    }

    /**
     * Serialises applicable rules into a compact context string for the LLM system prompt.
     * Only includes the natural language text fields — no internal Salesforce IDs.
     * @param pricingRules  Applicable pricing rules
     * @param productRules  Applicable product rules
     * @param discountRules Applicable discount rules
     * @return JSON string representation of rules for LLM context
     */
    public static String buildRuleContext(
        List<AI_Pricing_Rule__c> pricingRules,
        List<AI_Product_Rule__c> productRules,
        List<AI_Discount_Rule__c> discountRules
    ) {
        Map<String, Object> context = new Map<String, Object>();

        List<Map<String, Object>> prList = new List<Map<String, Object>>();
        for (AI_Pricing_Rule__c r : pricingRules) {
            prList.add(new Map<String, Object>{
                'name'      => r.Name,
                'category'  => r.Rule_Category__c,
                'condition' => r.Condition_Text__c,
                'formula'   => r.Formula_Text__c
            });
        }
        context.put('pricing_rules', prList);

        List<Map<String, Object>> prRuleList = new List<Map<String, Object>>();
        for (AI_Product_Rule__c r : productRules) {
            prRuleList.add(new Map<String, Object>{
                'name'             => r.Name,
                'type'             => r.Rule_Type__c,
                'primary_product'  => r.Primary_Product_Code__c,
                'related_products' => r.Related_Product_Codes__c,
                'rule_text'        => r.Rule_Text__c,
                'bundle_discount'  => r.Bundle_Discount_Percent__c
            });
        }
        context.put('product_rules', prRuleList);

        List<Map<String, Object>> drList = new List<Map<String, Object>>();
        for (AI_Discount_Rule__c r : discountRules) {
            drList.add(new Map<String, Object>{
                'name'                => r.Name,
                'type'                => r.Discount_Type__c,
                'value'               => r.Discount_Value__c,
                'max_percent'         => r.Max_Discount_Percent__c,
                'approval_threshold'  => r.Approval_Required_Threshold__c,
                'stackable'           => r.Stackable__c,
                'condition'           => r.Condition_Text__c
            });
        }
        context.put('discount_rules', drList);

        return JSON.serialize(context);
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    /**
     * Filters rules by product code. Supports wildcard '*' and comma-separated codes.
     */
    private static List<AI_Pricing_Rule__c> filterByProductCodes(
        List<AI_Pricing_Rule__c> rules, List<String> productCodes
    ) {
        Set<String> codeSet = new Set<String>(productCodes);
        List<AI_Pricing_Rule__c> matched = new List<AI_Pricing_Rule__c>();
        for (AI_Pricing_Rule__c rule : rules) {
            if (String.isBlank(rule.Product_Code__c)) {
                matched.add(rule);
                continue;
            }
            if (rule.Product_Code__c.trim() == '*') {
                matched.add(rule);
                continue;
            }
            List<String> ruleCodes = rule.Product_Code__c.split(',');
            for (String code : ruleCodes) {
                if (codeSet.contains(code.trim())) {
                    matched.add(rule);
                    break;
                }
            }
        }
        return matched;
    }
}
