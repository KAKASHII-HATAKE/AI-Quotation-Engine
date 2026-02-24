/**
 * @description Handles all outbound callouts from Salesforce Apex to the Node.js
 *              LLM orchestration middleware. Uses Named Credential 'AQE_Backend'
 *              for authentication — no hardcoded URLs or credentials.
 *
 *              All data passed to the backend is pre-sanitised (PII stripped)
 *              by the backend's own PII tokenizer. Apex only sends structured
 *              business context (product codes, quantities, rule texts).
 *
 * @namespace   aqe
 */
public with sharing class AQE_LLMService {

    private static final String NAMED_CREDENTIAL = 'callout:AQE_Backend';
    private static final String ENDPOINT_GENERATE = '/api/quote/generate';
    private static final String ENDPOINT_HEALTH   = '/api/health';

    /** Request DTO sent to Node.js backend */
    public class LLMRequest {
        public String  userPrompt;
        public String  ruleContext;       // JSON from AQE_RuleEngine.buildRuleContext()
        public String  orgContext;        // Cloud environment, account type, etc.
        public String  sessionId;         // For tracking in AI_Transaction_Log__c
        public List<Map<String, Object>> products; // Product catalogue context (no PII)
    }

    /** Response DTO received from Node.js backend */
    public class LLMResponse {
        public Boolean success;
        public String  intent;
        public List<AQE_QuoteLineDTO> quoteLines;
        public AQE_QuoteTotalsDTO     quoteSummary;
        public Boolean approvalRequired;
        public List<String> warnings;
        public List<String> productRecommendations;
        public String  rawJson;           // Original JSON response for logging
        public String  errorMessage;
    }

    /**
     * Calls the Node.js LLM orchestration service to generate quote lines
     * from a natural language prompt.
     *
     * @param request LLMRequest containing user prompt and context
     * @return LLMResponse with parsed quote lines and metadata
     * @throws AQE_Exception on callout failure or timeout
     */
    public static LLMResponse generateQuote(LLMRequest request) {
        // Check engine is active
        AI_Engine_Config__c config = AI_Engine_Config__c.getOrgDefaults();
        if (config == null || config.Engine_Active__c != true) {
            throw new AQE_Exception('AQE Engine is currently disabled. Contact your administrator.');
        }

        Integer timeoutMs = config.Callout_Timeout_Seconds__c != null
            ? (Integer)(config.Callout_Timeout_Seconds__c * 1000)
            : 120000;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + ENDPOINT_GENERATE);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-AQE-OrgId', UserInfo.getOrganizationId());
        req.setHeader('X-AQE-SessionId', request.sessionId != null ? request.sessionId : generateSessionId());
        req.setTimeout(timeoutMs);
        req.setBody(JSON.serialize(request));

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (System.CalloutException e) {
            throw new AQE_Exception('LLM service callout failed: ' + e.getMessage());
        }

        if (res.getStatusCode() == 200) {
            return parseResponse(res.getBody());
        } else if (res.getStatusCode() == 429) {
            throw new AQE_Exception('LLM service rate limit exceeded. Please wait and retry.');
        } else if (res.getStatusCode() == 503) {
            throw new AQE_Exception('LLM service temporarily unavailable. Please retry in a few minutes.');
        } else {
            throw new AQE_Exception(
                'LLM service error ' + res.getStatusCode() + ': ' + res.getStatus()
                + '. Body: ' + res.getBody().left(500)
            );
        }
    }

    /**
     * Health check ping to the Node.js backend.
     * @return true if backend is reachable and responding
     */
    public static Boolean healthCheck() {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL + ENDPOINT_HEALTH);
            req.setMethod('GET');
            req.setTimeout(10000);
            HttpResponse res = new Http().send(req);
            return res.getStatusCode() == 200;
        } catch (Exception e) {
            return false;
        }
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static LLMResponse parseResponse(String responseBody) {
        LLMResponse resp = new LLMResponse();
        resp.rawJson = responseBody;

        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            resp.success = parsed.containsKey('success') ? (Boolean) parsed.get('success') : true;

            // Parse quote_lines array
            resp.quoteLines = new List<AQE_QuoteLineDTO>();
            if (parsed.containsKey('quote_lines')) {
                List<Object> linesRaw = (List<Object>) parsed.get('quote_lines');
                for (Object lineObj : linesRaw) {
                    Map<String, Object> lineMap = (Map<String, Object>) lineObj;
                    AQE_QuoteLineDTO dto = new AQE_QuoteLineDTO();
                    dto.productCode     = (String)  lineMap.get('product_code');
                    dto.quantity        = lineMap.containsKey('quantity') ? Decimal.valueOf(String.valueOf(lineMap.get('quantity'))) : 1;
                    dto.listPrice       = lineMap.containsKey('list_price') ? Decimal.valueOf(String.valueOf(lineMap.get('list_price'))) : 0;
                    dto.unitPrice       = lineMap.containsKey('unit_price') ? Decimal.valueOf(String.valueOf(lineMap.get('unit_price'))) : 0;
                    dto.discountPercent = lineMap.containsKey('discount_percent') ? Decimal.valueOf(String.valueOf(lineMap.get('discount_percent'))) : 0;
                    dto.totalPrice      = lineMap.containsKey('total_price') ? Decimal.valueOf(String.valueOf(lineMap.get('total_price'))) : 0;
                    if (lineMap.containsKey('rules_applied')) {
                        dto.rulesApplied = String.valueOf(lineMap.get('rules_applied'));
                    }
                    resp.quoteLines.add(dto);
                }
            }

            // Parse quote_summary
            if (parsed.containsKey('quote_summary')) {
                Map<String, Object> summary = (Map<String, Object>) parsed.get('quote_summary');
                resp.quoteSummary = new AQE_QuoteTotalsDTO();
                resp.quoteSummary.subtotal      = summary.containsKey('subtotal')         ? Decimal.valueOf(String.valueOf(summary.get('subtotal'))) : 0;
                resp.quoteSummary.totalDiscount = summary.containsKey('total_discount')   ? Decimal.valueOf(String.valueOf(summary.get('total_discount'))) : 0;
                resp.quoteSummary.netTotal      = summary.containsKey('net_total')        ? Decimal.valueOf(String.valueOf(summary.get('net_total'))) : 0;
            }

            // Parse approval
            if (parsed.containsKey('approval')) {
                Map<String, Object> approval = (Map<String, Object>) parsed.get('approval');
                resp.approvalRequired = approval.containsKey('required') ? (Boolean) approval.get('required') : false;
            }

            // Parse warnings
            resp.warnings = new List<String>();
            if (parsed.containsKey('warnings')) {
                List<Object> warns = (List<Object>) parsed.get('warnings');
                for (Object w : warns) { resp.warnings.add((String) w); }
            }

        } catch (Exception e) {
            resp.success = false;
            resp.errorMessage = 'Failed to parse LLM response: ' + e.getMessage();
        }

        return resp;
    }

    private static String generateSessionId() {
        return EncodingUtil.base64Encode(Crypto.generateAESKey(128)).left(36).replace('+', '-').replace('/', '_');
    }
}
