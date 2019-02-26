Set-StrictMode -Version Latest
#Class to register appropriate listeners based on environment
class ListenerHelper
{
	static ListenerHelper()
	{
	}

    static [void] RegisterListeners()
    {
		[WriteFolderPath]::GetInstance().RegisterEvents();
        [WriteDetailedLog]::GetInstance().RegisterEvents();
        [WriteSummaryFile]::GetInstance().RegisterEvents();
        [WritePsConsole]::GetInstance().RegisterEvents();
        [WriteDataFile]::GetInstance().RegisterEvents();
		[OMSOutput]::GetInstance().RegisterEvents();
        [EventHubOutput]::GetInstance().RegisterEvents();
        [WebhookOutput]::GetInstance().RegisterEvents();
		[AIOrgTelemetry]::GetInstance().RegisterEvents();
        [UsageTelemetry]::GetInstance().RegisterEvents();
        [RemoteReportsListener]::GetInstance().RegisterEvents();
        [WriteEnvironmentFile]::GetInstance().RegisterEvents();
		[WriteCAStatus]::GetInstance().RegisterEvents();
        [WriteFixControlFiles]::GetInstance().RegisterEvents();
        [SecurityRecommendationReport]::GetInstance().RegisterEvents();
        [GenericListener]::GetInstance().RegisterEvents();		
    }


    static [void] UnregisterListeners()
    {
		[WriteFolderPath]::GetInstance().UnregisterEvents();
        [WriteDetailedLog]::GetInstance().UnregisterEvents();
        [WriteSummaryFile]::GetInstance().UnregisterEvents();
        [WritePsConsole]::GetInstance().UnregisterEvents();
        [WriteDataFile]::GetInstance().UnregisterEvents();
		[OMSOutput]::GetInstance().UnregisterEvents();
        [EventHubOutput]::GetInstance().UnregisterEvents();
        [WebhookOutput]::GetInstance().UnregisterEvents();
		[AIOrgTelemetry]::GetInstance().UnregisterEvents();
        [UsageTelemetry]::GetInstance().UnregisterEvents();
        [RemoteReportsListener]::GetInstance().UnregisterEvents();
        [WriteEnvironmentFile]::GetInstance().UnregisterEvents();
		[WriteCAStatus]::GetInstance().UnregisterEvents();
        [WriteFixControlFiles]::GetInstance().UnregisterEvents();
        [SecurityRecommendationReport]::GetInstance().UnregisterEvents();
        [GenericListener]::GetInstance().UnregisterEvents();		
    }	
}
#[ListenerHelper]::RegisterListeners();
