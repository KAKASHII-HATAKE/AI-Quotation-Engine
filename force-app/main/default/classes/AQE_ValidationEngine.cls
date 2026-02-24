/**
 * @description Deterministic guard layer that validates LLM output before
 *              any DML is performed. Catches hallucinations, calculation errors,
 *              and policy violations from the LLM response.
 *
 *              This is the CRITICAL safety net that ensures financial accuracy:
 *              every LLM-generated price is independently re-calculated and verified.
 *
 * @namespace   aqe
 */
public with sharing class AQE_ValidationEngine {

    /** Result object returned by all validate methods */
    public class ValidationResult {
        public Boolean isValid               = true;
        public List<String> errors           = new List<String>();
        public List<String> warnings         = new List<String>();
        public List<AQE_QuoteLineDTO> lines  = new List<AQE_QuoteLineDTO>();

        public void addError(String msg) {
            errors.add(msg);
            isValid = false;
        }
        public void addWarning(String msg) {
            warnings.add(msg);
        }
    }

    /**
     * Full validation pass on LLM-generated quote lines.
     * Checks: price calculations, discount limits, required fields, product existence.
     *
     * @param lines          LLM-generated line DTOs
     * @param products       Map of productCode -> AQE_ProductDTO (source of truth for list prices)
     * @param discountRules  Active discount rules (for max discount checks)
     * @return ValidationResult with errors, warnings, and corrected lines
     */
    public static ValidationResult validateQuoteLines(
        List<AQE_QuoteLineDTO> lines,
        Map<String, AQE_ProductDTO> products,
        List<AI_Discount_Rule__c> discountRules
    ) {
        ValidationResult result = new ValidationResult();
        Decimal maxAllowedDiscount = getMaxAllowedDiscount(discountRules);

        for (AQE_QuoteLineDTO line : lines) {

            // 1. Required fields
            if (String.isBlank(line.productCode)) {
                result.addError('Quote line missing product code');
                continue;
            }
            if (line.quantity == null || line.quantity <= 0) {
                result.addError('Invalid quantity for product: ' + line.productCode);
                continue;
            }

            // 2. Product must exist
            AQE_ProductDTO product = products.get(line.productCode);
            if (product == null) {
                result.addError('Product not found in pricebook: ' + line.productCode);
                continue;
            }

            // 3. Fill in product ID and pricebook entry if missing
            if (line.product2Id == null) {
                line.product2Id = product.id;
            }
            if (line.pricebookEntryId == null) {
                line.pricebookEntryId = product.pricebookEntryId;
            }

            // 4. List price sanity check
            if (line.listPrice == null || line.listPrice <= 0) {
                line.listPrice = product.listPrice;
                result.addWarning('List price corrected from pricebook for: ' + line.productCode);
            }

            // 5. Discount percentage bounds
            if (line.discountPercent != null) {
                if (line.discountPercent < 0) {
                    result.addError('Negative discount not allowed for: ' + line.productCode);
                    line.discountPercent = 0;
                }
                if (line.discountPercent > 100) {
                    result.addError('Discount exceeds 100% for: ' + line.productCode);
                    line.discountPercent = 100;
                }
                if (maxAllowedDiscount != null && line.discountPercent > maxAllowedDiscount) {
                    result.addWarning('Discount ' + line.discountPercent + '% exceeds max allowed '
                        + maxAllowedDiscount + '% for: ' + line.productCode + '. Approval required.');
                }
            }

            // 6. Re-calculate unit price deterministically
            Decimal expectedUnitPrice = line.listPrice;
            if (line.discountPercent != null && line.discountPercent > 0) {
                expectedUnitPrice = line.listPrice * (1 - (line.discountPercent / 100));
                expectedUnitPrice = expectedUnitPrice.setScale(4, RoundingMode.HALF_UP);
            }

            // 7. Compare LLM unit price vs deterministic calculation (allow 0.01 tolerance)
            if (line.unitPrice != null) {
                Decimal diff = Math.abs(line.unitPrice - expectedUnitPrice);
                if (diff > 0.01) {
                    result.addWarning('Unit price corrected for ' + line.productCode
                        + ': LLM=' + line.unitPrice + ', Expected=' + expectedUnitPrice);
                    line.unitPrice = expectedUnitPrice;
                }
            } else {
                line.unitPrice = expectedUnitPrice;
            }

            // 8. Re-calculate total price deterministically
            Decimal expectedTotal = (line.unitPrice * line.quantity).setScale(2, RoundingMode.HALF_UP);
            if (line.totalPrice != null) {
                Decimal totalDiff = Math.abs(line.totalPrice - expectedTotal);
                if (totalDiff > 0.01) {
                    result.addWarning('Total price corrected for ' + line.productCode
                        + ': LLM=' + line.totalPrice + ', Expected=' + expectedTotal);
                    line.totalPrice = expectedTotal;
                }
            } else {
                line.totalPrice = expectedTotal;
            }

            result.lines.add(line);
        }

        return result;
    }

    /**
     * Validates that the quote summary totals match the sum of individual line totals.
     * @param lines     Validated line DTOs
     * @param totals    LLM-generated totals DTO
     * @return ValidationResult (errors if totals are inconsistent)
     */
    public static ValidationResult validateTotals(
        List<AQE_QuoteLineDTO> lines, AQE_QuoteTotalsDTO totals
    ) {
        ValidationResult result = new ValidationResult();
        Decimal expectedSubtotal = 0, expectedNetTotal = 0;
        for (AQE_QuoteLineDTO line : lines) {
            expectedSubtotal += (line.listPrice  * line.quantity);
            expectedNetTotal += (line.unitPrice  * line.quantity);
        }
        expectedSubtotal = expectedSubtotal.setScale(2, RoundingMode.HALF_UP);
        expectedNetTotal = expectedNetTotal.setScale(2, RoundingMode.HALF_UP);

        if (totals != null) {
            Decimal llmSubtotal = totals.subtotal != null ? totals.subtotal : 0;
            Decimal llmNet      = totals.netTotal != null ? totals.netTotal  : 0;

            if (Math.abs(llmSubtotal - expectedSubtotal) > 0.01) {
                result.addWarning('Subtotal corrected: LLM=' + llmSubtotal + ', Calculated=' + expectedSubtotal);
                totals.subtotal = expectedSubtotal;
            }
            if (Math.abs(llmNet - expectedNetTotal) > 0.01) {
                result.addWarning('Net total corrected: LLM=' + llmNet + ', Calculated=' + expectedNetTotal);
                totals.netTotal = expectedNetTotal;
            }
            totals.totalDiscount = (totals.subtotal - totals.netTotal).setScale(2, RoundingMode.HALF_UP);
            totals.grandTotal    = totals.netTotal;
            if (totals.subtotal > 0) {
                totals.effectiveDiscountPercent = ((totals.totalDiscount / totals.subtotal) * 100)
                    .setScale(2, RoundingMode.HALF_UP);
            }
        }

        return result;
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static Decimal getMaxAllowedDiscount(List<AI_Discount_Rule__c> rules) {
        Decimal maxDiscount = null;
        for (AI_Discount_Rule__c rule : rules) {
            if (rule.Max_Discount_Percent__c != null) {
                if (maxDiscount == null || rule.Max_Discount_Percent__c > maxDiscount) {
                    maxDiscount = rule.Max_Discount_Percent__c;
                }
            }
        }
        return maxDiscount;
    }
}
