/**
 * @description Intelligent approval engine that evaluates approval policies
 *              and determines the appropriate approval chain for a quote.
 *
 *              Combines LLM contextual intelligence (via policy text evaluation)
 *              with deterministic threshold checks (discount %, deal value).
 *
 * @namespace   aqe
 */
public with sharing class AQE_ApprovalEngine {

    /** Result of approval determination */
    public class ApprovalDecision {
        public Boolean required         = false;
        public Boolean autoApproved     = false;
        public String  policyName;
        public String  approvalChain;
        public String  reason;
        public List<String> warnings    = new List<String>();
    }

    /**
     * Evaluates all active approval policies against the quote context
     * and returns the first matching policy decision.
     *
     * @param quote         The quote DTO (header context)
     * @param lines         Validated quote lines
     * @param totals        Calculated quote totals
     * @param policies      Active approval policies from AQE_RuleEngine
     * @return ApprovalDecision indicating if/how approval is needed
     */
    public static ApprovalDecision evaluate(
        AQE_QuoteDTO quote,
        List<AQE_QuoteLineDTO> lines,
        AQE_QuoteTotalsDTO totals,
        List<AI_Approval_Policy__c> policies
    ) {
        ApprovalDecision decision = new ApprovalDecision();
        Decimal effectiveDiscount = totals != null ? totals.effectiveDiscountPercent : 0;
        Decimal dealValue         = totals != null ? totals.netTotal : 0;

        for (AI_Approval_Policy__c policy : policies) {

            // Deterministic threshold checks first
            Boolean discountBreached = (policy.Min_Discount_Threshold__c != null
                && effectiveDiscount >= policy.Min_Discount_Threshold__c);
            Boolean valueBreached    = (policy.Min_Deal_Value__c != null
                && dealValue >= policy.Min_Deal_Value__c);

            if (!discountBreached && !valueBreached) {
                continue; // This policy's thresholds not met
            }

            // Policy triggered — check auto-approve condition
            decision.required    = true;
            decision.policyName  = policy.Name;
            decision.approvalChain = policy.Approval_Chain__c;
            decision.reason = buildReason(policy, effectiveDiscount, dealValue);

            // Check auto-approve conditions (deterministic part only)
            if (String.isNotBlank(policy.Auto_Approve_Condition__c)) {
                if (meetsAutoApproveCondition(policy.Auto_Approve_Condition__c, quote, effectiveDiscount)) {
                    decision.required    = false;
                    decision.autoApproved = true;
                    decision.reason      = 'Auto-approved: ' + policy.Auto_Approve_Condition__c;
                }
            }

            break; // First matching policy wins
        }

        return decision;
    }

    /**
     * Submits the quote for Salesforce approval using the matching process name
     * derived from the approval chain.
     * @param quoteId       Quote Record ID
     * @param decision      ApprovalDecision from evaluate()
     * @param comments      Submitter comments
     * @return ProcessInstanceWorkitem ID, or null if auto-approved
     */
    public static Id submitApproval(Id quoteId, ApprovalDecision decision, String comments) {
        if (!decision.required || decision.autoApproved) {
            return null;
        }

        // Use the cloud-appropriate adapter to submit
        AQE_IQuoteAdapter adapter = AQE_AdapterFactory.getAdapter();
        String submitComment = String.isNotBlank(comments)
            ? comments
            : 'AQE automated approval submission. Policy: ' + decision.policyName
              + '. Reason: ' + decision.reason;

        return adapter.submitForApproval(quoteId, submitComment);
    }

    /**
     * Checks delegate configurations for a given role and returns the active delegate.
     * @param roleApiName   Salesforce Role API Name to check delegation for
     * @param checkDate     DateTime to check delegation window against
     * @return Delegate role API Name, or null if no active delegation
     */
    public static String getActiveDelegateRole(String roleApiName, DateTime checkDate) {
        List<AI_Delegate_Config__c> delegates = [
            SELECT Delegate_Approver_Role__c, Delegation_Start__c, Delegation_End__c
            FROM   AI_Delegate_Config__c
            WHERE  Active__c = true
            AND    Primary_Approver_Role__c = :roleApiName
            AND    (Delegation_Start__c = null OR Delegation_Start__c <= :checkDate)
            AND    (Delegation_End__c   = null OR Delegation_End__c   >= :checkDate)
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        return delegates.isEmpty() ? null : delegates[0].Delegate_Approver_Role__c;
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static String buildReason(AI_Approval_Policy__c policy, Decimal discount, Decimal dealValue) {
        List<String> reasons = new List<String>();
        if (policy.Min_Discount_Threshold__c != null && discount >= policy.Min_Discount_Threshold__c) {
            reasons.add('Discount ' + discount.setScale(1) + '% >= threshold ' + policy.Min_Discount_Threshold__c + '%');
        }
        if (policy.Min_Deal_Value__c != null && dealValue >= policy.Min_Deal_Value__c) {
            reasons.add('Deal value ' + dealValue.format() + ' >= threshold ' + policy.Min_Deal_Value__c.format());
        }
        return String.join(reasons, '; ');
    }

    private static Boolean meetsAutoApproveCondition(String condition, AQE_QuoteDTO quote, Decimal discount) {
        // Deterministic auto-approve checks based on condition keywords
        // Full LLM-based evaluation handled by Node.js middleware
        // This is a lightweight pre-check only
        if (String.isBlank(condition)) return false;
        String condLower = condition.toLowerCase();
        // If condition text mentions specific thresholds we can check deterministically
        // Otherwise, return false — LLM middleware handles complex conditions
        return false;
    }
}
