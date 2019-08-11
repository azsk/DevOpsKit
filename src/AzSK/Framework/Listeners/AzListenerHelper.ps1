Set-StrictMode -Version Latest
#Class to register appropriate listeners based on environment
class AzListenerHelper : ListenerHelper
{
    static AzListenerHelper()
    {

     }

     static [void] RegisterListeners()
    {
        [ListenerHelper]:: RegisterListeners();
        [WriteCAStatus]::GetInstance().RegisterEvents();
        [AzResourceInventoryListener]::GetInstance().RegisterEvents();

    }

     static [void] UnregisterListeners()
    {
        [ListenerHelper]:: UnRegisterListeners();
        [ListenerHelper]:: RegisterListeners();
		[AzResourceInventoryListener]::GetInstance().UnRegisterEvents();
    }	
}