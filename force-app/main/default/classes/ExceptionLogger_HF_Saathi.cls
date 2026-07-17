public without sharing class ExceptionLogger_HF_Saathi {

    // Log an actual exception with full stack trace and line number
    public static void log(String className, String methodName, Exception ex) {
        log(className, methodName, ex, null);
    }

    public static void log(String className, String methodName, Exception ex, String referenceId) {
        try {
            Exception_Log__c rec = new Exception_Log__c();
            rec.Class_Name__c     = className;
            rec.Method_Name__c    = methodName;
            rec.Exception_Type__c = ex.getTypeName();
            rec.Line_Number__c    = ex.getLineNumber();
            rec.Error_Message__c  = ex.getMessage();
            rec.Stack_Trace__c    = ex.getStackTraceString();
            rec.Reference_Id__c   = referenceId;
            rec.Occurred_At__c    = Datetime.now();
            insert rec;
        } catch (Exception logEx) {
            // Silent — logger must never surface to the caller
        }
    }

    // Log a business-logic issue without an exception object
    public static void log(String className, String methodName, String message) {
        log(className, methodName, message, null);
    }

    public static void log(String className, String methodName, String message, String referenceId) {
        try {
            Exception_Log__c rec = new Exception_Log__c();
            rec.Class_Name__c     = className;
            rec.Method_Name__c    = methodName;
            rec.Exception_Type__c = 'BusinessLogicError';
            rec.Error_Message__c  = message;
            rec.Reference_Id__c   = referenceId;
            rec.Occurred_At__c    = Datetime.now();
            insert rec;
        } catch (Exception logEx) {
            // Silent
        }
    }
}