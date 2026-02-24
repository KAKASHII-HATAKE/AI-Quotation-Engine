/**
 * AQE Post-Install Script
 * Run this anonymous Apex after deploying the package to a new org.
 *
 * Run with: sf apex run --file scripts/apex/postInstall.apex
 */

// Step 1: Auto-detect and save cloud environment
String env = AQE_CloudDetector.detectAndSave();
System.debug('AQE: Cloud environment detected — ' + env);

// Step 2: Initialise default AI Engine Config values
AI_Engine_Config__c config = AI_Engine_Config__c.getOrgDefaults();
if (config == null) {
    config = new AI_Engine_Config__c();
}

// Set sensible defaults — admin must configure LLM_Endpoint_URL__c and LLM_Model__c
config.Cloud_Environment__c       = env;
config.Max_Quote_Lines__c         = 30;
config.Enable_PII_Tokenisation__c = true;
config.Callout_Timeout_Seconds__c = 120;
config.Engine_Active__c           = false; // Admin must explicitly activate after config

upsert config;

System.debug('AQE: Engine Config initialised. Set Engine_Active__c = true after configuring Named Credential AQE_Backend and LLM_Model__c.');
System.debug('AQE: Post-install complete.');
