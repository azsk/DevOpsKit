Set-StrictMode -Version Latest

function Set-AzSKPIMConfiguration # Manage/Set-AzSKPIMConfiguration
{	
	Begin
	{
		[CommandHelper]::BeginCommand($MyInvocation);
		[ListenerHelper]::RegisterListeners();
	}
	Process
	{
	try 
		{
			$SubscriptionId = [Constants]::BlankSubscriptionId
			$pimscript=[PIM]::new($SubscriptionId, $MyInvocation);
			$pimscript.PIMScript();
		}
		catch 
		{
			[EventBase]::PublishGenericException($_);
		}  
	}
	End
	{
		[ListenerHelper]::UnregisterListeners();
	}

}

