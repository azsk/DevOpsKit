# Contributing to DevOps Kit 

Welcome, and thank you for showing interest in contributing to Secure DevOps Kit! To get an overview of Secure DevOps Kit you can refer to our [documentation repository]( https://github.com/azsk/DevOpsKit-docs.). The goal of this document is to provide a high-level overview of how you can get involved in contribution.

## Table of Content
 * [Code of Conduct](/CONTRIBUTING.md#code-of-conduct)
 * [Contribution Area](/CONTRIBUTING.md#asking-questions)
 * [Reporting Issues](/CONTRIBUTING.md#submitting-changes)
 * [Contributing to code](/CONTRIBUTING.md#contributing-to-code)
 	* [Understanding the structure of Secure DevOps Kit](#understanding-the-structure-of-secure-devops-kit)
 	* [Enhance controls for supported resources](#enhance-controls-for-supported-resources)
	   * [Update existing control](#update-existing-control)
	   * [Add new controls for existing supported resources](#add-new-controls-for-existing-supported-resources)   
 * [Submitting Changes](/CONTRIBUTING.md#submitting-changes)
 * [Suggestions](/CONTRIBUTING.md#suggestions)
	
	
### Code of Conduct
Code of Conduct is necessary so as to encourage a healthy environment for end users to contribute to the project. Thus members and contributors must adhere to code of conduct while reporting any issue, engaging in a discussion or commenting on issues or involving in whatever means.

### Contribution Area
You can contribute to blogs, documentation or code of Secure DevOps Kit. 
* Blogs and Documents: You can contribute to blogs or documents to enhance current documentation by creating a pull request to our [documentation repository](https://github.com/azsk/DevOpsKit-docs).
* Contribute to code:To contribute to code you can refer [Contributing to code](#contributing-to-code) to know more about how and where to contribute. 


### Reporting Issues
Have you identified a reproducible bug in Secure DevOps Kit? We want to hear about it! Here's how you can make reporting your issue as effective as possible.
#### Look for an existing issue
Before creating a new issue, search in [issues](https://github.com/azsk/DevOpsKit/issues) to see if the issue already been created.
Be sure to scan through the [most popular]() feature requests.
If you find your issue already exists, make relevant comments and mention if something is still missing there.
#### Write good bug reports
Writing a good issue will help others including reviewers to have better understanding of the issue, for example giving an appropriate  issue title may help others facing similar issue to find and comment on it. We have created an [issue template] to make sure that important piece of information are not missed while creating an issue:
##### Best practices
* File a single issue per problem. Do not add multiple bugs under same issue as the bugs may look similar but their root cause might be different
* Always try to specify the AzSK version for which you faced the issue.
* Steps to reproduce the issue like the commands you ran, parameters you passed when you encountered this issue
* Modules that were present in the powershell session while you ran the command
* Output


### Contributing to code
#### Understanding the structure of Secure DevOps Kit
Before contributing to code you must understand the structure of Secure DevOps Kit. It evaluates security controls for Azure services like App Service, KeyVault, Storage etc. For each service, Secure DevOps Kit defines controls using two main parts:
**1. Policy/Configuration:**</br>
It is a json file that has a set of security controls for an Azure service. For each control in a service there is an entry in Policy/Configuration json file having properties like ControlId, Description, Recommendation, Rationale etc. 
You can find the configuration for service under :"AzSK\Framework\Configurations\SVT\Services\<FeatureName>.Json"          
Now let's understand the various properties defined for controls:
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

 Following acronym are used for control type:
 
 
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

**2. Core Logic** </br>
Each supported Azure service has core logic defined for evaluating **automated controls**. You can find it under path 
"AzSK\Framework\Core\SVT\Services\<FeatureName>.ps1".

Having understood the basic structure of Secure DevOps Kit code, you can now go ahead with the contribution.

### Enhance controls for supported resources 
Since Azure services keep on updating with latest security features and automation options, therefore Secure DevOps Kit controls need to be upgraded with latest bits for control validation or recommendation or change in control description.
Following are the ways you can enhance controls for supported resources

#### Update existing control
There are various ways in which you can update an existing control:
  * Update recommendations as per latest options/PowerShell command available: This is as simple as updating Policy/Configuration Json file. (Refer Policy/Configuration )
  * Update core logic defined to cover different/missing scenarios for control evaluation or bug fixes: You can navigate to core logic for specific control by finding the ControlId in Policy/Configuration.json file and then in the MethodName property you will be able to find the method that contains the logic to evaluate that particular control.  
  
#### Add new controls for existing supported resources</br>
  * You can add your security practices as control for a particular Azure Service. Before adding control to code, you should come up with below basic details:
	1. Control description 
	2. Rationale behind the control
	3. Recommendation to be followed  to fix control
	4. Define level(TCP/Best Practice/Information) and severity(Critical/High/Medium/Low) of the control
	5. Can control be validated using Azure cmdlet or API. Based on this control can be added as a **Manual or Automated** control. The control you are thinking to add may be Manual or Automated control, based upon that you can go through the below given description to add Manual or Automated control.

**Add manual control**</br>
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
> * Do not change values for fixed variables e.g. FeatureName, ControlID, Id  and MethodaName. These values are referenced at different places in framework.
> * Control Policy is strongly typed schema, new property or renaming of the property is not allowed
> * ControlId, Id should not be repeated/duplicated

**Add automated control**</br>
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
> * Do not change values for fixed variables e.g. FeatureName, ControlID, Id  and MethodaName. These values are referenced at different places in framework.
> * Control Policy is strongly typed schema, new property or renaming of the property is not allowed
> * ControlId, Id should not be repeated/duplicated

**2.**  Add core logic for evaluating control 
</br>Below is the stucture of a function defined for an SVT TCP. 

```powershell  
hidden [ControlResult] <ControlMethodName>([ControlResult] $controlResult)
 # ControlMethodName needs to configured in Policy Config against "MethodName 
   {
		  # SVT implementation goes here 
		  # Update the result of TCP control in object $controlResult
		  $controlResult.VerificationResult = [VerificationResult]::Verify;  # Valid values are - Passed, Verify, Failed, Unknown 

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
Once you have done the code changes, tested them and want to submit your changes or bug fix you can create a pull request. Follow the below steps while creating a pull request for reviewers to have better understanding of your request:
* Point to 'External Contribution' branch so that your changes are merged into it after your pull request is accepted. If you point to any other branch, your pull request might not be considered.
* The pull request template is placed with the intent to be followed while creating a pull request and if you delete or ignore the template, your pull request might not be considered.
	
Below mentioned are the most basic acceptance criteria for a pull request: 
*  The code changes should not impacts performance in negative way.
*  The code changes should not break existing code flow.
*  The team needs to agree with any architectural impact a change may make. Things like new extension APIs must be discussed with and agreed upon by the core team.

### Suggestions
We're also interested in your feedback for the future of tool. You can submit a suggestion or feature request at <azsdksupext@microsoft.com>. To make this process more effective, try to include more information to describe the suggestion more clearly. For example one can add the need, impact and advantages or the feature being requeseted.  

### Thank You !
Your contributions are really appreciated.
