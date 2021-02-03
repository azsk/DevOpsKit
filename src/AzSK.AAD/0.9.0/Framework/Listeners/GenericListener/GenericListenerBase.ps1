Set-StrictMode -Version Latest 

class GenericListenerBase
{		
	hidden [ListenerBase] $ParentInstance = $null;  

    hidden [AzSKRootEventArgument] $EventArgs = $null;
    
    
	GenericListenerBase($_ParentInstance, $_EventArgs)
	{
		$this.ParentInstance = $_ParentInstance;
		$this.EventArgs = $_EventArgs;
	}

    [void] SVTCommandStarted ([PSObject] $params)
    {
        return;
    }

    [void] SVTCommandCompleted ([PSObject] $params)
    {
        return;
    }

    [void] GenericCommandStarted ([PSObject] $params)
    {
        return;
    }

    [void] GenericCommandCompleted ([PSObject] $params)
    {
        return;
    }

    [void] FeatureEvaluationStarted ([PSObject] $params)
    {
        return;
    }

    [void] FeatureEvaluationCompleted ([PSObject] $params)
    {
        return;
    }	
}

	



