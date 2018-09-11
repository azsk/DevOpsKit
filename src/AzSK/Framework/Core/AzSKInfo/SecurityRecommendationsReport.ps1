Set-StrictMode -Version Latest 



class SecurityRecommendationsReport: CommandBase

{    

	hidden [PSObject] $AzSKRG = $null

	hidden [String] $AzSKRGName = ""

	hidden [hashtable]$category_hash = @{

		"Storage" = 1000003;
	
		"DataProcessing" = 1000033;
	
		"Reporting" = 1000037;
	
		"Web Front End" = 1000039;
	
		"APIs" = 1000081;
	
		"Security Infra" = 1000099;
	
		"SubscriptionCore" = 1000117;
	
		"Communication Hub" = 1000121;
	
		"Hybrid" = 1000133;
	
		"Network Isolation" = 1000151;
	
		"Cache" = 1000159;
	
		"Backend Processing" = 123123593;
	
	}
	
	hidden [hashtable] $get_categories =@{

		"CDN" = @("Storage") ;

		"ServiceBus" = @("Communication Hub", "Hybrid");

		"AppService" = @("Web Front End", "APIs");
	
		"SQLDatabase"= @("Storage", "DataProcessing", "Reporting");
	
		"Storage"= @("Storage", "Reporting", "DataProcessing");
	
		"LogicApps"= @("DataProcessing");
	
		"DataFactory"= @("DataProcessing");
	
		"DataLakeAnalytics"= @("DataProcessing", "Reporting");
	
		"DataLakeStore"= @("Storage", "Reporting", "DataProcessing");
	
		"NotificationHub"= @("Communication Hub");
	
		"ServiceFabric"=  @("Web Front End", "APIs", "Backend Processing");
	
		"Search" = @("APIs", "Backend Processing");
	
		"VirtualMachine"= @("Web Front End", "APIs", "Backend Processing",
	
						   "DataProcessing");
	
		"ContainerRegistry" = @("Web Front End", "APIs", "Backend Processing",
	
						   "DataProcessing");
	
		"VirtualNetwork" = @("Network Isolation", "Hybrid");
	
		"AnalysisServices"= @("DataProcessing", "Reporting");
	
		"Batch" = @("Backend Processing");
	
		"RedisCache" = @("Cache");
	
		"EventHub"= @("Communication Hub", "Hybrid");
	
		"ODG"= @("Hybrid");
	
		"TrafficManager"= @("Network Isolation");
	
		"ERvNet" = @("Hybrid", "Network Isolation");
	
		"Automation" = @("Backend Processing");
	
		"CosmosDB"= @("Storage", "DataProcessing", "Reporting");
	
		"StreamAnalytics"= @("DataProcessing", "Reporting");
	
		"CloudService"= @("Web Front End", "APIs", "Backend Processing");
	
		"LoadBalancer"= @("Network Isolation");
	
		"APIConnection"= @("DataProcessing");
	
		"BotService"= @("APIs", "Communication Hub", "Web Front End");
	
		"ContainerInstances"= @("Web Front End", "APIs", "DataProcessing",
	
							   "Backend Processing");
	
		"DataFactoryV2"= @("DataProcessing", "Backend Processing");
	
		"KeyVault"= @("Security Infra");
	}

	SecurityRecommendationsReport([string] $subscriptionId, [InvocationInfo] $invocationContext): 

        Base($subscriptionId, $invocationContext) 

    { 

		#$this.DoNotOpenOutputFolder = $true;

		$this.AzSKRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;

		$this.AzSKRG = Get-AzureRmResourceGroup -Name $this.AzSKRGName -ErrorAction SilentlyContinue

	}

	hidden [System.Object]get_hash([SecurityReportInput] $Input){

		$hash_val = 1;

      if(-not [string]::IsNullOrWhiteSpace($Input.Categories))
	   {

		foreach ($category in $Input.Categories)
		{
		
			$hash_val = $hash_val * $this.category_hash[$category];

			$hash_val = $hash_val % 824633720831 ;
			
		}
		
	   }

	   if(-not [string]::IsNullOrWhiteSpace($Input.Features))
	   {

		foreach ($feature in $Input.Features)
		{
			[string[]] $categories = $this.get_categories[$feature];
			
			$hash_val = $hash_val * $this.category_hash[$categories[0]];

			$hash_val = $hash_val % 824633720831 ;
			
		}
		
	   }

		return $hash_val;
	}

	[psobject]FindReport([psobject] $Allcombinations,[System.Object] $hash_val)
	{

     return $Allcombinations.$hash_val;

	}

	[bool]CompareArrays([string[]] $a, [string[]] $b)
	{
		if($a.Count -ne $b.Count)
		{
			return $false;
		}

		for($i=0; $i -lt $a.Count;$i++)
		{
			if(($b.Contains($a[$i])) -eq $false)
			{
				return $false;
			}
		}
		return $true;
	}

	[MessageData[]] GenerateReport([string] $ResourceGroupName, [ResourceTypeName[]] $ResourceTypeNames,[string[]] $Categories)

    {		    	    

	    [MessageData[]] $messages = @();	   

		try

		{

			[RecommendedSecurityReport] $report = [RecommendedSecurityReport]::new();

			[SecurityReportInput] $userInput = [SecurityReportInput]::new();

			if(-not [string]::IsNullOrWhiteSpace($ResourceGroupName))

			{

				$resources = Find-AzureRmResource -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

				if(($resources | Measure-Object).Count -gt 0)

				{

					[SVTMapping]::GetSupportedResourceMap();

					$resources | ForEach-Object{						

						if($null -ne [SVTMapping]::SupportedResourceMap[$_.ResourceType.ToLower()])

						{

							$userInput.Features += ([SVTMapping]::SupportedResourceMap[$_.ResourceType.ToLower()]).ToString();

						}

					}	

					$report.ResourceGroupName = $ResourceGroupName;

				}				

				elseif(($ResourceTypeNames | Measure-Object).Count -gt 0)

				{

					$ResourceTypeNames | ForEach-Object { $userInput.Features += $_.ToString();}

				}

				elseif(($Categories | Measure-Object).Count -gt 0)

				{

					$userInput.Categories = Categories

				}

			}			



			#$uri = "http://104.211.204.4/recommend";

			$content = [Helpers]::ConvertToJsonCustomCompressed($userInput);

			#write-host $content;

			$headers = @{};

			$RecommendationURI = [constants]::RecommendationURI;

			$result = [ConfigurationHelper]::InvokeControlsAPI($RecommendationURI, '', '', '');

			[RecommendedSecureCombination] $Combination = [RecommendedSecureCombination]::new();

			$hash_val=$this.get_hash($userInput);
			
			$result=$this.FindReport($result,$hash_val);

			if(($result | Measure-Object).Count -gt 0)

			{

				$currentFeatureGroup = [RecommendedFeatureGroup]::new();

				$currentFeatureGroup.Features = $userInput.Features;

				#$currentFeatureGroup.Categories = $userInput.Categories;

				<#$currentFeatureGroup.Ranking = 2;

				$currentFeatureGroup.TotalSuccessCount = $result.TotalSuccessCount;

				$currentFeatureGroup.TotalFailCount = $result.TotalFailCount;

				$currentFeatureGroup.SecurityRating = (1-$result.SecurityRating)*100;

				$currentFeatureGroup.TotalOccurances = $result.TotalOccurrences;

				$Combination.CurrentFeatureGroup = $currentFeatureGroup;#>

				[int]$i =1;
               
				$result | ForEach-Object{

					$recommendedGroup = $_;

					$recommededFeatureGroup = [RecommendedFeatureGroup]::new();

					$recommededFeatureGroup.Features = $recommendedGroup.features;

					foreach ($feature in $recommendedGroup.features)
					{
						[string[]] $categories = $this.get_categories[$feature];

						$recommededFeatureGroup.Categories += $categories[0];	

					}

					if($this.CompareArrays($userInput.Features,$recommendedGroup.features))
					{
						$currentFeatureGroup.Ranking = $i;

						$currentFeatureGroup.TotalSuccessCount = $recommendedGroup.info.Success;

						$currentFeatureGroup.TotalFailCount = $recommendedGroup.info.Fails;

						$currentFeatureGroup.SecurityRating = ($recommendedGroup.info.Fails/$recommendedGroup.info.Totals);

						$currentFeatureGroup.TotalOccurances = $recommendedGroup.info.Totals;

						$currentFeatureGroup.Categories = $recommededFeatureGroup.Categories;

						$Combination.CurrentFeatureGroup += $currentFeatureGroup
					}	

					$recommededFeatureGroup.Ranking = $i;

					$i++;

					$recommededFeatureGroup.TotalSuccessCount = $recommendedGroup.info.Success;

					$recommededFeatureGroup.TotalFailCount = $recommendedGroup.info.Fails;

					$recommededFeatureGroup.SecurityRating = ($recommendedGroup.info.Fails/$recommendedGroup.info.Totals);

					$recommededFeatureGroup.TotalOccurances = $recommendedGroup.info.Totals;

					$Combination.RecommendedFeatureGroups += $recommededFeatureGroup;

				}



			}



			<#[RecommendedSecureCombination] $dummy = [RecommendedSecureCombination]::new();



			$dummyCFG = [RecommendedFeatureGroup]::new();

			$dummyCFG.Features = @("AppService","Storage");

			$dummyCFG.Categories = @("Web App","Storage");		

			$dummyCFG.Ranking = 2;

			$dummyCFG.TotalSuccessCount = 300;

			$dummyCFG.TotalFailCount = 100;

			$dummyCFG.SecurityRating = 60.00;

			$dummyCFG.TotalOccurances = 4;

			$dummy.CurrentFeatureGroup = $dummyCFG;



			$dummyFG1 = [RecommendedFeatureGroup]::new();

			$dummyFG1.Features = @("AppService","Storage");

			$dummyFG1.Categories = @("Web App","Storage");		

			$dummyFG1.Ranking = 2;

			$dummyFG1.TotalSuccessCount = 300;

			$dummyFG1.TotalFailCount = 100;

			$dummyFG1.SecurityRating = 60.00;

			$dummyFG1.TotalOccurances = 4;

			$dummy.RecommendedFeatureGroups += $dummyFG1;



			$dummyFG2 = [RecommendedFeatureGroup]::new();

			$dummyFG2.Features = @("AppService", "Storage","KeyVault");			

			$dummyFG2.Categories = @("Web App","Storage", "Security Infra");		

			$dummyFG2.Ranking = 1;

			$dummyFG2.TotalSuccessCount = 350;

			$dummyFG2.TotalFailCount = 50;

			$dummyFG2.SecurityRating = 60.00;

			$dummyFG2.TotalOccurances = 4;

			$dummy.RecommendedFeatureGroups += $dummyFG2;



			$dummyFG3 = [RecommendedFeatureGroup]::new();

			$dummyFG3.Features = @("AppService", "Automation","KeyVault");			

			$dummyFG3.Categories = @("Web App","Backend Processing", "Security Infra");		

			$dummyFG3.Ranking = 1;

			$dummyFG3.TotalSuccessCount = 350;

			$dummyFG3.TotalFailCount = 50;

			$dummyFG3.SecurityRating = 60.00;

			$dummyFG3.TotalOccurances = 4;

			$dummy.RecommendedFeatureGroups += $dummyFG3; #>

			#Write-Host ($dummy | ConvertTo-Json -Depth 10)

			[MessageData] $message = [MessageData]::new();

			$message.Message = "RecommendationData"

			$report.Input = $userInput;

			$report.Recommendations =$Combination;

			$message.DataObject = $report;

			$messages += $message;

			#$outputReponse = [RecommendedSecureCombination]($result)

			#AddToMessages

			#$messages.

			

		}

		catch

		{

		$this.PublishEvent([AzSKGenericEvent]::Exception, "Unable to generate the security recommendation report");

			$this.PublishException($_);

		}

		return $messages;

	}

}

