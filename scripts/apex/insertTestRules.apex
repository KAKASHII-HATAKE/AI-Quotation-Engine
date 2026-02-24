// ─── Insert test rules to verify conditional rule enforcement ─────────────────
// Run with: sf apex run --file scripts/apex/insertTestRules.apex

// 1. Discount Rule — cap laptop discounts at 15%, approval above 10%
AI_Discount_Rule__c discRule = new AI_Discount_Rule__c(
    Name                       = 'Laptop Max 15% Discount',
    Discount_Type__c           = 'Percentage',
    Discount_Value__c          = 15.0,
    Max_Discount_Percent__c    = 15.0,
    Approval_Required_Threshold__c = 10.0,
    Stackable__c               = false,
    Condition_Text__c          = 'Applies to all laptop products. Maximum 15% discount. Discounts above 10% require manager approval.',
    Effective_Date__c          = Date.today().addDays(-1),
    Active__c                  = true
);
insert discRule;
System.debug('Inserted Discount Rule: ' + discRule.Id);

// 2. Pricing Rule — enterprise accounts get 12% off laptops
AI_Pricing_Rule__c priceRule = new AI_Pricing_Rule__c(
    Name             = 'Enterprise Laptop Pricing',
    Product_Code__c  = 'LAPTOP13,LAPTOP15',
    Rule_Category__c = 'Enterprise',
    Condition_Text__c = 'When account type is Enterprise, apply 12% standard discount to laptop products.',
    Formula_Text__c  = 'unit_price = list_price * 0.88',
    Priority__c      = 1,
    Effective_Date__c = Date.today().addDays(-1),
    Active__c        = true
);
insert priceRule;
System.debug('Inserted Pricing Rule: ' + priceRule.Id);

// 3. Product Rule — bundle: LAPTOP15 + WARRANTYEXTENSION gets extra 5% on warranty
AI_Product_Rule__c prodRule = new AI_Product_Rule__c(
    Name                    = 'Laptop Pro 15 + Warranty Bundle',
    Rule_Type__c            = 'Bundle',
    Primary_Product_Code__c = 'LAPTOP15',
    Related_Product_Codes__c = 'WARRANTYEXTENSION',
    Rule_Text__c            = 'When Laptop Pro 15 and Extended Warranty appear on the same quote, apply an additional 5% bundle discount to the warranty line.',
    Bundle_Discount_Percent__c = 5.0,
    Priority__c             = 1,
    Active__c               = true
);
insert prodRule;
System.debug('Inserted Product Rule: ' + prodRule.Id);

// 4. Approval Policy — deals above $50,000 need Sales Manager approval
AI_Approval_Policy__c approvalPolicy = new AI_Approval_Policy__c(
    Name                    = 'High Value Deal Approval',
    Trigger_Condition__c    = 'net_total >= 50000',
    Approval_Chain__c       = 'Sales Manager',
    Min_Deal_Value__c       = 50000,
    Auto_Approve_Condition__c = null,
    Priority__c             = 1,
    Active__c               = true
);
insert approvalPolicy;
System.debug('Inserted Approval Policy: ' + approvalPolicy.Id);

System.debug('✅ All test rules inserted successfully.');
System.debug('Rules summary:');
System.debug('  - Discount: max 15%, approval > 10%');
System.debug('  - Pricing: enterprise laptops 12% off');
System.debug('  - Product: LAPTOP15 + WARRANTYEXTENSION bundle → +5% on warranty');
System.debug('  - Approval: deals >= $50,000 need Sales Manager');
