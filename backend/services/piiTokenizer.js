'use strict';
const config = require('../config');

/**
 * PII Tokenizer — strips and replaces personally identifiable information
 * from user prompts before they reach the LLM.
 *
 * Maintains a token map so PII can be restored in responses if needed
 * (though typically we never return raw PII back from the LLM).
 */

/**
 * Tokenises a full prompt, replacing PII with anonymous tokens.
 * @param {string} input Raw user prompt
 * @returns {{ sanitisedPrompt: string, tokenMap: object }}
 */
function tokenise(input) {
  if (!input) return { sanitisedPrompt: '', tokenMap: {} };

  let sanitised = input;
  const tokenMap = {};
  let counter = 0;

  for (const { pattern, token } of config.pii.patterns) {
    sanitised = sanitised.replace(pattern, (match) => {
      const key = `${token}_${counter++}`;
      tokenMap[key] = match;
      return key;
    });
  }

  return { sanitisedPrompt: sanitised, tokenMap };
}

/**
 * Tokenises a string (non-prompt context fields).
 * @param {string} input
 * @returns {{ sanitised: string }}
 */
function tokeniseString(input) {
  if (!input) return { sanitised: '' };
  let sanitised = input;
  for (const { pattern, token } of config.pii.patterns) {
    sanitised = sanitised.replace(pattern, token);
  }
  return { sanitised };
}

/**
 * Restores tokens back to their original PII values in a string.
 * Use only for user-facing messages, never for LLM context.
 * @param {string} text Text containing tokens
 * @param {object} tokenMap Token-to-original mapping from tokenise()
 * @returns {string} Detokenised string
 */
function detokenise(text, tokenMap) {
  if (!text || !tokenMap) return text;
  let result = text;
  for (const [key, value] of Object.entries(tokenMap)) {
    result = result.replaceAll(key, value);
  }
  return result;
}

module.exports = { tokenise, tokeniseString, detokenise };
