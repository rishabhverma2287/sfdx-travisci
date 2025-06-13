/**
 * STRY0449230 - Cancelled Sales Order Items Will Not Allow Work Order Posting.
 */
global class HeaderWoliCancellationBatch implements Database.Batchable <sObject>,Database.Stateful,Schedulable{
	 
    /**
     * start
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        
        // Get the date 5 days ago from today
        Id HeaderRecTypID = Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName().get('Header').getRecordTypeId();
        Id InstallationRecTypID = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName().get('Installation').getRecordTypeId();
        Id TrainingRecTypID = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName().get('Training').getRecordTypeId();
        Database.QueryLocator qryLoc;
        String qry = 'SELECT Id, RecordTypeId, Sales_Order_Item__c, Status, NewSO__c, Sales_Order_Item__r.Reject_Reason__c, WorkOrder.recordTypeId  from WorkOrderLineItem '+
            		 ' Where  RecordTypeId =: HeaderRecTypID AND  (WorkOrder.RecordTypeId =: InstallationRecTypID OR WorkOrder.RecordTypeId =: TrainingRecTypID )  AND (Sales_Order_Item__c = NULL OR Sales_Order_Item__r.Reject_Reason__c != NULL)';
            		 
                     
        system.debug('==qry=='+qry);
        qryLoc = Database.getQueryLocator(qry);        
        return qryLoc;
    }
    /**
     * execute
     */
    global void execute(Database.BatchableContext bc, List<WorkOrderLineItem> scope) { 
        List<WorkOrderLineItem> wolisToUpdate = new List<WorkOrderLineItem>();
        
        // Loop through leads in scope and prepare them for deletion
        for (WorkOrderLineItem woli : scope) {
            woli.Status = 'Canceled';
			wolisToUpdate.add(woli);
        }
        
        // Delete the leads
        if (!wolisToUpdate.isEmpty()) {
            update  wolisToUpdate;
        }
    }
    
   
   global void finish(Database.BatchableContext BC) {
           
   }
    
   global void execute(SchedulableContext SC){
        Database.executeBatch(new HeaderWoliCancellationBatch());
   }
}

