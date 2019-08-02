Set-StrictMode -Version Latest 
class LogicAppControl
{
	[string] $Name = ""
	[string] $Automated = ""
	[string] $MethodName = ""
	[string] $Remarks = ""
}
class LogicAppApprovedConnector
{
	[string] $connectorName = ""
	[LogicAppControl[]] $ApplicableControls = @()
	[LogicAppControl[]] $NotApplicableControls = @()
	
}
class LogicAppNotApprovedConnector
{
	[string] $connectorName = ""
	[string] $Remarks = ""
	
}
class LogicAppConnectorsMetadata
{
	[LogicAppApprovedConnector[]] $ApprovedConnectors = @()
	[LogicAppNotApprovedConnector[]] $notApprovedConnectors = @()	
}

class LogicApps: AzSVTBase
{   
    hidden [PSObject] $ResourceObject;
	hidden [LogicAppConnectorsMetadata] $LogicAppConnectorsMetadata

    LogicApps([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
		$this.LogicAppConnectorsMetadata = [LogicAppConnectorsMetadata] ($this.LoadServerConfigFile("LogicApps.Connectors.json"));
		
		if(Get-Member -InputObject $this.ResourceObject.Properties.parameters -Name '$connections' -MemberType Properties)
		{
			$apiConnections = $this.ResourceObject.Properties.parameters.'$connections'.value
			if($null -ne $apiConnections)
			{
				$apiConnections | Get-Member -MemberType *Property | ForEach-Object{  
					try
					{
						$apiConId = ($apiConnections.($_.name) | Select-Object connectionId).connectionId
						$childSvtObject = $this.CreateSVTResource($apiConId, $svtResource.ResourceGroupName, $svtResource.ResourceName + "/" + $_.name, "Microsoft.Web/connections", $svtResource.Location, "APIConnection")
						$this.ChildSvtObjects += New-Object -TypeName $($childSvtObject.ResourceTypeMapping.ClassName) -ArgumentList $this.SubscriptionContext.SubscriptionId, $childSvtObject
					}
					catch
					{
						#Consuming the exception intentionally to prevent adding deleted connections
					}
				}
			}
		}

		$Definition=$this.ResourceObject.Properties.definition
		if($null -ne $Definition.Actions -and -not[string]::IsNullOrEmpty($this.ResourceObject.Properties.definition.actions))
		{
			$this.ChildResourceNames = @();
			$Definition.Actions | Get-Member -MemberType *Property | ForEach-Object{ 
				$Name=$_.name
				if($Definition.Actions.$Name.type -ne 'ApiConnection')	
				{				
					$newResourceId = $svtResource.ResourceId.replace($svtResource.ResourceName,$_.name).replace("Microsoft.Logic/workflows/","Microsoft.Web/connections/custom/")
					$childSvtObject = $this.CreateSVTResource($newResourceId, $svtResource.ResourceGroupName, $svtResource.ResourceName + "/" + $_.name, "Microsoft.Web/connections", $svtResource.Location, "APIConnection")
					$this.ChildResourceNames += $svtResource.ResourceName + "/" + $_.name;
					$this.ChildSvtObjects += New-Object -TypeName $($childSvtObject.ResourceTypeMapping.ClassName) -ArgumentList $this.SubscriptionContext.SubscriptionId, $childSvtObject
				}
			}
		}

		#if($null -ne $Definition.triggers -and -not[string]::IsNullOrEmpty($this.ResourceObject.Properties.definition.triggers))
		#{
		#	$Definition.Triggers | Get-Member -MemberType *Property | ForEach-Object{ 
		#		$Name=$_.name
		#		if($Definition.Triggers.$Name.type -ne 'ApiConnection')	
		#		{						
		#			$newResourceId = $svtResource.ResourceId.replace($svtResource.ResourceName,$_.name).replace("Microsoft.Logic/workflows/","Microsoft.Web/connections/custom/")
		#			$childSvtObject = $this.CreateSVTResource($newResourceId, $svtResource.ResourceGroupName, $svtResource.ResourceName + "/" + $_.name, "Microsoft.Web/connections", $svtResource.Location, "APIConnection")
		#			$this.ChildSvtObjects += New-Object -TypeName $($childSvtObject.ResourceTypeMapping.ClassName) -ArgumentList $this.SubscriptionContext.SubscriptionId, $childSvtObject
		#		}
		#	}
		#}
    }

    hidden [PSObject] GetResourceObject()
    {
        if (-not $this.ResourceObject) {
            $this.ResourceObject =  Get-AzResource -Name $this.ResourceContext.ResourceName `
			-ResourceGroupName $this.ResourceContext.ResourceGroupName `
			-ResourceType $this.ResourceContext.ResourceType
            if(-not $this.ResourceObject)
            {
                throw ([SuppressedException]::new(("Resource '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
            }
			
        }
        return $this.ResourceObject;
    }

	hidden [ControlResult[]] CheckConnectorsAADAuth([ControlResult] $controlResult)
    {
		[ControlResult[]] $controlResultList = @()
		[PSObject[]] $Connectors = @()
		if(Get-Member -InputObject $this.ResourceObject.Properties.parameters -Name '$connections' -MemberType Properties)
		{
			$apiConnections = $this.ResourceObject.Properties.parameters.'$connections'.value
			if($null -ne $apiConnections)
			{
				$apiConnections | Get-Member -MemberType *Property | ForEach-Object{  
					try
					{
						$apiConId = ($apiConnections.($_.name) | Select-Object connectionId).connectionId     
						$apiConObj = Get-AzResource -ResourceId $apiConId
						$apiName=$apiConObj.Properties.Api.Name           				
			
						$Connector = New-Object PSObject
						Add-Member -InputObject $Connector -MemberType NoteProperty -Name ConnectorName -Value $apiName   
						Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorType -Value $apiName
						Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorObj -Value $null
						$Connectors+=$Connector
					}
					catch
					{
						#Consuming the exception intentionally to prevent adding deleted connections
					}
				}
			}
		}
		$Definition=$this.ResourceObject.Properties.definition
		if($null -ne $Definition.Actions -and -not[string]::IsNullOrEmpty($this.ResourceObject.Properties.definition.actions))
		{
			$Definition.Actions | Get-Member -MemberType *Property | ForEach-Object{ 
				$Name=$_.name		
				if($Definition.Actions.$Name.type -ne 'ApiConnection')	
				{				
					$Connector = New-Object PSObject
					Add-Member -InputObject $Connector -MemberType NoteProperty -Name ConnectorName -Value $Name
					Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorType -Value $Definition.Actions.$Name.type
					Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorObj -Value $Definition.Actions.$Name
					$Connectors+=$Connector
				}
			}
		}
		if($null -ne $Definition.triggers -and -not[string]::IsNullOrEmpty($this.ResourceObject.Properties.definition.triggers))
		{
			$Definition.Triggers | Get-Member -MemberType *Property | ForEach-Object{ 
				$Name=$_.name	
				if($Definition.Triggers.$Name.type -ne 'ApiConnection')	
				{						
					$Connector = New-Object PSObject
					Add-Member -InputObject $Connector -MemberType NoteProperty -Name ConnectorName -Value $Name
					Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorType -Value $Definition.Triggers.$Name.type
					Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorObj -Value $Definition.Triggers.$Name
					$Connectors+=$Connector
				}
			}
		}
		if($Connectors.Count -gt 0)
		{
			$Result = $this.GetConnectorsStatus($Connectors , "AAD", $controlResult)
			if($null -ne $Result)
			{
				$controlResultList += $Result
			}
		}
		else
		{
			$controlResult.AddMessage([VerificationResult]::Passed,"Logic app workflow is empty. No connectors found.")
			$controlResultList += $controlResult
		}
		return $controlResultList		
    }
	hidden [ControlResult[]] CheckConnectorsEncryptionInTransit([ControlResult] $controlResult)
    {
		[ControlResult[]] $controlResultList = @()
		[PSObject[]] $Connectors = @()
		if(Get-Member -InputObject $this.ResourceObject.Properties.parameters -Name '$connections' -MemberType Properties)
		{
			$apiConnections = $this.ResourceObject.Properties.parameters.'$connections'.value
			if($null -ne $apiConnections)
			{
				$apiConnections | Get-Member -MemberType *Property | ForEach-Object{  
					try
					{
						$apiConId = ($apiConnections.($_.name) | Select-Object connectionId).connectionId     
						$apiConObj = Get-AzResource -ResourceId $apiConId
						$apiName=$apiConObj.Properties.Api.Name           				
			
						$Connector = New-Object PSObject
						Add-Member -InputObject $Connector -MemberType NoteProperty -Name ConnectorName -Value $apiName   
						Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorType -Value $apiName
						Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorObj -Value $null
						$Connectors+=$Connector
					}
					catch
					{
						#Consuming the exception intentionally to prevent adding deleted connections	
					}
				}
			}
		}
		$Definition=$this.ResourceObject.Properties.definition
		if($null -ne $Definition.Actions -and -not[string]::IsNullOrEmpty($this.ResourceObject.Properties.definition.actions))
		{
			$Definition.Actions | Get-Member -MemberType *Property | ForEach-Object{ 
				$Name=$_.name		
				if($Definition.Actions.$Name.type -ne 'ApiConnection')	
				{				
					$Connector = New-Object PSObject
					Add-Member -InputObject $Connector -MemberType NoteProperty -Name ConnectorName -Value $Name
					Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorType -Value $Definition.Actions.$Name.type
					Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorObj -Value $Definition.Actions.$Name
					$Connectors+=$Connector
				}
			}
		}
		if($null -ne $Definition.triggers -and -not[string]::IsNullOrEmpty($this.ResourceObject.Properties.definition.triggers))
		{
			$Definition.Triggers | Get-Member -MemberType *Property | ForEach-Object{ 
				$Name=$_.name	
				if($Definition.Triggers.$Name.type -ne 'ApiConnection')	
				{						
					$Connector = New-Object PSObject
					Add-Member -InputObject $Connector -MemberType NoteProperty -Name ConnectorName -Value $Name
					Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorType -Value $Definition.Triggers.$Name.type
					Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorObj -Value $Definition.Triggers.$Name
					$Connectors+=$Connector
				}
			}
		}
		if($Connectors.Count -gt 0)
		{
			$Result = $this.GetConnectorsStatus($Connectors , "EncryptionTransit", $controlResult)
			if($null -ne $Result)
			{
				$controlResultList += $Result				
			}
		}
		else
		{
		    $controlResult.AddMessage([VerificationResult]::Passed,"Logic app workflow is empty. No connectors found.")
			$controlResultList += $controlResult
		}
	   return $controlResultList	
    }

	hidden [ControlResult] CheckConnectorsSecretsHandling([ControlResult] $controlResult)
    {			
		$complianceStatus = [VerificationResult]::Manual
		$userMsg = [string]::Empty
		$IsFailed = $false
		$Definition=$this.ResourceObject.Properties.definition
		$NonCompliantConnectors = @()
		if($null -ne $Definition.Actions -and -not[string]::IsNullOrEmpty($this.ResourceObject.Properties.definition.actions))
		{
			$Definition.Actions | Get-Member -MemberType *Property |         
			ForEach-Object{ 
					$connectorName=$_.name				
					$Connector = $Definition.Actions.$connectorName
					if($Connector.type -eq 'http')
					{
						 $ConnectorResultObject = $this.CheckSecretsHandlingForHttp($Connector)
						 if($ConnectorResultObject.ComplianceStatus -eq [VerificationResult]::Failed)
						 {
							$IsFailed = $true
							$currentStateObject = "" | Select-Object "ConnectorName","ConnectorType","AuthenticationType"
							$currentStateObject.ConnectorName = $connectorName
							$currentStateObject.ConnectorType = $Connector.type
							$currentStateObject.AuthenticationType = $ConnectorResultObject.AuthenticationType
							$NonCompliantConnectors += $currentStateObject
							$userMsg += "Connector - " + $connectorName + "`r`nType - " + $Connector.type `
										+"`r`nSecret(s) are given as plain text in Code View, must use 'SecureString' parameter"
						 }	
					}			
			}
		}
		
		if($null -ne $Definition.triggers -and -not[string]::IsNullOrEmpty($this.ResourceObject.Properties.definition.triggers))
		{
			$Definition.Triggers | Get-Member -MemberType *Property |         
			ForEach-Object{ 
					$connectorName=$_.name				
					$Connector = $Definition.Triggers.$connectorName
					if($Connector.type -eq 'http')
					{						
						 $ConnectorResultObject = $this.CheckSecretsHandlingForHttp($Connector)
						 if($ConnectorResultObject.ComplianceStatus -eq [VerificationResult]::Failed)
						 {
							$IsFailed = $true
							$currentStateObject = "" | Select-Object "ConnectorName","ConnectorType","AuthenticationType"
							$currentStateObject.ConnectorName = $connectorName
							$currentStateObject.ConnectorType = $Connector.type
							$currentStateObject.AuthenticationType = $ConnectorResultObject.AuthenticationType
							$NonCompliantConnectors += $currentStateObject
							$userMsg += "Connector - " + $connectorName + "`r`nType - " + $Connector.type `
										+"`r`nSecret(s) are given as plain text in Code View, must use 'SecureString' parameter"
						 }							
					}			
			}
		}
		#No HTTP connector is present. Display generic message for users.
		if($userMsg -eq [string]::Empty)
		{
			$userMsg = "Please verify manually that Logic App code view doesn't contain any secrets/credentials in plain text"			
		}
		if($IsFailed)
		{
		    $controlResult.SetStateData("Connectors which contains secret(s) as plain text in code view:", $NonCompliantConnectors);
			$complianceStatus = [VerificationResult]::Failed
		}
	
		$controlResult.AddMessage($complianceStatus , $userMsg)
		return $controlResult	
    }
	hidden [ControlResult] CheckLogicAppsInSameRG([ControlResult] $controlResult)
    {
        $OtherAppsinSameRG= Get-AzResource -ResourceGroupName $this.ResourceContext.ResourceGroupName -ResourceType $this.ResourceContext.ResourceType | Where-Object{$_.ResourceId -ne $this.ResourceObject.ResourceId }
        
		if($null -ne $OtherAppsinSameRG)
        {
			$controlResult.AddMessage("Below are the Logic Apps present in the same resource group as " + $this.ResourceContext.ResourceName + " - Logic App")
			$controlResult.AddMessage([VerificationResult]::Verify, "Validate that these Logic Apps trust each other",$OtherAppsinSameRG)
			$controlResult.SetStateData("Logic Apps present in same resource group", $OtherAppsinSameRG);
        }
        else
        {
			$controlResult.AddMessage([VerificationResult]::Passed, "No other logic apps found in resource group ["+ $this.ResourceContext.ResourceGroupName +"]")
        } 
		return $controlResult
    }		
	hidden [ControlResult] CheckTriggersAccessControl([ControlResult] $controlResult)
    { 	
		$IsFailed = $False
		$IsAccessConfigSet = ($null -ne (Get-Member -InputObject $this.Resourceobject.Properties -Name accessControl -MemberType Properties)) 
		if($IsAccessConfigSet)
		{
			$IsTriggerRestricted = ($null -ne (Get-Member -InputObject $this.Resourceobject.Properties.accessControl -Name triggers -MemberType Properties))
			
       
			#Check trigger access control
			if($IsTriggerRestricted)
			{
				if($this.ResourceObject.Properties.accessControl.triggers.allowedCallerIpAddresses.Count -eq 0)
				{
					#verify scenario
					$controlResult.AddMessage("Access control for triggers is set to `"Only other Logic Apps`"")               
				}
				else
				{
					$triggerIPRange = $this.ResourceObject.Properties.accessControl.triggers.allowedCallerIpAddresses.addressRange
					if($triggerIPRange -contains $this.ControlSettings.UniversalIPRange)
					{
						#fail if universal IP range found
						$IsFailed = $True
						$controlResult.AddMessage("IP range $($this.ControlSettings.UniversalIPRange) must be removed from triggers IP ranges")
					}
					else
					{
						$controlResult.AddMessage("Please verify below:")
					}
					$controlResult.AddMessage("IP ranges for triggers :",$triggerIPRange)    
					$controlResult.SetStateData("IP ranges for triggers", $triggerIPRange);           
				}
			}
			else
			{
				#fail if no trigger access control found
				$IsFailed = $True
				$controlResult.AddMessage("Access control for triggers is not found")            
			}
		}   
		else
		{
			$IsFailed = $True
			$controlResult.AddMessage("Access control for triggers is not found")
		} 
        if($IsFailed -eq $True)
        {
             $controlResult.VerificationResult =  [VerificationResult]::Failed  
        }
        else
        {
            $controlResult.VerificationResult =  [VerificationResult]::Verify
        }
		return $controlResult  
    }
	hidden [ControlResult] CheckContentsAccessControl([ControlResult] $controlResult)
    { 		   
    	$IsFailed = $False
		$IsAccessConfigSet = ($null -ne (Get-Member -InputObject $this.Resourceobject.Properties -Name accessControl -MemberType Properties))   
		if($IsAccessConfigSet)
		{
			$IsContentRestricted = ($null -ne (Get-Member -InputObject $this.Resourceobject.Properties.accessControl -Name contents -MemberType Properties))
				
			#check content access control
			if($IsContentRestricted)
			{
				$contentIPRange = $this.ResourceObject.Properties.accessControl.contents.allowedCallerIpAddresses.addressRange
				if($contentIPRange -contains $this.ControlSettings.UniversalIPRange)
				{
					#fail if universal IP range assigned
					$IsFailed = $True
					$controlResult.AddMessage("IP range $($this.ControlSettings.UniversalIPRange) must be removed from contents IP ranges")
				}
				else
				{
					$controlResult.AddMessage("Please verify below:")
				}
				$controlResult.AddMessage("IP ranges for contents :", $contentIPRange)  
				$controlResult.SetStateData("IP ranges for contents", $contentIPRange);    
			}
			else
			{
				#fail if content access control not found
				$IsFailed = $True
				$controlResult.AddMessage("Access control for contents is not found")
			}  
		}   
		else
		{
			$IsFailed = $True
			$controlResult.AddMessage("Access control for contents is not found")
		}   
        if($IsFailed -eq $True)
        {
             $controlResult.VerificationResult =  [VerificationResult]::Failed  
        }
        else
        {
            $controlResult.VerificationResult =  [VerificationResult]::Verify
        }
		return $controlResult  
    }

	#internal functions
	
	hidden [boolean] CheckSecretParameter([string] $secretString,[PSObject[]] $parametersList)
	{
		if(!$secretString.Trim().StartsWith("@parameters("))
		{
			return $false
		}
		else
		{
			$temp=($secretString.replace(' ','')).split('(')[1]
			$parametervalue=$temp.split(')')[0].Trim("'")
			$type=$parametersList.$parametervalue.type
			if($type -ne "securestring")
			{return $false}
			else
			{return $true}
		}
	}
	hidden [PSObject] CheckSecretsHandlingForHttp([PSObject] $Connector)
	{	 

	   $ConnectorObject = [PSObject]::new();
	   Add-Member -InputObject $ConnectorObject -Name "ComplianceStatus" -MemberType NoteProperty -Value [VerificationResult]::Manual
	   Add-Member -InputObject $ConnectorObject -Name "AuthenticationType" -MemberType NoteProperty -Value $null
	
		if(Get-Member -inputobject $Connector.inputs -name "authentication" -Membertype Properties)
		{
			$authentication = $Connector.inputs.authentication	
			if([Helpers]::CheckMember($authentication, "Type"))
			{
			    $ConnectorObject.AuthenticationType = $authentication.type
				switch($authentication.type)
				{
					"ActiveDirectoryOAuth" 
					{
						$IsValidSecret=$this.CheckSecretParameter($authentication.secret,$this.ResourceObject.Properties.definition.parameters)
						if($IsValidSecret -ne $true)
						{
						    $ConnectorObject.ComplianceStatus = [VerificationResult]::Failed
						} 					      
					}
					"ClientCertificate"
					{
						$IsValidPw=$this.CheckSecretParameter($authentication.Password,$this.ResourceObject.Properties.definition.parameters)
						if($IsValidPw -ne $true)
						{ 
						    $ConnectorObject.ComplianceStatus = [VerificationResult]::Failed
						}					
					}
					"Basic"
					{
						$IsValidPw=$this.CheckSecretParameter($authentication.Password,$this.ResourceObject.Properties.definition.parameters)
						if($IsValidPw -ne $true)
						{
						    $ConnectorObject.ComplianceStatus = [VerificationResult]::Failed
						}					
					}
					"default"
					{
					    $ConnectorObject.ComplianceStatus = [VerificationResult]::Manual
					}
				 }
			}		
		 }
		return $ConnectorObject
	}
	hidden [ControlResult] CheckAadAuthForHttp([string] $remarks , [ControlResult] $childControlResult , [PSObject]$Connector)
	{   
		$isPassed = $false		
		if(Get-Member -inputobject $Connector.ConnectorObj.inputs -name "authentication" -Membertype Properties)
		{	
			if([Helpers]::CheckMember($Connector.ConnectorObj.inputs.authentication,"type") -and $Connector.ConnectorObj.inputs.authentication.type -eq "ActiveDirectoryOAuth")
			{
				$isPassed = $true
			}
		}	
		if($isPassed)	
		{
			$childControlResult.AddMessage([VerificationResult]::Passed,"AAD Authentication is used in connector - "+ $Connector.ConnectorName)
		}
		else
		{
			$childControlResult.AddMessage([VerificationResult]::Failed, "AAD Authentication is not used in connector - "+ $Connector.ConnectorName)
		}
		return $childControlResult
	}
	hidden [ControlResult] CheckEncryptionTransitForHttp([string] $remarks , [ControlResult] $childControlResult , [PSObject]$Connector)
	{
			$isPassed = $true
			$uriString = $Connector.ConnectorObj.inputs.uri			
			
			if(([system.Uri]$uriString).Scheme -ne 'https')
			{
				$isPassed = $false 
			}
			if($isPassed)	
			{
				$childControlResult.AddMessage([VerificationResult]::Passed,"Connector name : " + $Connector.ConnectorName + "`r`nConnector URI : "+ $uriString)
			}
			else
			{
				$childControlResult.AddMessage([VerificationResult]::Failed, `
												"Must use HTTPS URI for below connector`r`n" `
												+ "Connector name : " + $Connector.ConnectorName + "`r`nConnector URI : "+$uriString)
												
			}
			return $childControlResult
	}
	hidden [ControlResult] CheckEncryptionTransitForWebhook([string] $remarks , [ControlResult] $childControlResult , [PSObject]$Connector)
	{
		$isPassed = $true			
		$subURI = ""
		$unSubURI = ""
		if(([Helpers]::CheckMember($Connector.connectorObj.inputs,"subscribe")) -and ([Helpers]::CheckMember($Connector.connectorObj.inputs.subscribe,"uri")))
		{
			$subURI = $Connector.connectorObj.inputs.subscribe.uri
		}
		
		if(([Helpers]::CheckMember($connector.connectorObj.inputs,"unsubscribe")) -and ([Helpers]::CheckMember($connector.connectorObj.inputs.unsubscribe,"uri")))
		{
			$unSubURI = $connector.connectorObj.inputs.unsubscribe.uri 
		}

		if(($subURI -ne "" -and ([system.Uri]$subURI).Scheme -ne 'https') -or ($unSubURI -ne "" -and ([system.Uri]$unSubURI).Scheme -ne 'https'))
		{
			$isPassed = $false
		} 
		if($isPassed)	
		{
			$childControlResult.AddMessage([VerificationResult]::Passed, "Connector name : " + $Connector.ConnectorName `
																		+ "`r`nWebhook subscribe URI : "+ $subURI`
																		+ "`r`nWebhook unsubscribe URI : "+$unSubURI)
		}
		else
		{
			$childControlResult.AddMessage([VerificationResult]::Failed, "Must use HTTPS URI(s) for below connector`r`n" `
																		+ "Connector name : " + $Connector.ConnectorName `
																		+ "`r`nWebhook subscribe URI : "+ $subURI`
																		+ "`r`nWebhook unsubscribe URI : "+$unSubURI)
		}
		return $childControlResult
	}	
	hidden [ControlResult[]] GetConnectorsStatus([PSObject] $Connectors,[string] $controlName, [ControlResult] $controlResult)
	{
		$controlResultList = @()
		$Connectors | ForEach-Object{ 
				$Connector = $_
				$connectorName=$Connector.ConnectorName				
				$ConnectorObj = $Connector.ConnectorObj
				$connectorType=$Connector.ConnectorType

				[ControlResult] $childControlResult = $this.CreateChildControlResult($connectorName + " ("+$connectorType+" connector)", $controlResult);
 
				if($connectorName -eq "manual")
				{
					$connectorName = $connectorType
				}					
					
				#check if this connector belongs to not approved list
				$notApprovedConnector = $this.LogicAppConnectorsMetadata.NotApprovedConnectors | Where-Object {$_.connectorName -eq $connectorType}
				if($notApprovedConnector)
				{
					$childControlResult.AddMessage([VerificationResult]::Failed, $notApprovedConnector.Remarks)
				}
				else
				{
					#Check if it belongs to approved connectors
					$approvedConnector = $this.LogicAppConnectorsMetadata.ApprovedConnectors | Where-Object {$_.connectorName -eq $connectorType} 
					if(($approvedConnector|Measure-Object).Count -gt 0)
					{
						#check if control is applicable on this connector
						$applicableControl = $approvedConnector.ApplicableControls | Where-Object {$_.Name -eq $controlName} 
						$notApplicableControl = $approvedConnector.NotApplicableControls | Where-Object {$_.Name -eq $controlName} 
						if(($applicableControl|Measure-Object).Count -gt 0)
						{
							#Get method name
							$methodName = $applicableControl.MethodName 
							$childControlResult = $this.$methodName($applicableControl.Remarks , $childControlResult, $Connector)
						}
						else
						{
							$methodName = $notApplicableControl.MethodName 
							if($notApplicableControl.Remarks -eq [string]::Empty)
							{
								$notApplicableControl.Remarks = "This control is not applicable on connector type - " + $connectorType 
 							}
							$childControlResult = $this.$methodName($notApplicableControl.Remarks , $childControlResult, $Connector)							
						}
					}
					else
					{
						$childControlResult.AddMessage([VerificationResult]::Manual, $connectorType+" connector is not evaluated yet")
					}
				}		
				$controlResultList += $childControlResult			
			}
		return $controlResultList
	}

	hidden [ControlResult] DefaultPassed([string] $remarks,[ControlResult] $childControlResult, [PSObject] $Connector)
	{
		$childControlResult.AddMessage([VerificationResult]::Passed, $remarks)
		return $childControlResult
	}

	hidden [ControlResult] DefaultManual([string] $remarks,[ControlResult] $childControlResult, [PSObject] $Connector)
	{
		$childControlResult.AddMessage([VerificationResult]::Manual, $remarks)
		return $childControlResult
	}

}

