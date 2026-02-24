/**
 * @description Test data factory for AQE test classes.
 *              Centralises test record creation to keep test classes clean.
 * @namespace   aqe
 */
@IsTest
public class AQE_TestDataFactory {

    /** Creates and inserts a test Account */
    public static Account createAccount(String name, String type) {
        Account acc = new Account(Name = name, Type = type);
        insert acc;
        return acc;
    }

    /** Creates a test Product2 + PricebookEntry in the standard pricebook */
    public static Product2 createProduct(String name, String productCode, Decimal listPrice) {
        Product2 prod = new Product2(Name = name, ProductCode = productCode, IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id   = prod.Id,
            UnitPrice    = listPrice,
            IsActive     = true
        );
        insert pbe;
        return prod;
    }

    /** Creates and returns a test AI Pricing Rule record */
    public static AI_Pricing_Rule__c createPricingRule(
        String name, String productCode, String conditionText, String formulaText, Integer priority
    ) {
        AI_Pricing_Rule__c rule = new AI_Pricing_Rule__c(
            Name             = name,
            Product_Code__c  = productCode,
            Condition_Text__c = conditionText,
            Formula_Text__c  = formulaText,
            Priority__c      = priority,
            Active__c        = true,
            Rule_Category__c = 'Custom'
        );
        insert rule;
        return rule;
    }

    /** Creates and returns a test AI Discount Rule record */
    public static AI_Discount_Rule__c createDiscountRule(
        String name, Decimal maxDiscount, Decimal approvalThreshold, Boolean stackable
    ) {
        AI_Discount_Rule__c rule = new AI_Discount_Rule__c(
            Name                        = name,
            Discount_Type__c            = 'Percentage',
            Max_Discount_Percent__c     = maxDiscount,
            Approval_Required_Threshold__c = approvalThreshold,
            Stackable__c                = stackable,
            Active__c                   = true
        );
        insert rule;
        return rule;
    }

    /** Creates and returns a test AI Approval Policy record */
    public static AI_Approval_Policy__c createApprovalPolicy(
        String name, Decimal minDiscountThreshold, Decimal minDealValue, String chain
    ) {
        AI_Approval_Policy__c policy = new AI_Approval_Policy__c(
            Name                     = name,
            Min_Discount_Threshold__c = minDiscountThreshold,
            Min_Deal_Value__c        = minDealValue,
            Approval_Chain__c        = chain,
            Active__c                = true,
            Priority__c              = 1
        );
        insert policy;
        return policy;
    }

    /** Initialises AI Engine Config with engine active */
    public static void enableEngine() {
        AI_Engine_Config__c config = new AI_Engine_Config__c(
            Engine_Active__c           = true,
            Cloud_Environment__c       = AQE_CloudDetector.ENV_STANDARD,
            Max_Quote_Lines__c         = 30,
            Enable_PII_Tokenisation__c = true,
            Callout_Timeout_Seconds__c = 120,
            LLM_Model__c               = 'claude-sonnet-4-6'
        );
        upsert config;
    }

    /** Creates a test AQE_QuoteLineDTO with calculated prices */
    public static AQE_QuoteLineDTO createLineDTO(String productCode, Decimal qty, Decimal listPrice, Decimal discountPct) {
        AQE_QuoteLineDTO dto = new AQE_QuoteLineDTO();
        dto.productCode     = productCode;
        dto.quantity        = qty;
        dto.listPrice       = listPrice;
        dto.discountPercent = discountPct;
        dto.unitPrice       = listPrice * (1 - discountPct / 100);
        dto.totalPrice      = dto.unitPrice * qty;
        return dto;
    }

    /** Creates and inserts a test Opportunity for the given account */
    public static Opportunity createOpportunity(Id accountId) {
        Opportunity opp = new Opportunity(
            Name      = 'Test Opportunity',
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        return opp;
    }

    /** Creates a test Quote for the given account via an Opportunity (AccountId is derived from Opportunity) */
    public static Quote createQuote(Id accountId) {
        Opportunity opp = createOpportunity(accountId);
        Quote q = new Quote(
            Name          = 'Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id  = Test.getStandardPricebookId(),
            Status        = 'Draft',
            ExpirationDate = Date.today().addDays(30)
        );
        insert q;
        return q;
    }
}
