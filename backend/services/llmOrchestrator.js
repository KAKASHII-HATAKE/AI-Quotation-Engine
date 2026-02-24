'use strict';
const Anthropic = require('@anthropic-ai/sdk');
const config    = require('../config');
const { logger } = require('../middleware/logger');

// Only instantiate the Anthropic client when not in mock mode (avoids crash if no API key)
let anthropic;
if (!config.llm.mockMode) {
  anthropic = new Anthropic({ apiKey: config.llm.apiKey });
}

const SYSTEM_PROMPT = `You are a Salesforce CPQ pricing engine assistant. Your job is to parse natural language quote requests and generate accurate, rule-compliant quote line items.

You will be provided with:
1. A user's natural language quote request
2. Active pricing rules (structured text)
3. Available products and their list prices
4. Organisation context (cloud environment, account type)

STRICT RULES:
- Apply ALL matching pricing rules exactly as specified
- NEVER invent products — only use products from the provided product list
- ALL prices must be mathematically correct: total_price = unit_price * quantity
- Discount percentage must match: unit_price = list_price * (1 - discount_percent/100)
- If a rule requires approval, set approval.required = true

OUTPUT FORMAT: Respond ONLY with valid JSON matching this exact schema — no markdown, no explanation, just JSON:
{
  "intent": {
    "action": "create_quote",
    "products": ["PRODUCT_CODE_1", "PRODUCT_CODE_2"]
  },
  "quote_lines": [
    {
      "product_code": "string",
      "quantity": 0,
      "list_price": 0.00,
      "unit_price": 0.00,
      "discount_percent": 0.00,
      "total_price": 0.00,
      "rules_applied": ["Rule Name 1", "Rule Name 2"]
    }
  ],
  "quote_summary": {
    "subtotal": 0.00,
    "total_discount": 0.00,
    "net_total": 0.00
  },
  "approval": {
    "required": false,
    "chain": "",
    "reason": ""
  },
  "warnings": [],
  "product_recommendations": []
}`;

/**
 * Generates quote line items from a natural language prompt using the configured LLM.
 * @param {object} params
 * @param {string} params.userPrompt    Sanitised (PII-removed) user prompt
 * @param {string} params.ruleContext   JSON string of applicable rules
 * @param {string} params.orgContext    JSON string of org/account context
 * @param {Array}  params.products      Available products array
 * @param {string} params.sessionId     Session ID for tracking
 * @returns {Promise<object>} Parsed LLM response object
 */
async function generateQuote({ userPrompt, ruleContext, orgContext, products, sessionId }) {
  // ── Mock mode: return realistic canned response without calling any LLM ──
  if (config.llm.mockMode) {
    logger.info({ event: 'mock_quote', sessionId, productCount: (products || []).length });
    return buildMockResponse(products, userPrompt);
  }

  const userMessage = buildUserMessage(userPrompt, ruleContext, orgContext, products);

  logger.info({ event: 'llm_request', sessionId, model: config.llm.model,
    promptLength: userMessage.length });

  try {
    const response = await anthropic.messages.create({
      model:      config.llm.model,
      max_tokens: config.llm.maxTokens,
      temperature: config.llm.temperature,
      system:     SYSTEM_PROMPT,
      messages:   [{ role: 'user', content: userMessage }]
    });

    const rawText = response.content[0]?.text || '';
    logger.info({ event: 'llm_response', sessionId,
      inputTokens: response.usage?.input_tokens,
      outputTokens: response.usage?.output_tokens });

    return parseJSON(rawText, sessionId);

  } catch (err) {
    logger.error({ event: 'llm_error', sessionId, error: err.message });
    throw new Error('LLM call failed: ' + err.message);
  }
}

// ── Product catalogue — uses REAL ProductCodes from the connected Salesforce org ─
const PRODUCT_CATALOGUE = [
  { code: 'LAPTOP13',          name: '13" Laptop',                      list_price: 1300, keywords: ['laptop 13', 'laptop13', '13" laptop', '13 inch laptop', 'pro 13', 'lp13'] },
  { code: 'LAPTOP15',          name: '15" Laptop',                      list_price: 1500, keywords: ['laptop 15', 'laptop15', '15" laptop', '15 inch laptop', 'lp15'] },
  { code: 'MONITOR4K',         name: '4K Monitor',                      list_price: 400,  keywords: ['monitor', '4k monitor', 'display', 'screen'] },
  { code: 'TABLET10',          name: '10" Tablet',                      list_price: 150,  keywords: ['tablet', '10" tablet', 'ipad', '10 inch tablet'] },
  { code: 'HEADPHONES',        name: 'Headphones',                      list_price: 50,   keywords: ['headphone', 'headset', 'audio'] },
  { code: 'ACCIDENTINSURANCE', name: 'Accidental Damage Insurance',     list_price: 150,  keywords: ['accidental', 'insurance', 'damage insurance', 'protection'] },
  { code: 'DESKTOPCOMPUTER',   name: 'Desktop Computer',                list_price: 700,  keywords: ['desktop', 'desktop computer', 'pc'] },
  { code: 'FIREWALL',           name: 'Firewall',                        list_price: 2400, keywords: ['firewall', 'network security'] },
  { code: 'WARRANTY',          name: 'Warranty',                        list_price: 10,   keywords: ['warranty'] },
  { code: 'WARRANTYEXTENSION', name: 'Warranty Extension',              list_price: 15,   keywords: ['warranty extension', 'extended warranty', 'ext warranty', 'warrantyextension'] },
  { code: 'LDWARRANTY',        name: 'Loss and Damage Warranty',        list_price: 0,    keywords: ['loss and damage warranty', 'ldwarranty', 'loss damage warranty'] },
];

/**
 * Parse the user prompt to find matching products and quantities.
 * Returns [{code, list_price, quantity}] based on keyword matching.
 */
function parsePromptForProducts(userPrompt) {
  const prompt = (userPrompt || '').toLowerCase();

  // ── "all (active) products" / "everything" intent → return entire catalogue ─
  const allIntent = /\ball\s+(active\s+)?products?\b/.test(prompt)
    || /\bevery\s+(active\s+)?products?\b/.test(prompt)
    || /\beverything\b/.test(prompt)
    || prompt.includes('all items')
    || prompt.includes('full catalogue')
    || prompt.includes('full catalog');

  if (allIntent) {
    return PRODUCT_CATALOGUE.map(p => ({ ...p, quantity: 1 }));
  }

  // Extract a quantity number that precedes a keyword, e.g. "10 Laptop Pro 13"
  function extractQty(keyword) {
    const escaped = keyword.replace(/[-]/g, '[-]');
    const re = new RegExp(`(\\d+)\\s+${escaped}`, 'i');
    const m  = prompt.match(re);
    if (m) return parseInt(m[1], 10);
    // Also try keyword first then number: "Laptop Pro 13 x 10"
    const re2 = new RegExp(`${escaped}\\s+[x×]?\\s*(\\d+)`, 'i');
    const m2  = prompt.match(re2);
    return m2 ? parseInt(m2[1], 10) : null;
  }

  const matched = [];
  for (const product of PRODUCT_CATALOGUE) {
    for (const kw of product.keywords) {
      if (prompt.includes(kw)) {
        const qty = extractQty(kw) || extractQty(product.code.toLowerCase()) || 1;
        matched.push({ ...product, quantity: qty });
        break; // one match per product
      }
    }
  }

  // Fallback: if nothing matched, default to Laptop Pro 13 qty 1
  if (matched.length === 0) {
    matched.push({ ...PRODUCT_CATALOGUE[0], quantity: 1 });
  }

  return matched;
}

/**
 * Builds a realistic mock quote response.
 * Parses the user prompt to return real product codes that exist in Salesforce.
 * Applies a 10% base discount; enterprise/volume keywords increase to 12%/15%.
 */
function buildMockResponse(products, userPrompt) {
  const prompt = (userPrompt || '').toLowerCase();

  // Detect explicit discount percentage first: "50% discount", "50% off", "at 50%", etc.
  const explicitPct = prompt.match(/(\d+(?:\.\d+)?)\s*%\s*(?:discount|off)/i)
    || prompt.match(/(?:give|apply|with|at)\s+(\d+(?:\.\d+)?)\s*%/i);

  let discountPct;
  if (explicitPct) {
    discountPct = parseFloat(explicitPct[1]);
  } else if (prompt.includes('enterprise')) {
    discountPct = 12.0;
  } else if (prompt.includes('strategic')) {
    discountPct = 15.0;
  } else if (prompt.includes('volume') || /\b2[5-9]\b|\b[3-9]\d\b/.test(prompt)) {
    discountPct = 12.0;
  } else {
    discountPct = 10.0;
  }

  // Detect "all products" intent in the prompt
  const allIntent = /\ball\s+(active\s+)?products?\b/.test(prompt)
    || /\bevery\s+(active\s+)?products?\b/.test(prompt)
    || /\beverything\b/.test(prompt)
    || prompt.includes('all items')
    || prompt.includes('full catalogue')
    || prompt.includes('full catalog');

  // Use passed products array if populated:
  //   - "all" intent → return every product from the Salesforce org pricebook
  //   - specific intent → parse prompt to find which products were requested
  // Fall back to keyword-parsing the prompt if no products array provided.
  let productList;

  if (Array.isArray(products) && products.length > 0) {
    if (allIntent) {
      // Return ALL products from the Salesforce org — no limitation.
      // Use real list prices from the pricebook.
      productList = products.map(p => ({
        code:       p.code || p.productCode,
        list_price: parseFloat(p.list_price || p.unitPrice || p.price || 1000),
        quantity:   1
      }));
    } else {
      productList = products.map(p => ({
        code:       p.code || p.productCode,
        list_price: parseFloat(p.list_price || p.unitPrice || p.price || 1000),
        quantity:   parseInt(p.quantity || 1, 10)
      }));
    }
  } else {
    productList = parsePromptForProducts(userPrompt);
  }

  const rulesApplied = ['Standard Laptop Discount — Max 15%'];
  if (discountPct === 12.0) rulesApplied.push('Enterprise Account Pricing — 5%');
  if (discountPct === 15.0) rulesApplied.push('Strategic Account Override — 15%');

  // Detect bundle: 15" Laptop + Warranty Extension on same quote → extra 5% on warranty
  const codes = productList.map(p => p.code);
  const hasLaptop15    = codes.includes('LAPTOP15');
  const hasWarrantyExt = codes.includes('WARRANTYEXTENSION');
  const bundleActive   = hasLaptop15 && hasWarrantyExt;

  const quoteLines = productList.map(p => {
    const listPrice  = parseFloat((p.list_price || 1499).toFixed(2));
    const quantity   = p.quantity || 1;

    // Apply extra 5% bundle discount to the warranty extension line when bundle is active
    const isBundleWarranty = bundleActive && p.code === 'WARRANTYEXTENSION';
    const effectiveDiscount = isBundleWarranty ? discountPct + 5.0 : discountPct;

    const unitPrice  = parseFloat((listPrice * (1 - effectiveDiscount / 100)).toFixed(2));
    const totalPrice = parseFloat((unitPrice * quantity).toFixed(2));
    const lineRules  = [...rulesApplied];
    if (isBundleWarranty) lineRules.push('Laptop + Warranty Bundle — 5% Extra');

    return {
      product_code:     p.code,
      quantity,
      list_price:       listPrice,
      unit_price:       unitPrice,
      discount_percent: effectiveDiscount,
      total_price:      totalPrice,
      rules_applied:    lineRules
    };
  });

  const subtotal      = parseFloat(quoteLines.reduce((s, l) => s + (l.list_price * l.quantity), 0).toFixed(2));
  const netTotal      = parseFloat(quoteLines.reduce((s, l) => s + l.total_price, 0).toFixed(2));
  const totalDiscount = parseFloat((subtotal - netTotal).toFixed(2));
  const needsApproval = netTotal > 50000;

  return {
    intent: {
      action:   'create_quote',
      products: quoteLines.map(l => l.product_code)
    },
    quote_lines: quoteLines,
    quote_summary: { subtotal, total_discount: totalDiscount, net_total: netTotal },
    approval: {
      required: needsApproval,
      chain:    needsApproval ? 'Sales Manager → VP Sales' : '',
      reason:   needsApproval ? 'Quote total exceeds $50,000 approval threshold' : ''
    },
    warnings: ['MOCK MODE — responses are simulated. Configure LLM_API_KEY for live AI generation.'],
    product_recommendations: []
  };
}

function buildUserMessage(userPrompt, ruleContext, orgContext, products) {
  const parts = [`USER REQUEST: ${userPrompt}`];

  if (products && products.length > 0) {
    parts.push('\nAVAILABLE PRODUCTS:');
    parts.push(JSON.stringify(products, null, 2));
  }

  if (ruleContext) {
    try {
      const rules = JSON.parse(ruleContext);
      parts.push('\nACTIVE BUSINESS RULES:');
      parts.push(JSON.stringify(rules, null, 2));
    } catch (e) {
      parts.push('\nACTIVE BUSINESS RULES: ' + ruleContext);
    }
  }

  if (orgContext) {
    try {
      const ctx = JSON.parse(orgContext);
      parts.push('\nORGANISATION CONTEXT:');
      parts.push(JSON.stringify(ctx, null, 2));
    } catch (e) {
      // Use as-is if not valid JSON
    }
  }

  return parts.join('\n');
}

function parseJSON(rawText, sessionId) {
  // Strip any markdown code blocks if present
  const cleaned = rawText
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/, '')
    .trim();

  try {
    return JSON.parse(cleaned);
  } catch (e) {
    logger.error({ event: 'json_parse_error', sessionId, raw: rawText.slice(0, 500) });
    throw new Error('LLM returned invalid JSON. Response: ' + rawText.slice(0, 200));
  }
}

module.exports = { generateQuote };
