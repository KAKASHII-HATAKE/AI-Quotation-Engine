'use strict';
const config = require('../config');
const { logger } = require('./logger');

/**
 * Validates the Salesforce Org ID in X-AQE-OrgId header.
 * In production, add JWT Bearer token validation here using
 * Salesforce Connected App OAuth JWT Bearer flow.
 */
function validateOrgId(req, res, next) {
  const orgId = req.headers['x-aqe-orgid'];

  if (!orgId) {
    logger.warn({ event: 'auth_rejected', reason: 'Missing X-AQE-OrgId header', ip: req.ip });
    return res.status(401).json({ error: 'Missing required header: X-AQE-OrgId' });
  }

  // If allowed org list is configured, enforce it
  const allowed = config.security.allowedOrgIds;
  if (allowed.length > 0 && !allowed.includes(orgId)) {
    logger.warn({ event: 'auth_rejected', reason: 'Org ID not in allowlist', orgId });
    return res.status(403).json({ error: 'Org not authorised to use this service.' });
  }

  req.orgId = orgId;
  next();
}

module.exports = { validateOrgId };
