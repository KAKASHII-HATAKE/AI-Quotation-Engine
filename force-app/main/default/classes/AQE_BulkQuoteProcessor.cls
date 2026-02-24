/**
 * @description Async batch processor for large quotes exceeding the synchronous
 *              line limit (configured in AI_Engine_Config__c.Max_Quote_Lines__c).
 *
 *              Solves Salesforce's UI bottleneck beyond 30-40 lines by processing
 *              lines asynchronously via Queueable. Each line gets an External_Ref__c
 *              for idempotency. A verification job runs post-creation to detect
 *              discrepancies and trigger rollback if needed.
 *
 * @namespace   aqe
 */
public with sharing class AQE_BulkQuoteProcessor implements Queueable {

    private Id quoteId;
    private List<AQE_QuoteLineDTO> lines;
    private String batchTransactionId;
    private Id transactionLogId;
    private Integer chunkStart;
    private static final Integer CHUNK_SIZE = 50;

    public AQE_BulkQuoteProcessor(
        Id quoteId,
        List<AQE_QuoteLineDTO> lines,
        String batchTransactionId,
        Id transactionLogId,
        Integer chunkStart
    ) {
        this.quoteId            = quoteId;
        this.lines              = lines;
        this.batchTransactionId = batchTransactionId;
        this.transactionLogId   = transactionLogId;
        this.chunkStart         = chunkStart;
    }

    /**
     * Enqueues a bulk quote processing job.
     * @param quoteId           Target quote Record ID
     * @param lines             All lines to create (chunked internally)
     * @param transactionLogId  AI_Transaction_Log__c Record ID for status tracking
     * @return Batch transaction ID (UUID-style string for correlation)
     */
    public static String enqueueBulkCreation(
        Id quoteId,
        List<AQE_QuoteLineDTO> lines,
        Id transactionLogId
    ) {
        String batchId = generateBatchId();

        // Assign external refs for idempotency
        for (Integer i = 0; i < lines.size(); i++) {
            lines[i].externalRef = batchId + '-' + String.valueOf(i).leftPad(6, '0');
        }

        System.enqueueJob(new AQE_BulkQuoteProcessor(
            quoteId, lines, batchId, transactionLogId, 0
        ));

        return batchId;
    }

    /**
     * Queueable execute — processes CHUNK_SIZE lines, then chains next chunk.
     */
    public void execute(QueueableContext context) {
        AQE_IQuoteAdapter adapter = AQE_AdapterFactory.getAdapter();

        Integer chunkEnd = Math.min(chunkStart + CHUNK_SIZE, lines.size());
        List<AQE_QuoteLineDTO> chunk = new List<AQE_QuoteLineDTO>();
        for (Integer i = chunkStart; i < chunkEnd; i++) {
            chunk.add(lines[i]);
        }

        try {
            List<Id> createdIds = adapter.createQuoteLines(quoteId, chunk);

            // Update progress in transaction log
            updateLogProgress(transactionLogId, chunkEnd, lines.size(), batchTransactionId);

            // Chain next chunk if more lines remain
            if (chunkEnd < lines.size()) {
                System.enqueueJob(new AQE_BulkQuoteProcessor(
                    quoteId, lines, batchTransactionId, transactionLogId, chunkEnd
                ));
            } else {
                // All chunks processed — mark complete
                finaliseLog(transactionLogId, 'Success');
            }

        } catch (Exception e) {
            String errMsg = 'Bulk line creation failed at chunk ' + chunkStart + ': ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'AQE_BulkQuoteProcessor: ' + errMsg);
            // Persist error in transaction log so it is visible in the audit log UI
            if (transactionLogId != null) {
                try {
                    update new AI_Transaction_Log__c(
                        Id = transactionLogId,
                        Processing_Status__c = 'LLM Error',
                        Validation_Errors__c = JSON.serialize(new List<String>{ errMsg })
                    );
                } catch (Exception logEx) {
                    System.debug(LoggingLevel.WARN, 'Could not update log with error: ' + logEx.getMessage());
                }
            }
            rollbackCreatedLines(quoteId, adapter);
        }
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static String generateBatchId() {
        return 'BATCH-' + String.valueOf(DateTime.now().getTime()) + '-'
            + EncodingUtil.base64Encode(Crypto.generateAESKey(128)).left(8);
    }

    private static void updateLogProgress(Id logId, Integer processed, Integer total, String batchId) {
        if (logId == null) return;
        try {
            AI_Transaction_Log__c log = new AI_Transaction_Log__c(
                Id = logId,
                Batch_Transaction_Id__c = batchId,
                Processing_Status__c = processed < total ? 'Pending' : 'Success'
            );
            update log;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Could not update transaction log: ' + e.getMessage());
        }
    }

    private static void finaliseLog(Id logId, String status) {
        if (logId == null) return;
        try {
            AI_Transaction_Log__c log = new AI_Transaction_Log__c(
                Id = logId,
                Processing_Status__c = status
            );
            update log;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Could not finalise transaction log: ' + e.getMessage());
        }
    }

    private static void rollbackCreatedLines(Id quoteId, AQE_IQuoteAdapter adapter) {
        // Delete all lines on the quote using the adapter — works for Standard, CPQ, and Revenue Cloud.
        try {
            List<AQE_QuoteLineDTO> existing = adapter.getQuoteLines(quoteId);
            if (!existing.isEmpty()) {
                List<Id> ids = new List<Id>();
                for (AQE_QuoteLineDTO line : existing) {
                    if (line.id != null) { ids.add(line.id); }
                }
                if (!ids.isEmpty()) {
                    adapter.deleteQuoteLines(ids);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Rollback failed: ' + e.getMessage());
        }
    }
}
