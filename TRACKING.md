# AI-Native Quotation Engine — Implementation Tracker

**Package Namespace:** `aqe`
**Target:** Salesforce AppExchange (ISV Managed Package)
**Compatibility:** Salesforce CPQ Cloud (SBQQ) + Revenue Cloud + Standard Salesforce
**API Version:** 65.0
**Last Updated:** 2026-02-24

---

## Segment Status Overview

| # | Segment | Status | Files |
|---|---------|--------|-------|
| 1 | Project Foundation Setup | ✅ DONE | sfdx-project.json, directory structure |
| 2 | Custom Objects (7 objects) | ✅ DONE | 7 objects + all fields |
| 3 | Cross-Cloud Adapter Layer | ✅ DONE | Interface, DTOs, Factory, 3 Adapters, CloudDetector |
| 4 | Core Apex Service Layer | ✅ DONE | QuoteController, RuleEngine, ValidationEngine, ApprovalEngine, BulkProcessor, LLMService, SecurityUtil |
| 5 | LWC Components | ✅ DONE | quoteGeneratorMain, quotePreview, loadingIndicator, cloudSetupWizard |
| 6 | Node.js Backend | ✅ DONE | server.js, llmOrchestrator, piiTokenizer, ruleValidator, auth, logger |
| 7 | Security & Packaging | ✅ DONE | Named Creds, Permission Sets, package.xml, postInstall.apex |
| 8 | Test Classes | ✅ DONE | CloudDetectorTest, AdapterFactoryTest, RuleEngineTest, ValidationEngineTest, ApprovalEngineTest, StandardAdapterTest, SecurityUtilTest |

---

## ALL SEGMENTS COMPLETE ✅

---

## Complete File Inventory

### force-app/main/default/

#### objects/ (7 Custom Objects)
```
AI_Pricing_Rule__c/
  AI_Pricing_Rule__c.object-meta.xml
  fields/ Active__c, Condition_Text__c, Formula_Text__c, Product_Code__c,
          Rule_Category__c, Priority__c, Effective_Date__c, Expiry_Date__c

AI_Product_Rule__c/
  AI_Product_Rule__c.object-meta.xml
  fields/ Active__c, Rule_Type__c, Primary_Product_Code__c, Related_Product_Codes__c,
          Rule_Text__c, Bundle_Discount_Percent__c, Priority__c

AI_Discount_Rule__c/
  AI_Discount_Rule__c.object-meta.xml
  fields/ Active__c, Discount_Type__c, Max_Discount_Percent__c,
          Approval_Required_Threshold__c, Stackable__c, Condition_Text__c,
          Discount_Value__c, Effective_Date__c, Expiry_Date__c

AI_Approval_Policy__c/
  AI_Approval_Policy__c.object-meta.xml
  fields/ Active__c, Trigger_Condition__c, Approval_Chain__c,
          Auto_Approve_Condition__c, Min_Discount_Threshold__c,
          Min_Deal_Value__c, Priority__c

AI_Delegate_Config__c/
  AI_Delegate_Config__c.object-meta.xml
  fields/ Active__c, Primary_Approver_Role__c, Delegate_Approver_Role__c,
          Delegation_Start__c, Delegation_End__c, Escalation_Timeout_Hours__c

AI_Engine_Config__c/   (Custom Setting - Hierarchy)
  AI_Engine_Config__c.object-meta.xml
  fields/ LLM_Endpoint_URL__c, Cloud_Environment__c, LLM_Model__c,
          Max_Quote_Lines__c, Enable_PII_Tokenisation__c,
          Callout_Timeout_Seconds__c, Engine_Active__c

AI_Transaction_Log__c/
  AI_Transaction_Log__c.object-meta.xml
  fields/ User_Prompt__c, LLM_Response_JSON__c, Quote_Id__c,
          Processing_Status__c, Rules_Applied__c, Validation_Errors__c,
          Processing_Time_Ms__c, Cloud_Environment__c, Batch_Transaction_Id__c
```

#### classes/ (Apex)
```
AQE_IQuoteAdapter.cls          — Interface
AQE_QuoteDTO.cls               — Quote header DTO
AQE_QuoteLineDTO.cls           — Quote line DTO
AQE_ProductDTO.cls             — Product DTO
AQE_QuoteTotalsDTO.cls         — Totals DTO
AQE_Exception.cls              — Custom exception
AQE_CloudDetector.cls          — Auto-detects cloud environment
AQE_AdapterFactory.cls         — Selects correct adapter at runtime
AQE_StandardQuoteAdapter.cls   — Standard Salesforce adapter
AQE_CPQQuoteAdapter.cls        — CPQ (SBQQ) adapter
AQE_RevenueCloudAdapter.cls    — Revenue Cloud adapter
AQE_SecurityUtil.cls           — FLS/CRUD checks, input sanitisation
AQE_RuleEngine.cls             — Loads & builds rule context
AQE_ValidationEngine.cls       — Deterministic price guard layer
AQE_ApprovalEngine.cls         — Approval chain evaluation & submission
AQE_LLMService.cls             — Node.js backend callout handler
AQE_BulkQuoteProcessor.cls     — Async Queueable bulk line creation
AQE_QuoteController.cls        — @AuraEnabled LWC bridge (main orchestrator)

--- Test Classes ---
AQE_TestDataFactory.cls        — Shared test data creation
AQE_CloudDetectorTest.cls
AQE_AdapterFactoryTest.cls
AQE_RuleEngineTest.cls
AQE_ValidationEngineTest.cls
AQE_ApprovalEngineTest.cls
AQE_StandardAdapterTest.cls
AQE_SecurityUtilTest.cls
```

#### lwc/ (Lightning Web Components)
```
aqeQuoteGeneratorMain/     — Parent, natural language input, orchestrates all state
aqeQuotePreview/           — Interactive quote table with inline editing & approval banner
aqeLoadingIndicator/       — Processing animation with bouncing dots
aqeCloudSetupWizard/       — Admin status dashboard & setup guide
```

#### namedCredentials/
```
AQE_Backend.namedCredential-meta.xml
  → Set endpoint to your Node.js middleware URL before deploying
```

#### permissionsets/
```
AQE_Admin.permissionset-meta.xml  — Full CRUD on all AQE objects + config access
AQE_User.permissionset-meta.xml   — Read rules, create quotes, create transaction logs
```

---

### backend/ (Node.js Middleware)
```
package.json              — Dependencies: @anthropic-ai/sdk, express, helmet, etc.
server.js                 — Express entry point, rate limiting, routing
.env.example              — Copy to .env and fill in LLM_API_KEY, ALLOWED_ORG_IDS
config/index.js           — All config from env vars
middleware/auth.js        — Org ID validation
middleware/logger.js      — Winston structured logging
services/llmOrchestrator.js  — Anthropic SDK integration, system prompt, JSON parsing
services/piiTokenizer.js     — PII stripping and tokenisation
services/ruleValidator.js    — Deterministic price validation (server-side guard)
```

---

### scripts/
```
apex/postInstall.apex     — Run after deployment: detects env, initialises config
```

### manifest/
```
package.xml               — Full package component manifest
```

---

## Architecture Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Namespace | `aqe` | AppExchange requirement |
| Adapter Pattern | Runtime-selected via config | Same code runs on CPQ/Revenue/Standard |
| Rule Storage | Long Text Area (structured NL) | Human-editable + LLM-parseable, no code changes |
| LLM Guard | AQE_ValidationEngine.cls + ruleValidator.js | Double validation — Apex + Node.js |
| Bulk Safety | Queueable + External_Ref__c + rollback | Avoids governor limits on large quotes |
| Security | WITH SECURITY_ENFORCED, Named Credentials, FLS checks | AppExchange security review compliance |
| PII | Stripped server-side before LLM | Never sends customer data to LLM |

---

## Next Steps to Deploy

1. **Register namespace `aqe`** in your DevHub org (Setup → Packaging → Namespaces)
2. **Deploy Node.js backend** to a hosting service (Railway, Heroku, AWS, etc.)
3. **Update Named Credential** `AQE_Backend` with your backend URL
4. **Run post-install script**: `sf apex run --file scripts/apex/postInstall.apex`
5. **Configure AI Engine Config** Custom Setting:
   - Set `LLM_Model__c` = `claude-sonnet-4-6`
   - Set `Engine_Active__c` = `true`
6. **Assign permission sets**: AQE_Admin to admins, AQE_User to sales reps
7. **Add `aqeQuoteGeneratorMain`** component to Account/Opportunity record pages
8. **Create sample rules** in AI Pricing Rule, AI Discount Rule objects
9. **Run Apex tests**: `sf apex run test --test-level RunLocalTests`

---

## How to Resume After a Break

1. Check the **Segment Status Overview** table above
2. Find first segment NOT marked `✅ DONE`
3. Look at the **Complete File Inventory** for that segment's files
4. Implement next file — all patterns follow established conventions
5. Run `sf project deploy start --source-dir force-app` to validate after changes

---
*Implementation complete: 2026-02-24*
