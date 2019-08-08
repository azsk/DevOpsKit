<#
.Description
# Module helper function
# Provides common function to module version 
#>

class ModuleHelper: EventBase {
    
    hidden ModuleHelper() {
    }

    hidden static [ModuleHelper] $Instance = $null;

    static [ModuleHelper] GetInstance() {
        if ( $null  -eq [ModuleHelper]::Instance  ) {
            [ModuleHelper]::Instance = [ModuleHelper]::new();
        }
        return [ModuleHelper]::Instance
    }
    
    #Function to get current running module
    static [string] GetModuleName()
    {
        if([ModuleHelper]::GetInstance().InvocationContext)
		{
			return [ModuleHelper]::GetInstance().InvocationContext.MyCommand.Module.Name;
		}

		throw [System.ArgumentException] "The parameter 'InvocationContext' is not set"
    }

	static [CommandDetails] GetCommandMetadata()
    {
        if([ModuleHelper]::GetInstance().InvocationContext)
		{
			$commandNoun = [ModuleHelper]::GetInstance().InvocationContext.MyCommand.Noun
			if(-not [string]::IsNullOrWhiteSpace([ModuleHelper]::GetInstance().InvocationContext.MyCommand.Module.Prefix))
			{
				# Remove the module prefix from command name
				$commandNoun = $commandNoun.TrimStart([ModuleHelper]::GetInstance().InvocationContext.MyCommand.Module.Prefix);
			}

			return [CommandHelper]::Mapping | 
								Where-Object { $_.Noun -eq $commandNoun -and $_.Verb -eq [ModuleHelper]::GetInstance().InvocationContext.MyCommand.Verb } | 
								Select-Object -First 1;
		}

		throw [System.ArgumentException] "The parameter 'InvocationContext' is not set"
    }

	static [bool] IsLatestVersionRequired()
    {
        if([ModuleHelper]::GetInstance().InvocationContext)
		{
			$commandNoun = [ModuleHelper]::GetInstance().InvocationContext.MyCommand.Noun
			if(-not [string]::IsNullOrWhiteSpace([ModuleHelper]::GetInstance().InvocationContext.MyCommand.Module.Prefix))
			{
				# Remove the module prefix from command name
				$commandNoun = $commandNoun.TrimStart([ModuleHelper]::GetInstance().InvocationContext.MyCommand.Module.Prefix);
			}

			$mapping = [CommandHelper]::Mapping | 
								Where-Object { $_.Noun -eq $commandNoun -and $_.Verb -eq [ModuleHelper]::GetInstance().InvocationContext.MyCommand.Verb } | 
								Select-Object -First 1;
			return $mapping.IsLatestRequired;
		}

		throw [System.ArgumentException] "The parameter 'InvocationContext' is not set"
    }

	static [System.Version] GetCurrentModuleVersion()
    {
        if([ModuleHelper]::GetInstance().InvocationContext)
		{
			return [System.Version] ([ModuleHelper]::GetInstance().InvocationContext.MyCommand.Version);
		}

		# Return default version which is 0.0.
		return [System.Version]::new();
    }
}