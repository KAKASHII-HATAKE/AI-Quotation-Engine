/**
 * AQE Backend Configuration
 * All values read from environment variables — no hardcoded secrets.
 * Copy .env.example to .env and populate before running.
 */
require('dotenv').config();

module.exports = {
  server: {
    port:    parseInt(process.env.PORT || '3000', 10),
    nodeEnv: process.env.NODE_ENV || 'production',
  },

  llm: {
    provider:    process.env.LLM_PROVIDER || 'anthropic', // 'anthropic' | 'openai'
    apiKey:      process.env.LLM_API_KEY,                  // REQUIRED — set in env
    model:       process.env.LLM_MODEL || 'claude-sonnet-4-6',
    maxTokens:   parseInt(process.env.LLM_MAX_TOKENS || '4096', 10),
    temperature: parseFloat(process.env.LLM_TEMPERATURE || '0.1'),
  },

  security: {
    // Salesforce org IDs allowed to call this service (comma-separated)
    allowedOrgIds: (process.env.ALLOWED_ORG_IDS || '').split(',').filter(Boolean),
    rateLimitWindowMs:   parseInt(process.env.RATE_LIMIT_WINDOW_MS || '60000', 10),
    rateLimitMaxRequests: parseInt(process.env.RATE_LIMIT_MAX || '20', 10),
  },

  pii: {
    enabled:  process.env.PII_TOKENISATION_ENABLED !== 'false',
    patterns: [
      // Email addresses
      { pattern: /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g, token: '[EMAIL]' },
      // Phone numbers (various formats)
      { pattern: /(\+?[\d\s\-().]{10,17})/g, token: '[PHONE]' },
      // Salesforce IDs (15/18 char)
      { pattern: /\b[a-zA-Z0-9]{15,18}\b/g, token: '[SF_ID]' },
    ]
  },

  logging: {
    level: process.env.LOG_LEVEL || 'info',
  }
};
