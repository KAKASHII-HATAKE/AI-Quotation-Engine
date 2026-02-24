List<AI_Discount_Rule__c> dr = [SELECT Name, Discount_Value__c, Max_Discount_Percent__c, Approval_Required_Threshold__c FROM AI_Discount_Rule__c WHERE Active__c=true];
List<AI_Pricing_Rule__c> pr = [SELECT Name, Product_Code__c, Rule_Category__c FROM AI_Pricing_Rule__c WHERE Active__c=true];
List<AI_Product_Rule__c> por = [SELECT Name, Rule_Type__c, Primary_Product_Code__c, Bundle_Discount_Percent__c FROM AI_Product_Rule__c WHERE Active__c=true];
List<AI_Approval_Policy__c> ap = [SELECT Name, Min_Deal_Value__c, Min_Discount_Threshold__c, Approval_Chain__c FROM AI_Approval_Policy__c WHERE Active__c=true];
System.debug('DISCOUNT(' + dr.size() + '): ' + JSON.serialize(dr));
System.debug('PRICING(' + pr.size() + '): ' + JSON.serialize(pr));
System.debug('PRODUCT(' + por.size() + '): ' + JSON.serialize(por));
System.debug('APPROVAL(' + ap.size() + '): ' + JSON.serialize(ap));
