Set-StrictMode -Version Latest 
class APIConnectionControl
{
	[string] $Name = ""
	[string] $Automated = ""
	[string] $MethodName = ""
	[string] $Remarks = ""
}
class APIConnectionApprovedConnector
{
	[string] $connectorName = ""
	[APIConnectionControl[]] $ApplicableControls = @()
	[APIConnectionControl[]] $NotApplicableControls = @()
	
}
class APIConnectionNotApprovedConnector
{
	[string] $connectorName = ""
	[string] $Remarks = ""
	
}
class APIConnectionConnectorsMetadata
{
	[APIConnectionApprovedConnector[]] $ApprovedConnectors = @()
	[APIConnectionNotApprovedConnector[]] $notApprovedConnectors = @()	
}

class APIConnection: SVTBase
{   
	hidden [PSObject] $LogicAppObject;
    hidden [PSObject] $ResourceObject;
	hidden [APIConnectionConnectorsMetadata] $LogicAppConnectorsMetadata

	
    APIConnection([string] $subscriptionId, [string] $resourceGroupName, [string] $resourceName): 
        Base($subscriptionId, $resourceGroupName, $resourceName) 
    { 
        $this.GetResourceObject();		
		$this.LogicAppConnectorsMetadata = [APIConnectionConnectorsMetadata] ($this.LoadServerConfigFile("LogicApps.Connectors.json"));
    }

    APIConnection([string] $subscriptionId, [SVTResource] $svtResource): 
        Base($subscriptionId, $svtResource) 
    { 
        $this.GetResourceObject();
		$this.LogicAppConnectorsMetadata = [APIConnectionConnectorsMetadata] ($this.LoadServerConfigFile("LogicApps.Connectors.json"));
    }

    hidden [PSObject] GetResourceObject()
    {
		$logicAppConnectors = $this.ResourceContext.ResourceName.Split("//")

		if(($logicAppConnectors | Measure-Object).count -eq 2)
		{
			$this.LogicAppObject = Get-AzureRmResource -Name $logicAppConnectors[0] `
                                            -ResourceGroupName $this.ResourceContext.ResourceGroupName -ResourceType 'Microsoft.Logic/Workflows'
		}
		else
		{
			throw ([SuppressedException]::new(("Logic App Connector '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
		}
        if (-not $this.LogicAppObject) 
		{
			  throw ([SuppressedException]::new(("LogicApp '{0}' not found under Resource Group '{1}'" -f ($this.ResourceContext.ResourceName), ($this.ResourceContext.ResourceGroupName)), [SuppressedExceptionType]::InvalidOperation))
		}
		else
		{
			$this.ResourceObject = $this.GetConnectorObject()
		}
        return $this.ResourceObject;
    }

	hidden [PSObject] GetConnectorObject()
	{
		if($this.ResourceContext.ResourceId -like "*/custom/*")
		{
			$Definition = $this.LogicAppObject.Properties.definition
			if($null -ne $Definition.Actions -and -not[string]::IsNullOrEmpty($this.LogicAppObject.Properties.definition.actions))
			{
				$connectorFound = ($Definition.Actions | Get-Member -MemberType *Property | Where-Object { $_.name -eq  ($this.ResourceContext.ResourceName.Split("//")[1]) -and ($Definition.Actions.($_.name).type -ne 'ApiConnection') } | Select-Object -First 1)
				if($null -ne $connectorFound)
				{
						$Name = $connectorFound.name	
						$Connector = New-Object PSObject
						Add-Member -InputObject $Connector -MemberType NoteProperty -Name ConnectorName -Value $Name
						Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorType -Value $Definition.Actions.$Name.type
						Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorObj -Value $Definition.Actions.$Name
						$this.ResourceObject = $Connector
				}
			}
			if($null -ne $Definition.triggers -and -not[string]::IsNullOrEmpty($this.LogicAppObject.Properties.definition.triggers))
			{
				$connectorFound = ($Definition.Triggers | Get-Member -MemberType *Property | Where-Object { $_.name -eq  ($this.ResourceContext.ResourceName.Split("//")[1]) -and ($Definition.Triggers.($_.name).type -ne 'ApiConnection') } | Select-Object -First 1)
					if($null -ne $connectorFound)
					{
						$Name = $connectorFound.name	
						$Connector = New-Object PSObject
						Add-Member -InputObject $Connector -MemberType NoteProperty -Name ConnectorName -Value $Name
						Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorType -Value $Definition.Triggers.$Name.type
						Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorObj -Value $Definition.Triggers.$Name
						$this.ResourceObject = $Connector
					}
			}
		}
		else
		{
			$apiConObj = Get-AzureRmResource -ResourceId $this.ResourceContext.ResourceId
			$apiName=$apiConObj.Properties.Api.Name           				
			
			$Connector = New-Object PSObject
			Add-Member -InputObject $Connector -MemberType NoteProperty -Name ConnectorName -Value $apiName   
			Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorType -Value $apiName
			Add-Member -InputObject $Connector -MemberType NoteProperty  -Name ConnectorObj -Value $null

			$this.ResourceObject = $Connector
		}
		return $this.ResourceObject;
	}

	hidden [ControlResult] CheckConnectorsAADAuth([ControlResult] $controlResult)
    {
		$controlResult =  $this.GetConnectorsStatus("AAD", $controlResult)
		return $controlResult;
    }
	hidden [ControlResult] CheckConnectorsEncryptionInTransit([ControlResult] $controlResult)
    {
		$controlResult = $this.GetConnectorsStatus("EncryptionTransit", $controlResult)
		return $controlResult;
    }

	#internal functions
	
	hidden [ControlResult] CheckAadAuthForHttp([string] $remarks , [ControlResult] $childControlResult)
	{   
		$isPassed = $false		
		if(Get-Member -inputobject $this.ResourceObject.ConnectorObj.inputs -name "authentication" -Membertype Properties)
		{	
			if([Helpers]::CheckMember($this.ResourceObject.ConnectorObj.inputs.authentication,"type") -and $this.ResourceObject.ConnectorObj.inputs.authentication.type -eq "ActiveDirectoryOAuth")
			{
				$isPassed = $true
			}
		}	
		if($isPassed)	
		{
			$childControlResult.AddMessage([VerificationResult]::Passed,"AAD Authentication is used in connector - "+ $this.ResourceObject.ConnectorName)
		}
		else
		{
			$childControlResult.AddMessage([VerificationResult]::Failed, "AAD Authentication is not used in connector - "+ $this.ResourceObject.ConnectorName)
		}
		return $childControlResult
	}
	
	hidden [ControlResult] CheckEncryptionTransitForHttp([string] $remarks, [ControlResult] $childControlResult)
	{
			$isPassed = $true
			$uriString = $this.ResourceObject.ConnectorObj.inputs.uri			
			
			if(([system.Uri]$uriString).Scheme -ne 'https')
			{
				$isPassed = $false 
			}
			if($isPassed)	
			{
				$childControlResult.AddMessage([VerificationResult]::Passed,"Connector name : " + $this.ResourceObject.ConnectorName + "`r`nConnector URI : "+ $uriString)
			}
			else
			{
				$childControlResult.AddMessage([VerificationResult]::Failed, `
												"Must use HTTPS URI for below connector`r`n" `
												+ "Connector name : " + $this.ResourceObject.ConnectorName + "`r`nConnector URI : "+$uriString)
												
			}
			return $childControlResult
	}
	
	hidden [ControlResult] CheckEncryptionTransitForWebhook([string] $remarks , [ControlResult] $childControlResult)
	{
		$isPassed = $true			
		$subURI = ""
		$unSubURI = ""
		if(([Helpers]::CheckMember($this.ResourceObject.connectorObj.inputs,"subscribe")) -and ([Helpers]::CheckMember($this.ResourceObject.connectorObj.inputs.subscribe,"uri")))
		{
			$subURI = $this.ResourceObject.connectorObj.inputs.subscribe.uri
		}
		
		if(([Helpers]::CheckMember($this.ResourceObject.connectorObj.inputs,"unsubscribe")) -and ([Helpers]::CheckMember($this.ResourceObject.connectorObj.inputs.unsubscribe,"uri")))
		{
			$unSubURI = $this.ResourceObject.connectorObj.inputs.unsubscribe.uri 
		}

		if(($subURI -ne "" -and ([system.Uri]$subURI).Scheme -ne 'https') -or ($unSubURI -ne "" -and ([system.Uri]$unSubURI).Scheme -ne 'https'))
		{
			$isPassed = $false
		} 
		if($isPassed)	
		{
			$childControlResult.AddMessage([VerificationResult]::Passed, "Connector name : " + $this.ResourceObject.ConnectorName `
																		+ "`r`nWebhook subscribe URI : "+ $subURI`
																		+ "`r`nWebhook unsubscribe URI : "+$unSubURI)
		}
		else
		{
			$childControlResult.AddMessage([VerificationResult]::Failed, "Must use HTTPS URI(s) for below connector`r`n" `
																		+ "Connector name : " + $this.ResourceObject.ConnectorName `
																		+ "`r`nWebhook subscribe URI : "+ $subURI`
																		+ "`r`nWebhook unsubscribe URI : "+$unSubURI)
		}
		return $childControlResult
	}	
	
	hidden [ControlResult] GetConnectorsStatus([string] $controlName, [ControlResult] $controlResult)
	{
		$connectorName=$this.ResourceObject.ConnectorName				
		$ConnectorObj = $this.ResourceObject.ConnectorObj
		$connectorType=$this.ResourceObject.ConnectorType

		if($connectorName -eq "manual")
		{
			$connectorName = $connectorType
		}					
					
		#check if this connector belongs to not approved list
		$notApprovedConnector = $this.LogicAppConnectorsMetadata.NotApprovedConnectors | Where-Object {$_.connectorName -eq $connectorType}
		if($notApprovedConnector)
		{
			$controlResult.AddMessage([VerificationResult]::Failed, $notApprovedConnector.Remarks)
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
					$controlResult = $this.$methodName($applicableControl.Remarks , $controlResult)
				}
				else
				{
					$methodName = $notApplicableControl.MethodName 
					if($notApplicableControl.Remarks -eq [string]::Empty)
					{
						$notApplicableControl.Remarks = "This control is not applicable on connector type - " + $connectorType 
 					}
					$controlResult = $this.$methodName($notApplicableControl.Remarks , $controlResult)							
				}
			}
			else
			{
				$controlResult.AddMessage([VerificationResult]::Manual, $connectorType+" connector is not evaluated yet")
			}
		}		
		return $controlResult			
	}

	hidden [ControlResult] DefaultPassed([string] $remarks,[ControlResult] $childControlResult)
	{
		$childControlResult.AddMessage([VerificationResult]::Passed, $remarks)
		return $childControlResult
	}

	hidden [ControlResult] DefaultManual([string] $remarks,[ControlResult] $childControlResult)
	{
		$childControlResult.AddMessage([VerificationResult]::Manual, $remarks)
		return $childControlResult
	}
}