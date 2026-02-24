/**
 * @description Detects the active Salesforce quoting infrastructure on package install
 *              and persists the result in AI_Engine_Config__c.Cloud_Environment__c.
 *              Detection is performed by querying for environment-specific object schemas.
 *
 * Environment values written:
 *   'CPQ_Cloud'          — SBQQ__Quote__c object exists
 *   'Revenue_Cloud'      — OrderItem with revenueCloud attributes exists
 *   'Standard_Salesforce' — neither CPQ nor Revenue Cloud detected
 *
 * @namespace   aqe
 */
public with sharing class AQE_CloudDetector {

    public static final String ENV_CPQ           = 'CPQ_Cloud';
    public static final String ENV_REVENUE        = 'Revenue_Cloud';
    public static final String ENV_STANDARD       = 'Standard_Salesforce';

    /**
     * Detects the current cloud environment and saves it to the custom setting.
     * Safe to call multiple times — idempotent.
     * @return Detected environment string constant
     */
    public static String detectAndSave() {
        String env = detect();
        saveToConfig(env);
        return env;
    }

    /**
     * Detects the current cloud environment without saving.
     * @return Detected environment string constant
     */
    public static String detect() {
        if (isCPQInstalled()) {
            return ENV_CPQ;
        }
        if (isRevenueCloudInstalled()) {
            return ENV_REVENUE;
        }
        return ENV_STANDARD;
    }

    /**
     * Returns the last detected environment from the custom setting.
     * Falls back to live detection if config is not yet set.
     * @return Environment string constant
     */
    public static String getCurrent() {
        AI_Engine_Config__c config = AI_Engine_Config__c.getOrgDefaults();
        if (config != null && String.isNotBlank(config.Cloud_Environment__c)) {
            return config.Cloud_Environment__c;
        }
        return detectAndSave();
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static Boolean isCPQInstalled() {
        // Check if SBQQ__Quote__c is accessible — signature of Salesforce CPQ
        Map<String, Schema.SObjectType> globalDesc = Schema.getGlobalDescribe();
        return globalDesc.containsKey('SBQQ__Quote__c');
    }

    private static Boolean isRevenueCloudInstalled() {
        // Revenue Cloud surfaces as specific fields/objects in the org
        // Check for the OrderItem asset-based ordering fields (Revenue Cloud signature)
        Map<String, Schema.SObjectType> globalDesc = Schema.getGlobalDescribe();
        // OrderItem always exists; Revenue Cloud adds SBQQ__RevenueSchedule__c or
        // the commerce platform objects. We check for the most reliable indicator.
        return globalDesc.containsKey('SBQQ__RevenueSchedule__c')
            || globalDesc.containsKey('blng__BillingSchedule__c');
    }

    private static void saveToConfig(String env) {
        AI_Engine_Config__c config = AI_Engine_Config__c.getOrgDefaults();
        if (config == null) {
            config = new AI_Engine_Config__c();
        }
        config.Cloud_Environment__c       = env;
        config.Max_Quote_Lines__c         = config.Max_Quote_Lines__c == null ? 30 : config.Max_Quote_Lines__c;
        config.Enable_PII_Tokenisation__c = true;
        config.Callout_Timeout_Seconds__c = config.Callout_Timeout_Seconds__c == null ? 120 : config.Callout_Timeout_Seconds__c;

        try {
            upsert config;
        } catch (DmlException e) {
            // Log but don't throw — config save failure should not block install
            System.debug(LoggingLevel.ERROR, 'AQE_CloudDetector: Failed to save config — ' + e.getMessage());
        }
    }
}
