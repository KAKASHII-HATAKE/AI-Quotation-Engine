'use strict';
const Anthropic = require('@anthropic-ai/sdk');
const config    = require('../config');
const { logger } = require('../middleware/logger');

const anthropic = new Anthropic({ apiKey: config.llm.apiKey });

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
