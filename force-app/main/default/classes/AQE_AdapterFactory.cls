/**
 * @description Factory class that selects and returns the correct AQE_IQuoteAdapter
 *              implementation based on the detected cloud environment.
 *
 *              The adapter instance is cached per-transaction (static variable) to avoid
 *              repeated SOQL calls to AI_Engine_Config__c within the same execution context.
 *              Call resetAdapter() in tests between scenarios.
 *
 * @namespace   aqe
 */
public with sharing class AQE_AdapterFactory {

    private static AQE_IQuoteAdapter instance;

    /**
     * Returns the appropriate adapter for the current org's cloud environment.
     * Cached after first call within a transaction.
     * @return AQE_IQuoteAdapter implementation
     * @throws AQE_Exception if environment is unrecognised
     */
    public static AQE_IQuoteAdapter getAdapter() {
        if (instance != null) {
            return instance;
        }

        String env = AQE_CloudDetector.getCurrent();

        if (env == AQE_CloudDetector.ENV_CPQ) {
            // Dynamic instantiation allows CPQ adapter to compile even without CPQ installed
            Type t = Type.forName('AQE_CPQQuoteAdapter');
            if (t == null) {
                throw new AQE_Exception('AQE_CPQQuoteAdapter class not found. Ensure CPQ adapter is deployed.');
            }
            instance = (AQE_IQuoteAdapter) t.newInstance();

        } else if (env == AQE_CloudDetector.ENV_REVENUE) {
            Type t = Type.forName('AQE_RevenueCloudAdapter');
            if (t == null) {
                throw new AQE_Exception('AQE_RevenueCloudAdapter class not found. Ensure Revenue Cloud adapter is deployed.');
            }
            instance = (AQE_IQuoteAdapter) t.newInstance();

        } else {
            // Default: Standard Salesforce Quote object
            instance = new AQE_StandardQuoteAdapter();
        }

        return instance;
    }

    /**
     * Clears the cached adapter instance. Call in tests between test methods
     * or when you need to force re-detection.
     */
    public static void resetAdapter() {
        instance = null;
    }

    /**
     * Allows tests to inject a mock adapter without touching custom settings.
     * @param mockAdapter Test double implementing AQE_IQuoteAdapter
     */
    @TestVisible
    private static void setAdapter(AQE_IQuoteAdapter mockAdapter) {
        instance = mockAdapter;
    }
}
