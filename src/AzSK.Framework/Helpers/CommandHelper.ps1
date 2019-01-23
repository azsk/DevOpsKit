using namespace System.Management.Automation
Set-StrictMode -Version Latest  
class CommandHelper
{
	static [CommandDetails[]] $Mapping = @(
		# Services Security Status
		[CommandDetails]@{
            Verb = "Get";
            Noun = "AzSKAzureServicesSecurityStatus";
            ShortName = "GRS";
			IsLatestRequired = $false;
        },
		[CommandDetails]@{
            Verb = "Get";
            Noun = "AzSKControlsStatus";
            ShortName = "GACS";
			IsLatestRequired = $false;
        },
		[CommandDetails]@{
            Verb = "Get";
            Noun = "AzSKExpressRouteNetworkSecurityStatus";
            ShortName = "GES";
			IsLatestRequired = $false;
        },
		
		#Subscription Security
		[CommandDetails]@{
            Verb = "Get";
            Noun = "AzSKSubscriptionSecurityStatus";
            ShortName = "GSS";
			IsLatestRequired = $false;
        },
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKSubscriptionSecurity";
			ShortName = "SSS";
			HasAzSKComponentWritePermission = $true;
        },
		[CommandDetails]@{
            Verb = "Update";
            Noun = "AzSKSubscriptionSecurity";
            ShortName = "USS";
			IsLatestRequired = $false;
			HasAzSKComponentWritePermission = $true;
        },
		[CommandDetails]@{
            Verb = "Remove";
            Noun = "AzSKSubscriptionSecurity";
            ShortName = "RSS";
        },

		# CA
		[CommandDetails]@{
            Verb = "Get";
            Noun = "AzSKContinuousAssurance";
            ShortName = "GCA";
			IsLatestRequired = $false;
        },
		[CommandDetails]@{
            Verb = "Install";
            Noun = "AzSKContinuousAssurance";
			ShortName = "ICA";
			HasAzSKComponentWritePermission = $true;
        },
		[CommandDetails]@{
            Verb = "Remove";
            Noun = "AzSKContinuousAssurance";
            ShortName = "RCA";
        },
		[CommandDetails]@{
            Verb = "Update";
            Noun = "AzSKContinuousAssurance";
			ShortName = "UCA";
			HasAzSKComponentWritePermission = $true;
        },

		#Alerts
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKAlerts";
			ShortName = "SAA";
			HasAzSKComponentWritePermission = $true;
        },
		[CommandDetails]@{
            Verb = "Remove";
            Noun = "AzSKAlerts";
            ShortName = "RAL";
        },

		#Alerts Monitoring
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKAlertMonitoring";
            ShortName = "SAM";
        },
		[CommandDetails]@{
            Verb = "Remove";
            Noun = "AzSKAlertMonitoring";
            ShortName = "RAM";
        },

		#ARM Policies
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKARMPolicies";
			ShortName = "SAP";
			HasAzSKComponentWritePermission = $true;
        },
		[CommandDetails]@{
            Verb = "Remove";
            Noun = "AzSKARMPolicies";
            ShortName = "RAP";
        },

		#RBAC
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKSubscriptionRBAC";
			ShortName = "SRB";
			HasAzSKComponentWritePermission = $true;
        },
		[CommandDetails]@{
            Verb = "Remove";
            Noun = "AzSKSubscriptionRBAC";
            ShortName = "RRB";
        },

		# Security Centre
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKAzureSecurityCenterPolicies";
			ShortName = "SSC";
			HasAzSKComponentWritePermission = $true;
        },

		# OMS
		[CommandDetails]@{
            Verb = "Install";
            Noun = "AzSKOMSSolution";
            ShortName = "IOM";
        },

		# FixControl
		[CommandDetails]@{
            Verb = "Repair";
            Noun = "AzSKAzureServicesSecurity";
            ShortName = "RRS";
        },
		[CommandDetails]@{
            Verb = "Repair";
            Noun = "AzSKSubscriptionSecurity";
            ShortName = "RASS";
        },

		# Policy Store
		[CommandDetails]@{
            Verb = "Install";
            Noun = "AzSKOrganizationPolicy";
            ShortName = "IOP";
			IsLatestRequired = $false;
        },
		[CommandDetails]@{
            Verb = "Update";
            Noun = "AzSKOrganizationPolicy";
            ShortName = "UOP";
			IsLatestRequired = $false;
		},
		[CommandDetails]@{
            Verb = "Get";
            Noun = "AzSKOrganizationPolicyStats";
            ShortName = "GOP";
			IsLatestRequired = $false;
        },
		[CommandDetails]@{
            Verb = "Get";
            Noun = "AzSKInfo";
            ShortName = "GAI";
			IsLatestRequired = $false;
		},
		[CommandDetails]@{
            Verb = "Get";
            Noun = "AzSKSecurityRecommendationReport";
            ShortName = "GAR";
			IsLatestRequired = $false;
		},
		[CommandDetails]@{
            Verb = "Clear";
            Noun = "AzSKSessionState";
            ShortName = "CSS";
			IsLatestRequired = $false;
        },
		# Update-PersistedState

		[CommandDetails]@{
            Verb = "Update";
            Noun = "AzSKPersistedState";
            ShortName = "UPS";
			IsLatestRequired = $false;
        },
		[CommandDetails]@{
            Verb = "Get";
            Noun = "AzSKAccessToken";
            ShortName = "GAT";
        },
		[CommandDetails]@{
            Verb = "Get";
            Noun = "AzSKSupportedResourceTypes";
            ShortName = "GSRT";
        },
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKPolicySettings";
            ShortName = "SPS";
        },
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKOMSSettings";
            ShortName = "SOS";
        },
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKEventHubSettings";
            ShortName = "SEHS";
        },
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKWebhookSettings";
            ShortName = "SWHS";
        },
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKUsageTelemetryLevel";
            ShortName = "SUTL";
        },
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKLocalAIOrgTelemetrySettings";
            ShortName = "SLOTS";
        },
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKUserPreference";
            ShortName = "SUP";
        },
		[CommandDetails]@{
            Verb = "Set";
            Noun = "AzSKPrivacyNoticeResponse";
            ShortName = "SPNR";
        },
		[CommandDetails]@{
            Verb = "Send";
            Noun = "AzSKInternalData";
            ShortName = "SID";
        },
		[CommandDetails]@{
            Verb = "Get";
            Noun = "AzSKARMTemplateSecurityStatus";
            ShortName = "GATS";
        }
    );

	static BeginCommand([InvocationInfo] $invocationContext)
	{
		# Validate Command Prerequisites like AzureRM multiple version load issue
		[CommandHelper]::CheckCommandPrerequisites($invocationContext);
		[CommandHelper]::SetAzSKModuleName($invocationContext);
		[CommandHelper]::SetCurrentAzSKModuleVersion($invocationContext);
		# display warning if alias
		[CommandHelper]::CheckForAlias($invocationContext.InvocationName)
	}

	static CheckCommandPrerequisites([InvocationInfo] $invocationContext)
	{
		# Validate required module version dependency
	    try
		{			
			#Loop through all required modules list
			$invocationContext.MyCommand.Module.RequiredModules | ForEach-Object {				
				$requiredModule = $_
				$moduleList = Get-Module $requiredModule.Name 
				#Get list of other than required version is loaded into session
				$otherThanRequiredModule = @();
				$otherThanRequiredModule += $moduleList | Where-Object { $_.Version -ne $requiredModule.Version}
				if($otherThanRequiredModule.Count -gt 0 )
				{	 
					#Display warning   
					$loadedVersions = @();
					$moduleList | ForEach-Object {
						$loadedVersions += $_.Version.ToString()
					};
					Write-Host "WARNING: Found multiple versions of Azure PowerShell ($($requiredModule.Name)) modules loaded in the session. ($($requiredModule.Name) versions found: $([string]::Join(", ", $loadedVersions)))" -ForegroundColor Yellow
                    Write-Host "WARNING: This will lead to issues when running AzSK cmdlets." -ForegroundColor Yellow
                    Write-Host 'Recommendation: Please start a fresh PowerShell session and run "Import-Module AzSK" first to avoid getting into this situation.' -ForegroundColor Yellow					
				}
				else
				{
					# Continue execution without any error or warning
					Write-Debug ($requiredModule.Name + " module version dependency validation successful")
				}			
			};		
		}
		catch
		{
			Write-Debug "Not able to validate version dependency $_"
		}
		#check if old and new both modules are loaded in same session		
		$newModule = Get-Module|Where-Object {$_.Name -like "$([Constants]::NewModuleName)*"} | Select-Object -First 1
		$oldModule = Get-Module|Where-Object {$_.Name -like "$([Constants]::OldModuleName)*"} | Select-Object -First 1
		if($newModule -and $oldModule)
		{	 
			$warningMsg = [String]::Format([Constants]::MultipleModulesWarning, $newModule.Name,$oldModule.Name,$newModule.Name)
			Write-Host $warningMsg -ForegroundColor Yellow
			#stop execution
			throw ([SuppressedException]::new("",[SuppressedExceptionType]::Generic))
		}
		else
		{
			# Continue execution without any error or warning
			Write-Debug ("Multiple modules ($([Constants]::NewModuleName) and $([Constants]::OldModuleName)) load validation successful")
		}
		
	}

	static [void] SetAzSKModuleName([InvocationInfo] $invocationContext)
	{
		if($invocationContext)
		{
			[Constants]::SetAzSKModuleName($invocationContext.MyCommand.Module.Name);
		}
	}
	static [void] SetCurrentAzSKModuleVersion([InvocationInfo] $invocationContext)
	{
		if($invocationContext)
		{
			[Constants]::SetAzSKCurrentModuleVersion($invocationContext.MyCommand.Version);
		}
	}

	static [void] CheckForAlias([string] $methodName)
	{
		if($methodName -like "*-$([Constants]::OldModuleName)*")
		{
			#get correct casing 
			$methodName = get-command -Name $methodName
			$newMethodName = $methodName -replace ("-"+[Constants]::OldModuleName),("-"+[Constants]::NewModuleName);
			$CommandNameChangeWarning = [Constants]::CommandNameChangeWarning -f $methodName,$newMethodName
			Write-Warning $CommandNameChangeWarning
		}
	}
}
