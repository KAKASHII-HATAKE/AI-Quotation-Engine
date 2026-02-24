/**
 * @description Tests for AQE_CloudDetector.
 * @namespace   aqe
 */
@IsTest
private class AQE_CloudDetectorTest {

    @TestSetup
    static void setup() {
        // Ensure no existing config interferes
        AI_Engine_Config__c config = new AI_Engine_Config__c(
            Engine_Active__c = false,
            Cloud_Environment__c = null
        );
        upsert config;
    }

    @IsTest
    static void testDetectReturnsValidEnvironment() {
        Test.startTest();
        String env = AQE_CloudDetector.detect();
        Test.stopTest();

        System.assertNotEquals(null, env, 'Detect should return a non-null environment');
        List<String> valid = new List<String>{
            AQE_CloudDetector.ENV_STANDARD,
            AQE_CloudDetector.ENV_CPQ,
            AQE_CloudDetector.ENV_REVENUE
        };
        System.assert(valid.contains(env), 'Detected environment should be one of the valid constants: ' + env);
    }

    @IsTest
    static void testDetectAndSavePersistsToConfig() {
        Test.startTest();
        String env = AQE_CloudDetector.detectAndSave();
        Test.stopTest();

        AI_Engine_Config__c config = AI_Engine_Config__c.getOrgDefaults();
        System.assertNotEquals(null, config, 'Config should exist after detectAndSave');
        System.assertEquals(env, config.Cloud_Environment__c, 'Config should have the detected environment');
    }

    @IsTest
    static void testGetCurrentUsesExistingConfig() {
        // Pre-set config to known value
        AI_Engine_Config__c config = new AI_Engine_Config__c(
            Cloud_Environment__c = AQE_CloudDetector.ENV_STANDARD
        );
        upsert config;

        Test.startTest();
        String env = AQE_CloudDetector.getCurrent();
        Test.stopTest();

        System.assertEquals(AQE_CloudDetector.ENV_STANDARD, env,
            'getCurrent should return the pre-configured environment');
    }

    @IsTest
    static void testGetCurrentFallsBackToDetection() {
        // Config with blank environment
        AI_Engine_Config__c config = new AI_Engine_Config__c(
            Cloud_Environment__c = ''
        );
        upsert config;

        Test.startTest();
        String env = AQE_CloudDetector.getCurrent();
        Test.stopTest();

        System.assertNotEquals(null, env, 'Fallback detection should return a valid environment');
    }

    @IsTest
    static void testDefaultsAreSetAfterDetection() {
        Test.startTest();
        AQE_CloudDetector.detectAndSave();
        Test.stopTest();

        AI_Engine_Config__c config = AI_Engine_Config__c.getOrgDefaults();
        System.assertEquals(30, config.Max_Quote_Lines__c, 'Default Max_Quote_Lines__c should be 30');
        System.assertEquals(true, config.Enable_PII_Tokenisation__c, 'PII tokenisation should default to true');
        System.assertEquals(120, config.Callout_Timeout_Seconds__c, 'Default timeout should be 120 seconds');
    }
}
