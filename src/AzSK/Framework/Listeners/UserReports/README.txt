*** This README file describes how to interpret the different files created when AzSK cmdlets are executed ***

Each AzSK cmdlet writes output to a folder whose location is determined as below:

--------------------------------------------------------------
AzSK-Root-Output-Folder = %LocalAppData%\Microsoft\AzSKLogs 
	E.g., "C:\Users\<userName>\AppData\Local\Microsoft\AzSKLogs"

--------------------------------------------------------------
Sub-Folder = Sub_<Subscription Name>\<Timestamp>_<CommandAbbreviation> 
	E.g., "Sub_[yourSubscriptionName]\20170321_183800_GSS)"


--------------------------------------------------------------
Thus, the full path to an output folder for a specific cmdlet might look like: 
	E.g., "C:\Users\userName\AppData\Local\Microsoft\AzSKLogs\Sub_[yourSubscriptionName]\20170321_183800_GSS"

By default, cmdlets open this folder upon completion of the cmdlet (we assume you'd be interested in examining the control evaluation status, etc.)


==============================================================
The contents of the output folder are organized as under:

 	\SecurityReport-<timestamp>.csv			
	[This is the summary CSV file listing all applicable controls and their evaluation status. This file will be generated only for scan cmdlets like Get-AzSKAzureServicesSecurityStatus, Get-AzSKSubscriptionSecurityStatus etc. The CSV contains many useful columns such as recommendation, attestation details, a pointer to the control evaluation LOG file for the resource, etc.]


 	\AttestationReport-<timestamp>.csv			
	[This is the summary CSV file listing all applicable controls and their attestation details. This file will be generated only for the cmdlet Get-AzSKInfo -SubscriptionId <SubscriptionId> -InfoType AttestationInfo.]


  	\<Resource_Group_or_Subscription_Name_Folder>	
	[This folder corresponds to the resource-group or subscription that was evaluated. If multiple resource groups were scanned, there is one folder for each resource group.]

		\<resourceType>.LOG					
		[This is the detailed/raw output log of controls evaluated for a given resource type within a resource group.]


	\Etc
	[This contains some other logs capturing the runtime context of the command.]

		\PowerShellOutput.LOG				
		[This is the raw PS console output captured in a file.]
		
		\EnvironmentDetails.LOG				
		[This is the log file containing environment data of current PowerShell session.]
		\SecurityEvaluationData.json		
		[This is the detailed security data for each control that was evaluated. This file will be generated only for SVT cmdlets like Get-AzSKAzureServicesSecurityStatus, Get-AzSKSubscriptionSecurityStatus etc.]


	\FixControlScripts						
	[This folder contains scripts to fix failing controls where fix-script is supported. The folder is generated only when the 'GenerateFixScript' switch is passed and one or more failed controls support automated fixing.] 

		\README.txt							
		[This is help file describes the 'FixControlScripts' folder.]


--------------------------------------------------------------
You can use these outputs as follows - 
  1) The SecurityReport.CSV file provides a gist of the control evaluation results. Investigate those that say 'Verify' or 'Failed'.
  2) For 'Failed' or 'Verify' controls, look in the <resourceType>.LOG file (search for the text 'Failed' or by control-id) to help you understand why the control has failed.
  3) For 'Verify' controls, you will also find the SecurityEvaluationData.JSON file in the \Etc sub-folder handy. 
  4) For some controls, you can also use the 'Recommendation' field in the control output to quickly get to the PS command to address the issue.
  5) Make changes as needed to the subscription/resource configs based on steps 2, 3 and 4. 
  6) Rerun the cmdlet and verify that the controls you just attempted fixes for are passing now.
