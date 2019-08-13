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
        [WriteCAStatus]::GetInstance().UnRegisterEvents();
        [AzResourceInventoryListener]::GetInstance().UnRegisterEvents();
    }	
}