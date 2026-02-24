/**
 * AQE Backend — Express.js Entry Point
 * LLM Orchestration Middleware for Salesforce AQE Package
 */
'use strict';

const express      = require('express');
const helmet       = require('helmet');
const cors         = require('cors');
const rateLimit    = require('express-rate-limit');
const { v4: uuid } = require('uuid');
const config       = require('./config');
const { logger }   = require('./middleware/logger');
const auth         = require('./middleware/auth');
const llmOrchestrator = require('./services/llmOrchestrator');
const ruleValidator   = require('./services/ruleValidator');
const piiTokenizer    = require('./services/piiTokenizer');
const Joi          = require('joi');

const app = express();

// ─── Security middleware ───────────────────────────────────────────────────────
app.use(helmet({
  contentSecurityPolicy: false, // API server — no HTML
  crossOriginEmbedderPolicy: false
}));

app.use(cors({
  origin: false, // No browser CORS — Salesforce callouts go server-to-server
  methods: ['GET', 'POST'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-AQE-OrgId', 'X-AQE-SessionId']
}));

app.use(express.json({ limit: '2mb' }));

// ─── Rate limiting ─────────────────────────────────────────────────────────────
const limiter = rateLimit({
  windowMs: config.security.rateLimitWindowMs,
  max:      config.security.rateLimitMaxRequests,
  keyGenerator: (req) => req.headers['x-aqe-orgid'] || req.ip,
  message: { error: 'Rate limit exceeded. Please wait before retrying.' }
});
app.use('/api/', limiter);

// ─── Request logging ───────────────────────────────────────────────────────────
app.use((req, res, next) => {
  req.requestId = uuid();
  logger.info({ requestId: req.requestId, method: req.method, path: req.path,
    orgId: req.headers['x-aqe-orgid'] });
  next();
});

// ─── Routes ───────────────────────────────────────────────────────────────────

// Health check — no auth required
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', version: '1.0.0', timestamp: new Date().toISOString() });
});

// Quote generation — auth required
app.post('/api/quote/generate', auth.validateOrgId, async (req, res) => {
  const sessionId = req.headers['x-aqe-sessionid'] || uuid();

  // Input validation
  const schema = Joi.object({
    userPrompt:  Joi.string().min(3).max(2000).required(),
    ruleContext: Joi.string().allow('', null),
    orgContext:  Joi.string().allow('', null),
    sessionId:   Joi.string().allow('', null),
    products:    Joi.array().items(Joi.object()).allow(null)
  });
  const { error: validationError, value } = schema.validate(req.body);
  if (validationError) {
    return res.status(400).json({ success: false, error: validationError.details[0].message });
  }

  try {
    // 1. PII tokenisation
    const { sanitisedPrompt, tokenMap } = config.pii.enabled
      ? piiTokenizer.tokenise(value.userPrompt)
      : { sanitisedPrompt: value.userPrompt, tokenMap: {} };

    const sanitisedContext = config.pii.enabled
      ? piiTokenizer.tokeniseString(value.orgContext || '')
      : { sanitised: value.orgContext || '' };

    // 2. Call LLM
    const llmResponse = await llmOrchestrator.generateQuote({
      userPrompt:  sanitisedPrompt,
      ruleContext: value.ruleContext,
      orgContext:  sanitisedContext.sanitised,
      products:    value.products || [],
      sessionId
    });

    // 3. Deterministic validation
    const validatedResponse = ruleValidator.validate(llmResponse, value.products || []);

    // 4. Restore PII tokens in any user-facing strings (warnings etc.)
    if (config.pii.enabled && validatedResponse.warnings) {
      validatedResponse.warnings = validatedResponse.warnings.map(
        w => piiTokenizer.detokenise(w, tokenMap)
      );
    }

    logger.info({ requestId: req.requestId, sessionId, success: true,
      lineCount: (validatedResponse.quote_lines || []).length });

    res.json({ success: true, ...validatedResponse });

  } catch (err) {
    logger.error({ requestId: req.requestId, sessionId, error: err.message, stack: err.stack });
    res.status(500).json({
      success: false,
      error: err.message,
      requestId: req.requestId
    });
  }
});

// ─── Start server ──────────────────────────────────────────────────────────────
const port = config.server.port;
app.listen(port, () => {
  logger.info(`AQE Backend running on port ${port} [${config.server.nodeEnv}]`);
  if (!config.llm.apiKey) {
    logger.warn('WARNING: LLM_API_KEY is not set. Quote generation will fail.');
  }
});

module.exports = app; // For testing
