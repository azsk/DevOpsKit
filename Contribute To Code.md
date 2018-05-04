# Contributing to Code

There are many ways in which you can contribute to the Code project: logging bugs, submitting new feature requests, reporting issues. 
This document gives an overview about contribution areas and contribution guidelines

## Table of Content
* [Prerequisites]()
* [Contribution Guide]()
  * [SVT](#svt)
    * [Enhance controls for supported resources](#enhance-controls-for-supported-resources) 
      * [Update Existing Controls](#update-existing-control)
      * [Add new controls for existing supported resources](#add-new-controls-for-existing-supported-resources)
        * [Add Manual Control](#add-manual-control) 
        * [Add Automated Control](#add-automated-control)
      <!-- TODO * Add new services in AzSK with controls -->		
  * [OMS Views/Queries](#oms-viewsqueries)
    * [Enhance or add OMS Views/Queries](#enhance-or-add-oms-viewsqueries)
    * [Suggesting Useful OMS Queries](#suggesting-useful-oms-queries)
* [Pull Requests](#pull-requests)
* [Suggestions](#suggestions)
* [Discussion Etiquette](#discussion-etiquette)


## Prerequisites
* Visual Studio 
* PowerShell 5.0 or higher.
* AzureRM Version 5.2.0

## Contribution Guide
Following section guides you on how and where you can contribute in code:		

### SVT
Before contributing to code you must understand the structure of tool. Basically we have defined security controls for Azure services like App Service, KeyVault, Storage etc. For each service, AzSK defines controls using two main parts :

**1.Policy/Configuration:**

It is a json file which contains set of controls for service. For each control in a service there is an entry in Policy/Configuration json file having properties like ControlId, Description, Recommendation, Rationale etc. 
You can find the configuration for service under below path
"AzSK\Framework\Configurations\SVT\Services\<FeatureName>.Json"          
Now let's understand the properties defined for controls:
```
{                                                                                                                                                                                                                                   
    "FeatureName": "<Feature Name>",	//  Azure Feature Name                 
    "Reference" : "aka.ms/azsktcp/<FeatureName>",	  //  Reference link to Azure Feature Control documentation                   
    "IsManintenanceMode": false,                                                                                                                                                                 
    "Controls": [			// List of controls defined for feature                                                     
     {                                                                                                                                                                                                              
        "ControlID": "Azure_<FeatureName>_<ControlTypeAcronym>_ControlShortName",	// TCP Control Id. Make sure its unique                                    
        "Id": "FeatureName01",	// Id being used by framework internally                                  
        "Description": "<Control Description here>",                                                                                                                 
        "ControlSeverity": "High",   // Defines the severity of control with values: Critical, High, Medium and Low                                                                                      
        "Rationale":"<Control Rationale>", // Rationale behind the control                                                    
        "Automated" : "Yes",	// Possible values are: Yes, No                                                      
        "Tags":["SDL"],		// Tags related to Control                                                              
        "Enabled": true,					                                                                                                      
        "Recommendation":"<Recommendation To Fix Control>", // Steps to fix control using PowerShell Script or Portal Options or other manual steps				
        "MethodName": "<ControlMethodName>"		 // Name of method which will be called to evaluate control  
      },												
    ]
  }
```

 Following Acronym are used for control type:
 
 
  |Acronym|Full Name|Examples|
  |---|---|---|
  |AuthN|Authentication|Azure_Storage_AuthN_Dont_Allow_Anonymous|
  |AuthZ|Authorization|Azure_Batch_AuthZ_Grant_Min_RBAC_Access|
  |ACL|access control list|Azure_ODG_ACL_DataSource_Privacy|
  |DP|Data Protection|Azure_Storage_DP_Encrypt_At_Rest_Blob|
  |NetSec|Network Security|Azure_ERvNet_NetSec_Dont_Use_PublicIPs|
  |BCDR|Backup and disaster recovery|Azure_AppService_BCDR_Use_AlwaysOn|
  |Audit|Auditing and logging|Azure_Storage_Audit_AuthN_Requests|
  |Availability|Availability|Azure_ServiceFabric_Availability_Replica_Stateful_Size_Set_Min_3|
  |Config|Configuration|Azure_VirtualMachine_Config_OS_Auto_Update|
  |SI|System Integrity|Azure_CloudService_SI_Validate_InternalEndpoints|
  |Deploy|Deployment|Azure_AppService_Deploy_Dont_Use_Publish_Profiles|  

**2. Core Logic** 

Each supported Azure Service will be having core logic defined for evaluating automated controls. You can find it under path 
"AzSK\Framework\Core\SVT\Services\<FeatureName>.ps1".  Each automated control will have MethodName, where in you can see the logic defined for control.

Having understanding of the control working will accelerate your contribution.The Following are the different areas where you contribute to AzSK.

#### Enhance controls for supported resources 
Since Azure services keep on evolving with latest security features and automation options, AzSK controls needs to be upgraded with latest bits for control validation or recommendation or change in control description.
Following are the ways you can enhance controls for supported resources:

##### Update existing control
There are various ways in which can update an existing control:
  * Update recommendations as per latest options/PowerShell command available: This is as simple as updating Control Json file. (Refer Policy/Configuration )
  * Update core logic defined to cover different/missing scenarios for control evaluation or bug fixes: You can navigate to core logic for specific control by finding the ControlId in Policy/Configuration.json file and then in the MethodName property you will be able to find the method that contains the logic to evaluate that particular control.
  
##### Add new controls for existing supported resources</br>
  * You can add your security practices as control for a particular Azure Service. Before adding control to AzSK, you should come up with below basic details:
	1. Control Description 
	2. Rationale behind the control
	3. Recommendation to be followed  to fix control
	4. Define level(TCP/Best Practice/Information) and severity(Critical/High/Medium/Low) of the control
	5. Can control be validated using Azure cmdlet or API. Based on this control can be added as a Manual or Automated control.

The control you are thinking to add may be Manual or Automated control, based upon that you can go through the below given description to add Manual or Automated control.

###### Add Manual Control
Adding manual control is as easy as updating Policy Json. Follow below steps to add manual control</br>
**a.** Open Policy config of Azure Service by navigating to path: "AzSK\Framework\Configurations\SVT\Services\<FeatureName>.Json"</vr>
**b.** Add entry under Controls section. Sample shown below 
```
{                                                                                                                                                                                                              
   "ControlID": "Azure_<FeatureName>_<ControlTypeAcronym>_ControlShortName",
   "Id": "FeatureName<NextId>",	
   "Description": "<Control Description here>",
   "ControlSeverity": "Critical/High/Medium/Low",
   "Rationale":"<Control Rationale>",                                                                                        
   "Automated" : "No",					                                                      
   "Tags":["SDL", "Manual", "TCP/Best Practice/Information"],                                                              
   "Enabled": true,					                                       
   "Recommendation":"<Recommendation To Fix Control>", 
}	
```
>  **DONT'S:**
> * Do not change values for fixed variables e.g.. FeatureName, ControlID, Id  and MethodaName. These values are referenced at different places in framework.
> * Control Policy is strongly typed schema, new property or renaming of the property is not allowed
> * ControlId, Id should not be repeated/duplicated

###### Add Automated Control
If you have analyzed that control can be automated using PowerShell with help of Azure cmdlet or API, you can follow steps defined below to add automated control. Before automating control make sure you have below data available
1. Permissions(Reader/Contributor/Owner/Graph API access etc.) required to validate the control

Follow below steps to add automated control</br>
**1.** Add Control entry in Azure Service Policy config under the path "AzSK\Framework\Configurations\SVT\Services\<FeatureName>.Json"
```
{                                                                                                                                                                                                              
	  "ControlID": "Azure_<FeatureName>_<ControlTypeAcronym>_ControlShortName",
	  "Id": "FeatureName<NextId>",	
	  "Description": "<Control Description here>",
	  "ControlSeverity": "Critical/High/Medium/Low",
	 "Rationale":"<Control Rationale>",                                                                                        
	  "Automated" : "Yes",					                                                      
	  "Tags":["SDL", "Automated", "TCP/Best Practice/Information"],                                                              
	  "Enabled": true,					                                       
	  "Recommendation":"<Recommendation To Fix Control>", 
	 "MethodName": "<ControlMethodName>"  // The method which will contain control evaluation logic.
}
```
>  **DONT'S:**
> * Do not change values for fixed variables e.g.. FeatureName, ControlID, Id  and MethodaName. These values are referenced at different places in framework.
> * Control Policy is strongly typed schema, new property or renaming of the property is not allowed
> * ControlId, Id should not be repeated/duplicated


**2.**  Add Core logic for evaluating control 
</br>Below is the stucture of a function defined for an SVT TCP. 

```powershell  
hidden [ControlResult] <ControlMethodName>([ControlResult] $controlResult)
 # ControlMethodName needs to configured in Policy Config against "MethodName 
   {
		  # SVT implementation goes here 
		  # Update the result of TCP control in object $controlResult
		  $controlResult.VerificationResult = [VerificationResult]::Verify;	# Valid values are - Passed, Verify, Failed, Unknown 

		  # Add any number of messages and data objects using function $controlResult.AddMessage(). 
		  #	Refer file 'AzSDK\Framework\Models\AzSdkEvent.ps1' for definition of 'MessageData' class and its possible contractors. 
		  #	Refer file 'AzSDK\Framework\Models\SVTEvent.ps1' for definition of 'ControlResult' class and its possible overloads for 'AddMessage' function.
		  #	Some of the overloads are listed below:
		  $controlResult.AddMessage("Message text here");
		  $controlResult.AddMessage([MessageData]::new("Message text here", $<data object containing values to be logged in detailed logs>)); 
		  $controlResult.AddMessage([VerificationResult]::Passed, "Message text here", $dataObject));
		  $controlResult.AddMessage([VerificationResult]::Failed, "Message text here"));
		  $controlResult.AddMessage([VerificationResult]::Verify, [MessageData]::new("Message text here" , $dataObject));
		
		  return $controlResult; 
	  }
```
## OMS Views/Queries 
To understand in details about the OMS Views generated by AzSK to monitor Security Health of a subscription, you can refer [Alerting and Monitoring](https://github.com/azsk/DevOpsKit-docs/blob/master/05-Alerting-and-Monitoring/Readme.md), we have a template to provide AzSK health view which provides visualization of security health at various levels(namely subscription,	resource group and resources). You can contribute by adding a a blade to the view,modifying the existing queries,or suggesting useful queries.
To contribute to the existing OMS view you can modify OMS view file "AZSK.AM.OMS.GenericView.V2" which is template to create AzSK OMS View.
### Enhance or add OMS Views/Queries
You can add a blade by adding entry in "Dashboard" array in the json file for the blade you want to create.There is another way to create a blade for an OMS View </br>
    1. Open the AzSK OMS View on OMS Portal </br>
    2. Click on the edit option then select the type of dashboard view you want to add, or edit the query, color scheme etc. </br>
    3. Save the view and then download the template of edited view, copy the blade entry from the downloaded template and add it to the "Dashboard" array in "AZSK.AM.OMS.GenericView.V2" file. </br>

### Suggesting Useful OMS Queries 
If you have created a query that you want to share with others that can help them to monitor the health status of their subscription or resources, you can create a pull request submitting the suggested query and that would be added to the [documentation repository](https://github.com/azsk/DevOpsKit-docs/blob/master/05-Alerting-and-Monitoring/OMSQueries.md)

## Pull Requests
All pull request should be raised to <> branch.Make sure that you donot delete the Pull Request Template when creating a request.
Before we can accept a pull request from you, we would be reviewing the request and based upon the impact of the request we would be closing request in the time specified. For more details you can refer issue tracking and SLA.
To enable us to quickly review and accept your pull requests, always create one pull request per issue and link the issue in the pull request. Never merge multiple requests in one unless they have the same root cause. Pull requests should contain tests whenever possible.

## Suggestions
We're also interested in your feedback for the future of tool. You can submit a suggestion or feature request. To make this process more effective, we're asking that these include more information to help define them more clearly. For example one can add the need, impact and advantages or the feature being requeseted.  

## Discussion Etiquette
Try keeping the discussion clear and transparent, focused around issues, feedback or suggestion. Be considerate to others and try to be courteous and professional at all times. For more details on Code of Conduct you can refer:
