/**
 * @description Main Apex controller exposing @AuraEnabled methods to LWC components.
 *              Acts as the secure bridge between the UI and all engine services.
 *
 *              Orchestration flow for generateQuote():
 *              1. Load applicable rules (RuleEngine)
 *              2. Call Node.js LLM service (LLMService)
 *              3. Validate LLM output (ValidationEngine)
 *              4. Determine approval requirement (ApprovalEngine)
 *              5. Create quote via adapter (AdapterFactory)
 *              6. Handle bulk vs sync processing based on line count
 *              7. Write audit log (AI_Transaction_Log__c)
 *
 * @namespace   aqe
 */
public with sharing class AQE_QuoteController {

    // ─── Quote Generation ─────────────────────────────────────────────────────

    /**
     * Main entry point: generates a complete quote from a natural language prompt.
     * Called by aqeQuoteGeneratorMain LWC component.
     *
     * @param userPrompt   Natural language input from the user
     * @param accountId    Target Account Record ID
     * @param opportunityId Target Opportunity Record ID (optional)
     * @return GenerateQuoteResult containing quote ID, lines, totals, approval info
     */
    @AuraEnabled
    public static GenerateQuoteResult generateQuote(
        String userPrompt, Id accountId, Id opportunityId
    ) {
        Long startTime = System.currentTimeMillis();
        GenerateQuoteResult result = new GenerateQuoteResult();
        AI_Transaction_Log__c txnLog = createTransactionLog(userPrompt, accountId);

        try {
            // 1. Input validation
            if (String.isBlank(userPrompt)) {
                throw new AQE_Exception('Please enter a quote description.');
            }
            AQE_SecurityUtil.checkGovernorLimits();

            // 2. Get config
            AI_Engine_Config__c config = AI_Engine_Config__c.getOrgDefaults();
            if (config == null || config.Engine_Active__c != true) {
                throw new AQE_Exception('AI Quotation Engine is not active. Contact your administrator to enable it in AI Engine Config settings.');
            }

            Integer maxSyncLines = config.Max_Quote_Lines__c != null ? (Integer) config.Max_Quote_Lines__c : 30;

            // 3. Load rules that don't require product codes (discount + approval) upfront
            //    so they are available in the LLM context before the callout.
            List<AI_Approval_Policy__c> approvalPolicies = AQE_RuleEngine.getAllApprovalPolicies();
            List<AI_Discount_Rule__c> discountRules = AQE_RuleEngine.getApplicableDiscountRules(Date.today());

            // 4. Build LLM request — pass discount rules as context so the LLM honours
            //    them when generating prices. Product-specific rules are loaded after the
            //    LLM responds (product codes are not yet known at this point).
            AQE_LLMService.LLMRequest llmReq = new AQE_LLMService.LLMRequest();
            llmReq.userPrompt  = String.escapeSingleQuotes(userPrompt.trim());
            llmReq.sessionId   = txnLog.Id;
            llmReq.ruleContext = AQE_RuleEngine.buildRuleContext(
                new List<AI_Pricing_Rule__c>(),
                new List<AI_Product_Rule__c>(),
                discountRules
            );
            llmReq.orgContext  = JSON.serialize(new Map<String, Object>{
                'cloud_environment' => AQE_CloudDetector.getCurrent(),
                'account_id'        => accountId,
                'user_role'         => UserInfo.getUserRoleId(),
                'quote_date'        => String.valueOf(Date.today())
            });

            // 5. Call LLM service
            AQE_LLMService.LLMResponse llmResp = AQE_LLMService.generateQuote(llmReq);

            if (!llmResp.success) {
                throw new AQE_Exception('LLM processing failed: ' + llmResp.errorMessage);
            }

            // 6. Load products + product-specific rules (product codes now known)
            List<String> productCodes = extractProductCodes(llmResp.quoteLines);
            AQE_IQuoteAdapter adapter = AQE_AdapterFactory.getAdapter();
            List<AQE_ProductDTO> products = adapter.getProducts(productCodes);
            Map<String, AQE_ProductDTO> productMap = new Map<String, AQE_ProductDTO>();
            for (AQE_ProductDTO p : products) { productMap.put(p.productCode, p); }

            List<AI_Pricing_Rule__c> pricingRules = AQE_RuleEngine.getApplicablePricingRules(productCodes, Date.today());
            List<AI_Product_Rule__c> productRules  = AQE_RuleEngine.getApplicableProductRules(productCodes);

            // Rules are fully optional. If none exist for this quote, the user's request
            // is honoured exactly (math correctness is still verified).
            // If any rule is found, it is enforced.
            Boolean rulesExist = !approvalPolicies.isEmpty() || !discountRules.isEmpty()
                || !pricingRules.isEmpty() || !productRules.isEmpty();

            // 7. Deterministic validation — enforce discount caps only when rules are present
            AQE_ValidationEngine.ValidationResult validation =
                AQE_ValidationEngine.validateQuoteLines(
                    llmResp.quoteLines, productMap,
                    rulesExist ? discountRules : new List<AI_Discount_Rule__c>()
                );

            if (!validation.isValid) {
                result.success = false;
                result.errors  = validation.errors;
                result.warnings = validation.warnings;
                updateTransactionLog(txnLog, 'Validation Failed', null, validation.errors, startTime);
                return result;
            }

            // 8. Validate totals
            AQE_ValidationEngine.validateTotals(validation.lines, llmResp.quoteSummary);

            // 9. Determine approval requirement — skipped entirely when no rules are present
            AQE_ApprovalEngine.ApprovalDecision approvalDecision = rulesExist
                ? AQE_ApprovalEngine.evaluate(
                    new AQE_QuoteDTO(), validation.lines, llmResp.quoteSummary, approvalPolicies)
                : new AQE_ApprovalEngine.ApprovalDecision(); // no rules → no approval required

            // 10. Create the quote header
            Id pricebookId = getStandardPricebookId();
            AQE_QuoteDTO quoteDto = new AQE_QuoteDTO(accountId, pricebookId);
            quoteDto.opportunityId = opportunityId;
            quoteDto.expirationDate = Date.today().addDays(30);
            quoteDto.name = 'AQE - ' + userPrompt.trim().left(80) + ' - ' + Date.today().format();

            Id quoteId = adapter.createQuote(quoteDto);
            result.quoteId = quoteId;

            // 11. Create lines — sync or async based on count
            if (validation.lines.size() <= maxSyncLines) {
                List<Id> lineIds = adapter.createQuoteLines(quoteId, validation.lines);
                result.lineIds   = lineIds;
                result.isBulk    = false;
            } else {
                String batchId = AQE_BulkQuoteProcessor.enqueueBulkCreation(
                    quoteId, validation.lines, txnLog.Id
                );
                result.batchTransactionId = batchId;
                result.isBulk = true;
            }

            // 12. Submit for approval if required
            if (approvalDecision.required && !approvalDecision.autoApproved) {
                result.approvalRequired  = true;
                result.approvalChain     = approvalDecision.approvalChain;
                result.approvalReason    = approvalDecision.reason;
                if (!result.isBulk) {
                    AQE_ApprovalEngine.submitApproval(quoteId, approvalDecision, 'AQE auto-submitted');
                }
            }

            // 13. Populate result
            result.success      = true;
            result.quoteLines   = validation.lines;
            result.quoteTotals  = llmResp.quoteSummary;
            result.warnings     = validation.warnings;
            result.warnings.addAll(llmResp.warnings != null ? llmResp.warnings : new List<String>());
            result.warnings.addAll(approvalDecision.warnings);

            updateTransactionLog(txnLog, 'Success', quoteId, new List<String>(), startTime);

        } catch (AQE_Exception e) {
            result.success = false;
            result.errors  = new List<String>{ e.getMessage() };
            updateTransactionLog(txnLog, 'LLM Error', null, result.errors, startTime);
        } catch (Exception e) {
            result.success = false;
            result.errors  = new List<String>{ 'Unexpected error: ' + e.getMessage() };
            updateTransactionLog(txnLog, 'LLM Error', null, result.errors, startTime);
        }

        return result;
    }

    /**
     * Returns the detected cloud environment for the setup wizard.
     */
    @AuraEnabled(cacheable=true)
    public static String getCloudEnvironment() {
        return AQE_CloudDetector.getCurrent();
    }

    /**
     * Runs cloud detection and saves the result. Called by setup wizard.
     */
    @AuraEnabled
    public static String detectAndSaveEnvironment() {
        return AQE_CloudDetector.detectAndSave();
    }

    /**
     * Health check — returns engine status for the setup wizard.
     */
    @AuraEnabled
    public static Map<String, Object> getEngineStatus() {
        AI_Engine_Config__c config = AI_Engine_Config__c.getOrgDefaults();
        Boolean backendReachable   = AQE_LLMService.healthCheck();
        return new Map<String, Object>{
            'engineActive'      => config != null && config.Engine_Active__c == true,
            'cloudEnvironment'  => AQE_CloudDetector.getCurrent(),
            'backendReachable'  => backendReachable,
            'llmModel'          => config != null ? config.LLM_Model__c : null,
            'maxSyncLines'      => config != null ? config.Max_Quote_Lines__c : 30,
            'piiEnabled'        => config != null && config.Enable_PII_Tokenisation__c == true
        };
    }

    /**
     * Fetches quote lines for an existing quote (for preview/edit UI).
     */
    @AuraEnabled
    public static List<AQE_QuoteLineDTO> getExistingQuoteLines(Id quoteId) {
        if (!AQE_SecurityUtil.isValidSalesforceId(quoteId)) {
            throw new AQE_Exception('Invalid quote ID provided.');
        }
        return AQE_AdapterFactory.getAdapter().getQuoteLines(quoteId);
    }

    // ─── Result DTO ───────────────────────────────────────────────────────────

    public class GenerateQuoteResult {
        @AuraEnabled public Boolean success              = false;
        @AuraEnabled public Id quoteId;
        @AuraEnabled public List<Id> lineIds             = new List<Id>();
        @AuraEnabled public List<AQE_QuoteLineDTO> quoteLines = new List<AQE_QuoteLineDTO>();
        @AuraEnabled public AQE_QuoteTotalsDTO quoteTotals;
        @AuraEnabled public Boolean approvalRequired     = false;
        @AuraEnabled public String  approvalChain;
        @AuraEnabled public String  approvalReason;
        @AuraEnabled public Boolean isBulk               = false;
        @AuraEnabled public String  batchTransactionId;
        @AuraEnabled public List<String> warnings        = new List<String>();
        @AuraEnabled public List<String> errors          = new List<String>();
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static List<String> extractProductCodes(List<AQE_QuoteLineDTO> lines) {
        Set<String> codes = new Set<String>();
        for (AQE_QuoteLineDTO l : lines) {
            if (String.isNotBlank(l.productCode)) { codes.add(l.productCode); }
        }
        return new List<String>(codes);
    }

    private static Id getStandardPricebookId() {
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        return [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
    }

    // Build the log object only — no DML here so callouts are not blocked.
    // The actual insert happens in updateTransactionLog after the callout.
    private static AI_Transaction_Log__c createTransactionLog(String prompt, Id accountId) {
        return new AI_Transaction_Log__c(
            User_Prompt__c          = prompt.left(32768),
            Processing_Status__c    = 'Pending',
            Cloud_Environment__c    = AQE_CloudDetector.getCurrent()
        );
    }

    // Insert on first call (log.Id == null), update on subsequent calls.
    private static void updateTransactionLog(
        AI_Transaction_Log__c log, String status, Id quoteId,
        List<String> errors, Long startTime
    ) {
        try {
            log.Processing_Status__c  = status;
            log.Quote_Id__c           = quoteId;
            log.Processing_Time_Ms__c = System.currentTimeMillis() - startTime;
            if (!errors.isEmpty()) {
                log.Validation_Errors__c = JSON.serialize(errors);
            }
            if (log.Id == null) {
                insert log;
            } else {
                update log;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Could not save transaction log: ' + e.getMessage());
        }
    }
}
