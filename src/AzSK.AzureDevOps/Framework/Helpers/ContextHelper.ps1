<#
.Description
# Context class for indenity details. 
# Provides functionality to login, create context, get token for api calls
#>
using namespace Microsoft.IdentityModel.Clients.ActiveDirectory

class ContextHelper {
    
    static hidden [Context] $currentContext;

    hidden static [PSObject] GetCurrentContext()
    {
        return [ContextHelper]::GetCurrentContext($false);
    }

    hidden static [PSObject] GetCurrentContext([bool]$bRefresh)
    {
        if( (-not [ContextHelper]::currentContext) -or $bRefresh)
        {
            $clientId = [Constants]::DefaultClientId ;          
            $replyUri = [Constants]::DefaultReplyUri; 
            $azureDevOpsResourceId = [Constants]::DefaultAzureDevOpsResourceId;
            [AuthenticationContext] $ctx = $null;

            $ctx = [AuthenticationContext]::new("https://login.windows.net/common");

            [AuthenticationResult] $result = $null;

            $azSKUI = $null;
            if ( !$bRefresh -and ($azSKUI = Get-Variable 'AzSKADOLoginUI' -Scope Global -ErrorAction 'Ignore')) {
                if ($azSKUI.Value -eq 1) {
                    $result = $ctx.AcquireToken($azureDevOpsResourceId, $clientId, [Uri]::new($replyUri),[PromptBehavior]::Always);
                }
                else {
                    $result = $ctx.AcquireToken($azureDevOpsResourceId, $clientId, [Uri]::new($replyUri),[PromptBehavior]::Auto);
                }
            }
            else {
                $result = $ctx.AcquireToken($azureDevOpsResourceId, $clientId, [Uri]::new($replyUri),[PromptBehavior]::Auto);
            }

            [ContextHelper]::ConvertToContextObject($result)
        }
        return [ContextHelper]::currentContext
    }
    
    hidden static [PSObject] GetCurrentContext([System.Security.SecureString] $PATToken)
    {
        if(-not [ContextHelper]::currentContext)
        {
            [ContextHelper]::ConvertToContextObject($PATToken)
        }
        return [ContextHelper]::currentContext
    }

    static [string] GetAccessToken([string] $resourceAppIdUri) {
            return [ContextHelper]::GetAccessToken()   
    }

    static [string] GetAccessToken()
    {
        # TODO: Handlle login
        if([ContextHelper]::currentContext)
        {
            #if token expiry is within 2 min, refresh.
            if ([ContextHelper]::currentContext.TokenExpireTimeLocal -le [DateTime]::Now.AddMinutes(2))
            {
                [ContextHelper]::GetCurrentContext($true);
            }
            #ConvertFrom-SecureString
            return  [ContextHelper]::currentContext.AccessToken
        }
        else
        {
            return $null
        }
    }

    hidden [SubscriptionContext] SetContext([string] $subscriptionId)
    {
        if((-not [string]::IsNullOrEmpty($subscriptionId)))
              {
                     $SubscriptionContext = [SubscriptionContext]@{
                           SubscriptionId = $subscriptionId;
                           Scope = "/Organization/$subscriptionId";
                           SubscriptionName = $subscriptionId;
                     };
                     [ContextHelper]::GetCurrentContext()                  
              }
              else
              {
                     throw [SuppressedException] ("OrganizationName name [$subscriptionId] is either malformed or incorrect.")
        }
        return $SubscriptionContext;
    }

    hidden [SubscriptionContext] SetContext([string] $subscriptionId, [System.Security.SecureString] $PATToken)
    {
        if((-not [string]::IsNullOrEmpty($subscriptionId)))
              {
                     $SubscriptionContext = [SubscriptionContext]@{
                           SubscriptionId = $subscriptionId;
                           Scope = "/Organization/$subscriptionId";
                           SubscriptionName = $subscriptionId;
                     };
                     [ContextHelper]::GetCurrentContext($PATToken)         
              }
              else
              {
                     throw [SuppressedException] ("OrganizationName name [$subscriptionId] is either malformed or incorrect.")
        }
        return $SubscriptionContext;
    }

    static [void] ResetCurrentContext()
    {
        
    }

    hidden static ConvertToContextObject([PSObject] $context)
    {
        $contextObj = [Context]::new()
        $contextObj.Account.Id = $context.UserInfo.DisplayableId
        $contextObj.Tenant.Id = $context.TenantId 
        $contextObj.AccessToken = $context.AccessToken
        $contextObj.TokenExpireTimeLocal = $context.ExpiresOn.LocalDateTime
        #$contextObj.AccessToken =  ConvertTo-SecureString -String $context.AccessToken -asplaintext -Force
        [ContextHelper]::currentContext = $contextObj
    }

    hidden static ConvertToContextObject([System.Security.SecureString] $patToken)
    {
        $contextObj = [Context]::new()
        $contextObj.Account.Id = [string]::Empty
        $contextObj.Tenant.Id =  [string]::Empty
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($patToken)
        $contextObj.AccessToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        #$contextObj.AccessToken = $patToken
        #$contextObj.AccessToken =  ConvertTo-SecureString -String $context.AccessToken -asplaintext -Force
        [ContextHelper]::currentContext = $contextObj
    }

    static [string] GetCurrentSessionUser() {
        $context = [ContextHelper]::GetCurrentContext()
        if ($null -ne $context) {
            return $context.Account.Id
        }
        else {
            return "NO_ACTIVE_SESSION"
        }
    }
}