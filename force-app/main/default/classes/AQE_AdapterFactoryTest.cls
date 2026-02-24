/**
 * @description Tests for AQE_AdapterFactory.
 * @namespace   aqe
 */
@IsTest
private class AQE_AdapterFactoryTest {

    @TestSetup
    static void setup() {
        AI_Engine_Config__c config = new AI_Engine_Config__c(
            Engine_Active__c     = true,
            Cloud_Environment__c = AQE_CloudDetector.ENV_STANDARD,
            Max_Quote_Lines__c   = 30
        );
        upsert config;
    }

    @IsTest
    static void testGetAdapterReturnsStandardForStandardEnv() {
        Test.startTest();
        AQE_AdapterFactory.resetAdapter();
        AQE_IQuoteAdapter adapter = AQE_AdapterFactory.getAdapter();
        Test.stopTest();

        System.assertNotEquals(null, adapter, 'Adapter should not be null');
        System.assertEquals(AQE_CloudDetector.ENV_STANDARD, adapter.getEnvironmentType(),
            'Should return Standard adapter when env = Standard_Salesforce');
    }

    @IsTest
    static void testGetAdapterIsCachedWithinTransaction() {
        AQE_AdapterFactory.resetAdapter();

        Test.startTest();
        AQE_IQuoteAdapter first  = AQE_AdapterFactory.getAdapter();
        AQE_IQuoteAdapter second = AQE_AdapterFactory.getAdapter();
        Test.stopTest();

        System.assert(first === second, 'Adapter should be the same cached instance within a transaction');
    }

    @IsTest
    static void testResetAdapterClearsCache() {
        AQE_AdapterFactory.getAdapter(); // Prime cache

        Test.startTest();
        AQE_AdapterFactory.resetAdapter();
        AQE_IQuoteAdapter adapter = AQE_AdapterFactory.getAdapter();
        Test.stopTest();

        System.assertNotEquals(null, adapter, 'Should return a fresh adapter after reset');
    }

    @IsTest
    static void testSetAdapterInjectsTestDouble() {
        AQE_StandardQuoteAdapter mockAdapter = new AQE_StandardQuoteAdapter();

        Test.startTest();
        AQE_AdapterFactory.setAdapter(mockAdapter);
        AQE_IQuoteAdapter retrieved = AQE_AdapterFactory.getAdapter();
        Test.stopTest();

        System.assertEquals(mockAdapter, retrieved, 'Test double should be returned after injection');
        AQE_AdapterFactory.resetAdapter();
    }
}
