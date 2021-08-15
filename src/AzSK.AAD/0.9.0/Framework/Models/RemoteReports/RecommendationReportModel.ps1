Set-StrictMode -Version Latest

class SecurityReportInput
{        
    [string[]] $Categories = @();
    [string[]] $Features = @();    
}

class RecommendedSecureCombination
{
    [RecommendedFeatureGroup[]] $RecommendedFeatureGroups;
    [RecommendedFeatureGroup] $CurrentFeatureGroup;            
}

class RecommendedFeatureGroup{
    [string[]] $Features;
    [string[]] $Categories;
    [int] $Ranking;
    [int] $TotalSuccessCount;
    [int] $TotalFailCount;
    [float] $UsagePercentage;
    [int] $TotalOccurances;
    [float] $FailureRate;
    [string] $OtherMostUsed;
}

class RecommendedSecurityReport
{
    [SecurityReportInput] $Input;
    [string] $ResourceGroupName;
    [RecommendedSecureCombination] $Recommendations;
}