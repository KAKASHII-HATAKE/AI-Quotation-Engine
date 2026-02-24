/**
 * @description Centralised security utility for the AQE package.
 *              Enforces FLS, CRUD, object access checks, and input sanitisation.
 *              All DML-performing classes must call these methods before data access.
 * @namespace   aqe
 */
public with sharing class AQE_SecurityUtil {

    public static final String DML_CREATE = 'CREATE';
    public static final String DML_READ   = 'READ';
    public static final String DML_UPDATE = 'UPDATE';
    public static final String DML_DELETE = 'DELETE';

    /**
     * Verifies the running user has the specified CRUD permission on the object.
     * @param objectApiName SObject API name (e.g. 'Quote', 'SBQQ__Quote__c')
     * @param operation     One of DML_CREATE, DML_READ, DML_UPDATE, DML_DELETE
     * @throws AQE_Exception if permission is denied
     */
    public static void checkObjectAccess(String objectApiName, String operation) {
        Schema.DescribeSObjectResult descr = getDescribe(objectApiName);
        if (descr == null) {
            throw new AQE_Exception('Object not found: ' + objectApiName);
        }
        Boolean allowed = false;
        if      (operation == DML_CREATE) allowed = descr.isCreateable();
        else if (operation == DML_READ)   allowed = descr.isAccessible();
        else if (operation == DML_UPDATE) allowed = descr.isUpdateable();
        else if (operation == DML_DELETE) allowed = descr.isDeletable();

        if (!allowed) {
            throw new AQE_Exception(
                'Insufficient permissions: ' + operation + ' on ' + objectApiName
                + '. Contact your administrator.'
            );
        }
    }

    /**
     * Verifies the running user has field-level access to the specified fields.
     * @param objectApiName SObject API name
     * @param fieldApiNames List of field API names to check
     * @param operation     DML_READ or DML_UPDATE (CREATE = same as UPDATE for FLS)
     * @throws AQE_Exception if any field permission is denied
     */
    public static void checkFieldAccess(String objectApiName, List<String> fieldApiNames, String operation) {
        Schema.DescribeSObjectResult descr = getDescribe(objectApiName);
        if (descr == null) return;
        Map<String, Schema.SObjectField> fieldMap = descr.fields.getMap();

        for (String fieldName : fieldApiNames) {
            String fieldLower = fieldName.toLowerCase();
            if (!fieldMap.containsKey(fieldLower)) continue;
            Schema.DescribeFieldResult fdr = fieldMap.get(fieldLower).getDescribe();
            Boolean allowed = false;
            if      (operation == DML_READ)   allowed = fdr.isAccessible();
            else if (operation == DML_CREATE || operation == DML_UPDATE) allowed = fdr.isUpdateable();
            if (!allowed) {
                throw new AQE_Exception(
                    'Insufficient field permissions: ' + operation + ' on ' + objectApiName + '.' + fieldName
                );
            }
        }
    }

    /**
     * Sanitises a string value for safe use in dynamic SOQL.
     * Always prefer bind variables over this method; use only when bind vars aren't possible.
     * @param input Raw input string
     * @return Escaped string safe for SOQL
     */
    public static String sanitiseForSoql(String input) {
        if (input == null) return null;
        return String.escapeSingleQuotes(input.trim());
    }

    /**
     * Validates that a string is a valid Salesforce ID (15 or 18 char).
     * @param idStr Potential Salesforce ID string
     * @return true if valid, false otherwise
     */
    public static Boolean isValidSalesforceId(String idStr) {
        if (String.isBlank(idStr)) return false;
        if (idStr.length() != 15 && idStr.length() != 18) return false;
        try {
            Id testId = (Id) idStr;
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Checks governor limit headroom before performing bulk operations.
     * Throws AQE_Exception if DML limits are critically close.
     */
    public static void checkGovernorLimits() {
        if (Limits.getDmlStatements() >= (Limits.getLimitDmlStatements() - 5)) {
            throw new AQE_Exception('Governor limit warning: DML statement limit approaching. Retry as async batch.');
        }
        if (Limits.getQueries() >= (Limits.getLimitQueries() - 10)) {
            throw new AQE_Exception('Governor limit warning: SOQL query limit approaching.');
        }
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static Map<String, Schema.DescribeSObjectResult> describeCache = new Map<String, Schema.DescribeSObjectResult>();

    private static Schema.DescribeSObjectResult getDescribe(String objectApiName) {
        String key = objectApiName.toLowerCase();
        if (describeCache.containsKey(key)) {
            return describeCache.get(key);
        }
        Map<String, Schema.SObjectType> globalDesc = Schema.getGlobalDescribe();
        if (!globalDesc.containsKey(key)) return null;
        Schema.DescribeSObjectResult result = globalDesc.get(key).getDescribe();
        describeCache.put(key, result);
        return result;
    }
}
