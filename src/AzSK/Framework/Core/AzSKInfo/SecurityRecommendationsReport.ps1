Set-StrictMode -Version Latest 

class SecurityRecommendationsReport: AzCommandBase
{    
	hidden [PSObject] $AzSKRG = $null
	hidden [String] $AzSKRGName = ""
	$category_hash = $null;
	$get_categories = $null;
	SecurityRecommendationsReport([string] $subscriptionId, [InvocationInfo] $invocationContext): 
        Base($subscriptionId, $invocationContext) 

    { 
		$this.AzSKRGName = [ConfigurationManager]::GetAzSKConfigData().AzSKRGName;
		$this.AzSKRG = Get-AzResourceGroup -Name $this.AzSKRGName -ErrorAction SilentlyContinue
	}

	hidden [System.Object]get_hash([SecurityReportInput] $Input){
		$hash_val = 1;
        if(($Input.Categories| Measure-Object).Count -gt 0)
	    {
			foreach ($category in $Input.Categories)
			{
				[PSObject] $f=$category; 
				$hash_val = $hash_val * $this.category_hash.$f;
				$hash_val = $hash_val % 824633720831 ;
			}
	    }
	    if(($Input.Features | Measure-Object).Count -gt 0)
	    {
			foreach ($feature in $Input.Features)
			{
				[PSObject] $p=$feature;
				$categories = $this.get_categories.$p
				[PSObject] $f=$categories[0];
				$hash_val = $hash_val * $this.category_hash.$f;
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
	[psobject]FormatCombinations([psobject] $mostused)
	{
		$ht = @{}
		$mostused.psobject.properties | Foreach { $ht[$_.Name] =  [math]::Round($_.Value * 100,3)}
		$mostused = New-Object PSObject -Property $ht
        return $mostused
	}
	[String]FormatString([String] $mostused)
	{
		$mostused=$mostused.Substring(2,$mostused.Length-3)
		return $mostused -replace ';',"<br>"
	}
	[MessageData[]] GenerateReport([string] $ResourceGroupName, [ResourceTypeName[]] $ResourceTypeNames,[string[]] $Categories)
    {		    	    
		[MessageData[]] $messages = @();	
		$this.get_categories = [ConfigurationManager]::LoadServerConfigFile("CategoryMapping.json");
		#$this.get_categories = $this.get_categories | ConvertFrom-Json;
		$this.category_hash = [ConfigurationManager]::LoadServerConfigFile("CategoryHash.json");
		#$this.category_hash = $this.category_hash | ConvertFrom-Json;
		try
		{
			[RecommendedSecurityReport] $report = [RecommendedSecurityReport]::new();
			[SecurityReportInput] $userInput = [SecurityReportInput]::new();
			if(-not [string]::IsNullOrWhiteSpace($ResourceGroupName))
			{
				$resources = Get-AzResource -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
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
			}				
			elseif(($ResourceTypeNames | Measure-Object).Count -gt 0)
			{
				$ResourceTypeNames | ForEach-Object { $userInput.Features += $_.ToString();}
			}
			elseif(($Categories | Measure-Object).Count -gt 0)
			{
				$userInput.Categories = $Categories
			}
			$content = [JsonHelper]::ConvertToJsonCustomCompressed($userInput);
			#write-host $content;
			$headers = @{};
			$RecommendationURI = [constants]::RecommendationURI;
			$result = [ConfigurationHelper]::InvokeControlsAPI($RecommendationURI, '', '', '');
			[RecommendedSecureCombination] $Combination = [RecommendedSecureCombination]::new();
			$hash_val = $this.get_hash($userInput);
			$result = $this.FindReport($result,$hash_val);
			if(($result | Measure-Object).Count -gt 0)
			{
				$currentFeatureGroup = [RecommendedFeatureGroup]::new();
				$currentFeatureGroup.Features = $userInput.Features;
				if(($userInput.Categories | Measure-Object).Count -gt 0)
                {
                    $currentFeatureGroup.Ranking = "";
                    $currentFeatureGroup.TotalSuccessCount = "";
                    $currentFeatureGroup.TotalFailCount = "";
                    $currentFeatureGroup.UsagePercentage = "";
                    $currentFeatureGroup.TotalOccurances = "";
                    $currentFeatureGroup.Categories = "No features provided. This section is not application for Categories as input.";
                    $Combination.CurrentFeatureGroup += $currentFeatureGroup
                }
				[int]$i =1;
				$result | ForEach-Object{
					$recommendedGroup = $_;
					$recommededFeatureGroup = [RecommendedFeatureGroup]::new();
					$recommededFeatureGroup.Features = $recommendedGroup.features;
					foreach ($feature in $recommendedGroup.features)
					{
						[PSObject] $f=$feature;
						[string[]] $categories = $this.get_categories.$f;
						$recommededFeatureGroup.Categories += $categories[0];	
					}
					if($this.CompareArrays($userInput.Features,$recommendedGroup.features))
					{
						$currentFeatureGroup.Ranking = $i;
						$currentFeatureGroup.TotalSuccessCount = $recommendedGroup.info.Success;
						$currentFeatureGroup.TotalFailCount = $recommendedGroup.info.Fails;
						$currentFeatureGroup.FailureRate = ($recommendedGroup.info.Fails/$recommendedGroup.info.Totals)*100;
						$currentFeatureGroup.TotalOccurances = $recommendedGroup.occurrences;
						$currentFeatureGroup.Categories = $recommededFeatureGroup.Categories;
						$currentFeatureGroup.UsagePercentage = $recommendedGroup.UsagePercentage;
						$currentFeatureGroup.OtherMostUsed = $this.FormatCombinations($recommendedGroup.OtherMostUsed);
						$currentFeatureGroup.OtherMostUsed = $this.FormatString($currentFeatureGroup.OtherMostUsed);
						$Combination.CurrentFeatureGroup += $currentFeatureGroup
					}	
					$recommededFeatureGroup.Ranking = $i;
					$i++;
					$recommededFeatureGroup.TotalSuccessCount = $recommendedGroup.info.Success;
					$recommededFeatureGroup.TotalFailCount = $recommendedGroup.info.Fails;
					$recommededFeatureGroup.FailureRate = ($recommendedGroup.info.Fails/$recommendedGroup.info.Totals)*100;
					$recommededFeatureGroup.TotalOccurances = $recommendedGroup.occurrences;
					$recommededFeatureGroup.UsagePercentage = $recommendedGroup.UsagePercentage;
					$recommededFeatureGroup.OtherMostUsed = $this.FormatCombinations($recommendedGroup.OtherMostUsed);
					$recommededFeatureGroup.OtherMostUsed = $this.FormatString($recommededFeatureGroup.OtherMostUsed);
					$Combination.RecommendedFeatureGroups += $recommededFeatureGroup;
				}
			}

			[MessageData] $message = [MessageData]::new();
			$message.Message = "RecommendationData"
			$report.Input = $userInput;
			$report.Recommendations =$Combination;
			$message.DataObject = $report;
			$messages += $message;
		}
		catch
		{
			$this.PublishEvent([AzSKGenericEvent]::Exception, "Unable to generate the security recommendation report");
			$this.PublishException($_);
		}
		return $messages;
	}
}

