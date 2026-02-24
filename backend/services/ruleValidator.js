'use strict';

/**
 * Server-side deterministic validation of LLM-generated quote output.
 * This is the backend complement to AQE_ValidationEngine.cls in Apex.
 *
 * Catches mathematical errors in LLM output before it reaches Salesforce.
 */

const PRICE_TOLERANCE = 0.01;

/**
 * Validates and corrects LLM-generated quote response.
 * @param {object} llmResponse  Parsed JSON from LLM
 * @param {Array}  products     Available products array (for existence checks)
 * @returns {object} Validated and corrected response
 */
function validate(llmResponse, products) {
  if (!llmResponse || typeof llmResponse !== 'object') {
    throw new Error('LLM response is null or not an object');
  }

  const result = { ...llmResponse };
  const warnings = result.warnings || [];
  const productMap = buildProductMap(products);

  // Validate and correct each line
  result.quote_lines = (result.quote_lines || []).map(line => {
    return validateLine(line, productMap, warnings);
  });

  // Validate totals
  result.quote_summary = validateTotals(result.quote_lines, result.quote_summary, warnings);

  result.warnings = warnings;
  return result;
}

function validateLine(line, productMap, warnings) {
  const corrected = { ...line };

  // Required fields
  if (!corrected.product_code) {
    warnings.push('Line missing product_code — line skipped');
    return null;
  }

  const qty = parseFloat(corrected.quantity) || 0;
  if (qty <= 0) {
    warnings.push(`Invalid quantity (${qty}) for ${corrected.product_code}`);
    corrected.quantity = 1;
  }

  // Clamp discount
  let discount = parseFloat(corrected.discount_percent) || 0;
  if (discount < 0)   { discount = 0; warnings.push(`Negative discount corrected for ${corrected.product_code}`); }
  if (discount > 100) { discount = 100; warnings.push(`Discount >100% corrected for ${corrected.product_code}`); }
  corrected.discount_percent = discount;

  // Re-calculate unit price
  const listPrice = parseFloat(corrected.list_price) || 0;
  const expectedUnitPrice = parseFloat((listPrice * (1 - discount / 100)).toFixed(4));

  const llmUnitPrice = parseFloat(corrected.unit_price) || 0;
  if (Math.abs(llmUnitPrice - expectedUnitPrice) > PRICE_TOLERANCE) {
    warnings.push(`Unit price corrected for ${corrected.product_code}: LLM=${llmUnitPrice}, Expected=${expectedUnitPrice}`);
    corrected.unit_price = expectedUnitPrice;
  } else {
    corrected.unit_price = expectedUnitPrice;
  }

  // Re-calculate total price
  const expectedTotal = parseFloat((corrected.unit_price * corrected.quantity).toFixed(2));
  const llmTotal = parseFloat(corrected.total_price) || 0;
  if (Math.abs(llmTotal - expectedTotal) > PRICE_TOLERANCE) {
    warnings.push(`Total price corrected for ${corrected.product_code}: LLM=${llmTotal}, Expected=${expectedTotal}`);
  }
  corrected.total_price = expectedTotal;

  return corrected;
}

function validateTotals(lines, summary, warnings) {
  const validLines = (lines || []).filter(Boolean);

  let expectedSubtotal = 0;
  let expectedNetTotal = 0;
  for (const line of validLines) {
    expectedSubtotal += parseFloat(line.list_price)  * parseFloat(line.quantity);
    expectedNetTotal += parseFloat(line.total_price);
  }
  expectedSubtotal = parseFloat(expectedSubtotal.toFixed(2));
  expectedNetTotal = parseFloat(expectedNetTotal.toFixed(2));

  const corrected = { ...(summary || {}) };

  if (Math.abs((parseFloat(corrected.subtotal) || 0) - expectedSubtotal) > PRICE_TOLERANCE) {
    warnings.push(`Subtotal corrected: ${corrected.subtotal} → ${expectedSubtotal}`);
    corrected.subtotal = expectedSubtotal;
  }
  if (Math.abs((parseFloat(corrected.net_total) || 0) - expectedNetTotal) > PRICE_TOLERANCE) {
    warnings.push(`Net total corrected: ${corrected.net_total} → ${expectedNetTotal}`);
    corrected.net_total = expectedNetTotal;
  }

  corrected.total_discount = parseFloat((corrected.subtotal - corrected.net_total).toFixed(2));
  return corrected;
}

function buildProductMap(products) {
  const map = {};
  if (!Array.isArray(products)) return map;
  for (const p of products) {
    if (p && p.productCode) map[p.productCode] = p;
  }
  return map;
}

module.exports = { validate };
