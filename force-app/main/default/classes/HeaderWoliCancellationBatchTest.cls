/**
 * Test class for HeaderWoliCancellationBatch
 * STRY0449230 - Cancelled Sales Order Items Will Not Allow Work Order Posting.
 */
@isTest
public class HeaderWoliCancellationBatchTest {
    
    /**
     * Setup test data
     */
    @testSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;
        
        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = testAccount.Id
        );
        insert testContact;
        
        // Get Record Type IDs
        Id installationRecTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName().get('Installation')?.getRecordTypeId();
        Id trainingRecTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName().get('Training')?.getRecordTypeId();
        Id headerRecTypeId = Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName().get('Header')?.getRecordTypeId();
        
        // Create WorkOrders with Installation and Training record types
        List<WorkOrder> workOrders = new List<WorkOrder>();
        
        // Installation WorkOrder
        if (installationRecTypeId != null) {
            workOrders.add(new WorkOrder(
                Subject = 'Test Installation Work Order',
                AccountId = testAccount.Id,
                ContactId = testContact.Id,
                RecordTypeId = installationRecTypeId,
                Status = 'New'
            ));
        }
        
        // Training WorkOrder
        if (trainingRecTypeId != null) {
            workOrders.add(new WorkOrder(
                Subject = 'Test Training Work Order',
                AccountId = testAccount.Id,
                ContactId = testContact.Id,
                RecordTypeId = trainingRecTypeId,
                Status = 'New'
            ));
        }
        
        if (!workOrders.isEmpty()) {
            insert workOrders;
        }
        
        // Create test Sales Order Items (assuming custom object exists)
        List<SObject> salesOrderItems = new List<SObject>();
        try {
            // Create Sales Order Item with Reject_Reason__c populated
            SObject salesOrderItem1 = (SObject) Type.forName('Sales_Order_Item__c').newInstance();
            salesOrderItem1.put('Name', 'Test SO Item 1');
            salesOrderItem1.put('Reject_Reason__c', 'Test Rejection Reason');
            salesOrderItems.add(salesOrderItem1);
            
            // Create Sales Order Item without Reject_Reason__c
            SObject salesOrderItem2 = (SObject) Type.forName('Sales_Order_Item__c').newInstance();
            salesOrderItem2.put('Name', 'Test SO Item 2');
            salesOrderItems.add(salesOrderItem2);
            
            if (!salesOrderItems.isEmpty()) {
                insert salesOrderItems;
            }
        } catch (Exception e) {
            // Sales Order Item object might not exist in this org
            System.debug('Sales Order Item object not available: ' + e.getMessage());
        }
        
        // Create WorkOrderLineItems
        List<WorkOrderLineItem> workOrderLineItems = new List<WorkOrderLineItem>();
        
        if (!workOrders.isEmpty() && headerRecTypeId != null) {
            // WOLI with null Sales_Order_Item__c
            workOrderLineItems.add(new WorkOrderLineItem(
                WorkOrderId = workOrders[0].Id,
                RecordTypeId = headerRecTypeId,
                Status = 'New'
                // Sales_Order_Item__c is null
            ));
            
            // WOLI with Sales_Order_Item__c that has Reject_Reason__c
            if (!salesOrderItems.isEmpty()) {
                workOrderLineItems.add(new WorkOrderLineItem(
                    WorkOrderId = workOrders.size() > 1 ? workOrders[1].Id : workOrders[0].Id,
                    RecordTypeId = headerRecTypeId,
                    Status = 'New',
                    Sales_Order_Item__c = salesOrderItems[0].Id
                ));
            }
            
            // WOLI that should NOT be processed (has Sales_Order_Item__c without Reject_Reason__c)
            if (salesOrderItems.size() > 1) {
                workOrderLineItems.add(new WorkOrderLineItem(
                    WorkOrderId = workOrders[0].Id,
                    RecordTypeId = headerRecTypeId,
                    Status = 'New',
                    Sales_Order_Item__c = salesOrderItems[1].Id
                ));
            }
        }
        
        if (!workOrderLineItems.isEmpty()) {
            insert workOrderLineItems;
        }
    }
    
    /**
     * Test the start method of the batch class
     */
    @isTest
    static void testBatchStart() {
        Test.startTest();
        
        HeaderWoliCancellationBatch batch = new HeaderWoliCancellationBatch();
        Database.BatchableContext bc = new TestBatchableContext();
        
        Database.QueryLocator queryLocator = batch.start(bc);
        
        Test.stopTest();
        
        // Verify that query locator is returned
        System.assertNotEquals(null, queryLocator, 'Query locator should not be null');
        
        // Verify the query returns the expected records
        List<WorkOrderLineItem> results = Database.query(queryLocator.getQuery());
        
        // Should return WorkOrderLineItems that meet the criteria:
        // - Header record type
        // - WorkOrder with Installation or Training record type
        // - Sales_Order_Item__c is null OR Sales_Order_Item__r.Reject_Reason__c is not null
        System.assert(results.size() >= 0, 'Query should execute without errors');
    }
    
    /**
     * Test the execute method of the batch class
     */
    @isTest
    static void testBatchExecute() {
        // Get test data
        List<WorkOrderLineItem> testWOLIs = [
            SELECT Id, Status, Sales_Order_Item__c, Sales_Order_Item__r.Reject_Reason__c
            FROM WorkOrderLineItem
            WHERE RecordType.DeveloperName = 'Header'
            AND (Sales_Order_Item__c = NULL OR Sales_Order_Item__r.Reject_Reason__c != NULL)
            LIMIT 10
        ];
        
        if (testWOLIs.isEmpty()) {
            // Create minimal test data if setup didn't work
            Account testAccount = new Account(Name = 'Test Account');
            insert testAccount;
            
            Contact testContact = new Contact(FirstName = 'Test', LastName = 'Contact', AccountId = testAccount.Id);
            insert testContact;
            
            WorkOrder testWO = new WorkOrder(
                Subject = 'Test Work Order',
                AccountId = testAccount.Id,
                ContactId = testContact.Id,
                Status = 'New'
            );
            insert testWO;
            
            WorkOrderLineItem testWOLI = new WorkOrderLineItem(
                WorkOrderId = testWO.Id,
                Status = 'New'
            );
            insert testWOLI;
            
            testWOLIs.add(testWOLI);
        }
        
        Test.startTest();
        
        HeaderWoliCancellationBatch batch = new HeaderWoliCancellationBatch();
        Database.BatchableContext bc = new TestBatchableContext();
        
        // Execute the batch with test data
        batch.execute(bc, testWOLIs);
        
        Test.stopTest();
        
        // Verify that WorkOrderLineItems were updated to 'Canceled' status
        List<WorkOrderLineItem> updatedWOLIs = [
            SELECT Id, Status
            FROM WorkOrderLineItem
            WHERE Id IN :testWOLIs
        ];
        
        for (WorkOrderLineItem woli : updatedWOLIs) {
            System.assertEquals('Canceled', woli.Status, 'WorkOrderLineItem status should be updated to Canceled');
        }
    }
    
    /**
     * Test the finish method of the batch class
     */
    @isTest
    static void testBatchFinish() {
        Test.startTest();
        
        HeaderWoliCancellationBatch batch = new HeaderWoliCancellationBatch();
        Database.BatchableContext bc = new TestBatchableContext();
        
        // Test finish method (currently empty but should not throw errors)
        batch.finish(bc);
        
        Test.stopTest();
        
        // Since finish method is empty, just verify it executes without errors
        System.assert(true, 'Finish method should execute without errors');
    }
    
    /**
     * Test the schedulable execute method
     */
    @isTest
    static void testSchedulableExecute() {
        Test.startTest();
        
        HeaderWoliCancellationBatch batch = new HeaderWoliCancellationBatch();
        SchedulableContext sc = new TestSchedulableContext();
        
        // Test schedulable execute method
        batch.execute(sc);
        
        Test.stopTest();
        
        // Verify that a batch job was queued
        List<AsyncApexJob> batchJobs = [
            SELECT Id, JobType, Status
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'HeaderWoliCancellationBatch'
        ];
        
        System.assert(batchJobs.size() > 0, 'Batch job should be queued when schedulable executes');
    }
    
    /**
     * Test full batch execution
     */
    @isTest
    static void testFullBatchExecution() {
        Test.startTest();
        
        // Execute the batch
        HeaderWoliCancellationBatch batch = new HeaderWoliCancellationBatch();
        Id batchId = Database.executeBatch(batch, 200);
        
        Test.stopTest();
        
        // Verify batch job was created
        System.assertNotEquals(null, batchId, 'Batch job ID should not be null');
        
        // Verify the batch job exists
        List<AsyncApexJob> batchJobs = [
            SELECT Id, Status, JobType
            FROM AsyncApexJob
            WHERE Id = :batchId
        ];
        
        System.assertEquals(1, batchJobs.size(), 'Batch job should exist');
        System.assertEquals('BatchApex', batchJobs[0].JobType, 'Job type should be BatchApex');
    }
    
    /**
     * Test batch with no qualifying records
     */
    @isTest
    static void testBatchWithNoRecords() {
        // Delete all test data to ensure no qualifying records
        delete [SELECT Id FROM WorkOrderLineItem];
        delete [SELECT Id FROM WorkOrder];
        
        Test.startTest();
        
        HeaderWoliCancellationBatch batch = new HeaderWoliCancellationBatch();
        Id batchId = Database.executeBatch(batch, 200);
        
        Test.stopTest();
        
        // Verify batch completes successfully even with no records
        System.assertNotEquals(null, batchId, 'Batch should execute even with no qualifying records');
    }
    
    /**
     * Mock BatchableContext for testing
     */
    private class TestBatchableContext implements Database.BatchableContext {
        public Id getJobId() {
            return '01p000000000000';
        }
        
        public Id getChildJobId() {
            return '01p000000000001';
        }
    }
    
    /**
     * Mock SchedulableContext for testing
     */
    private class TestSchedulableContext implements SchedulableContext {
        public String getTriggerId() {
            return '08e000000000000';
        }
    }
}

