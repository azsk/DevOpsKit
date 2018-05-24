# Contributing to DevOps Kit 

Welcome, and thank you for showing interest in contributing to the Secure DevOps Kit for Azure! To get an overview of the Secure DevOps Kit for Azure (a.k.a., DevOps Kit or 'AzSK'), refer to our [doc repository]( https://github.com/azsk/DevOpsKit-docs.). The goal of this document is to provide a high level overview of how you can contribute to the DevOps Kit.

## Table of Contents
 * [Code of Conduct](#code-of-conduct)
 * [Contribution areas](#contribution-areas)
 * [Reporting issues](#reporting-issues)
 * [Contributing to code](#contributing-to-code)
 	* [Understanding the structure of the DevOps Kit](understanding-the-structure-of-the-devops-kit)
 	* [Enhance controls for supported resources](#enhance-controls-for-supported-resources)
	   * [Update existing controls](#update-existing-controls)
	   * [Add new controls for existing supported resources](#add-new-controls-for-existing-supported-resources)   
 * [Submitting changes](#submitting-changes)
 * [Suggestions](#suggestions)
	
	
### Code of Conduct
Code of Conduct is necessary so as to encourage a healthy environment for end users to contribute to the project. Our Code of Conduct can be found [here](https://github.com/azsk/DevOpsKit/blob/master/CODE_OF_CONDUCT.md).

### Contribution areas
You can contribute to the DevOps Kit project through blogs, documentation, or code. 
* Blogs and Documents: You can contribute to blogs or documents to enhance current documentation by creating a pull request to our [doc repository](https://github.com/azsk/DevOpsKit-docs).
* Contribute to code: To contribute to code you can refer [Contributing to code](#contributing-to-code) to know more about how and where to contribute. 


### Reporting issues
Have you identified a reproducible bug in the DevOps Kit? We want to hear about it! Here's how you can make reporting your issue as effective as possible.

#### Look for an existing issue
Before creating a new issue, search in [issues](https://github.com/azsk/DevOpsKit/issues) to see if the issue has already been created.
If you find that the issue already exists, make relevant comments and mention if something is still missing there.

#### Write good bug reports
Writing a good issue/bug report will help others (including reviewers) get a better understanding of the issue. For example, giving an appropriate  issue title may help others facing a similar issue to find and comment on it. We have created an issue template to make sure that important pieces of information are not missed while creating an issue.

##### Best practices
* File a single issue per problem. Do not add multiple bugs under the same issue as bugs may look similar but their root causes might be different.
* Always specify the AzSK version for which you faced the issue.
* Provide the steps to reproduce the issue like the commands you ran, parameters you passed when you encountered this issue.
* Mention the modules that were present in the powershell session while you ran the command.
* Specify the expected vs actual behavior.


### Contributing to code
#### Understanding the structure of the DevOps Kit
Before contributing to code, you must understand the structure of the DevOps Kit. At its core, the PowerShell module of the DevOps Kit evaluates security controls for Azure subscriptions and Azure services such as AppService, KeyVault, Storage, etc. For each service, controls are defined using two main parts:

**1. Policy/Configuration:**</br>
It is a json file that has a set of security controls for an Azure service. For each control in a service there is an entry in Policy/Configuration json file with properties like ControlID, Description, Recommendation, Rationale etc. 

You can find the configuration for any Azure service under: "AzSK\Framework\Configurations\SVT\Services\<FeatureName>.Json"          

Now let's understand the various properties defined for controls:
```
{                                                                                                                                                                                                                                   
    "FeatureName": "<Feature Name>",	//  Azure Feature Name                 
    "Reference" : "aka.ms/azsktcp/<FeatureName>",	  //  Reference link to Azure Feature control documentation                   
    "IsManintenanceMode": false,                                                                                                                                                                 
    "Controls": [			// List of controls defined for feature                                                     
     {                                                                                                                                                                                                              
        "ControlID": "Azure_<FeatureName>_<ControlTypeAcronym>_ControlShortName",	// TCP ControlID. Make sure it is unique                                    
        "Id": "FeatureName01",	// Id being used by framework internally                                  
        "Description": "<Control Description here>",                                                                                                                 
        "ControlSeverity": "High",   // Defines the severity of a control. Possible values: Critical, High, Medium and Low                                                                                      
        "Rationale": "<Control Rationale>", // Rationale behind the control                                                    
        "Automated" : "Yes",	// Possible values are: Yes, No                                                      
        "Tags": ["SDL"],		// Tags related to control                                                              
        "Enabled": true,					                                                                                                      
        "Recommendation": "<Recommendation To Fix Control>", // Steps to fix control using PowerShell Script or Azure Portal Options or other manual steps				
        "MethodName": "<ControlMethodName>"		 // Name of method which will be called to evaluate control  
      },												
    ]
  }
```

 The following acronyms are used for control type:
 
 
  |Acronym|Full Name|Example|
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

**2. Core Logic** </br>
Each supported Azure service has core logic defined for evaluating **automated** controls. You can find it under:  
"AzSK\Framework\Core\SVT\Services\<FeatureName>.ps1".

Having understood the basic structure of DevOps Kit source code, you can now go ahead with the contribution.

### Enhance controls for supported resources 
Since Azure services keep on updating with latest security features and automation options, DevOps Kit controls also need to be updated to reflect the securty improvements and additional security checks that might apply towards control validation (or change in control description or recommendation).

 You can enhance controls for supported resources in the following ways:

#### Update existing controls
There are various ways in which you can update an existing control:
  * Update recommendations as per latest options/PowerShell command available. This is as simple as updating Policy/Configuration Json file.
  * Update core logic defined to cover different/missing scenarios for control evaluation or bug fixes. You can navigate to core logic file for that service. The name of method where the core logic is defined for a specific control can be found in the MethodName property of that control in the Policy/Configuration.json file.  
  
#### Add new controls for existing supported resources</br>
  * You can add your own security practices/checks as controls for a particular Azure service. Before adding control to code, you should come up with below basic details:
	1. Control description.
	2. Rationale behind the control.
	3. Recommendation to be followed to fix control.
	4. Level (TCP/Best Practice/Information) and severity (Critical/High/Medium/Low) of the control.
	5. Can control be validated using Azure cmdlet or API? Based on this control can be added as a **manual** or **automated** control.

**Add manual control**</br>
Follow the steps below to add a manual control:</br>
**a.** Open Policy config of Azure service by navigating to path: "AzSK\Framework\Configurations\SVT\Services\<FeatureName>.Json"</br>
**b.** Add an entry under Controls section. See an example below:  
```
{                                                                                                                                                                                                              
   "ControlID": "Azure_<FeatureName>_<ControlTypeAcronym>_ControlShortName",
   "Id": "FeatureName<NextId>",	
   "Description": "<Control Description here>",
   "ControlSeverity": "Critical/High/Medium/Low",
   "Rationale": "<Control Rationale>",                                                                                        
   "Automated" : "No",					                                                      
   "Tags": ["SDL", "Manual", "TCP/Best Practice/Information"],                                                              
   "Enabled": true,					                                       
   "Recommendation": "<Recommendation To Fix Control>", 
}	
```
>  **DONT'S:**
> * Do not change values for fixed variables e.g. FeatureName, ControlID, Id  and MethodName. These values are referenced at different places in the framework.
> * Control Policy is strongly typed schema, new property or renaming of the property can break things.
> * ControlID, Id should not be repeated/duplicated.

**Add automated control**</br>
You may also add controls that can be automated using AzureRm PowerShell or ARM API calls. Before automating a control, make sure you have knowledge about the permissions/access required to validate the control.

Follow the steps below to add an automated control:</br>
**1.** Add control entry in the policy file for the Azure Service that can be found under the path "AzSK\Framework\Configurations\SVT\Services\<FeatureName>.Json".
```
{                                                                                                                                                                                                              
	  "ControlID": "Azure_<FeatureName>_<ControlTypeAcronym>_ControlShortName",
	  "Id": "FeatureName<NextId>",	
	  "Description": "<Control Description here>",
	  "ControlSeverity": "Critical/High/Medium/Low",
	 "Rationale": "<Control Rationale>",                                                                                        
	  "Automated" : "Yes",					                                                      
	  "Tags": ["SDL", "Automated", "TCP/Best Practice/Information"],                                                              
	  "Enabled": true,					                                       
	  "Recommendation": "<Recommendation To Fix Control>", 
	 "MethodName": "<ControlMethodName>"  // The method which will contain control evaluation logic.
}
```
>  **DONT'S:**
> * Do not change values for fixed variables e.g. FeatureName, ControlID, Id  and MethodName. These values are referenced at different places in framework.
> * Control Policy is strongly typed schema, new property or renaming the property can break things.
> * ControlID, Id should not be repeated/duplicated.

**2.**  Add core logic for evaluating the control in the <ControlMethodName> function. 
	
</br>Here is how the function evaluating any given control needs to be structured: 

```PowerShell  
hidden [ControlResult] <ControlMethodName>([ControlResult] $controlResult)
 # ControlMethodName needs to configured in Policy Config against "MethodName" 
   {
		  # SVT implementation goes here 
		  # Update the result of TCP control in object $controlResult
		  $controlResult.VerificationResult = [VerificationResult]::Verify;  # Valid values are - Verify,Failed, NotSupported,
        Error 

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

### Submitting changes
Once you have done the code changes and tested them you can create a pull request. Follow the practices below when creating a pull request: 
* Point to 'External Contribution' branch so that your changes are merged into it after your pull request is accepted. If you point to any other branch, your pull request may not get noticed.
* Make sure you use the pull request template. If you delete or ignore the template, your pull request will not be considered.
	
Basic acceptance criteria for a pull request: 
*  Changes should not impact performance in a negative way.
*  Changes should not break existing code flow.
*  The core team needs to agree with any architectural impact a change may make. Things like new extensions or APIs must be discussed with and agreed upon by the core team.

### Suggestions
You can submit feedback, suggestions or feature requests at <azsksup@microsoft.com>. To make the feedback process more effective, try to include as much information as possible. For example one can add the need, impact and advantages of the feature being requested.  

We appreciate your contributions to the DevOps Kit!
