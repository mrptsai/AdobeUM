function Import-PFXCert
{
    <#
    .SYNOPSIS
        Import a certificate with a private key from file

    .PARAMETER CertPwd
        Password to open PFX

    .PARAMETER CertPath
        Path to PFX File

    .NOTES
        If you hard-code the password in a script utilizing this function, you should ensure the script is itself, somewhere secure

    .EXAMPLE
        Import-PFXCert -CertPwd "ASDF" -CertPath "C:\Cert.pfx"
    #>

    Param
    (
        [string]$CertPwd,

        [ValidateScript({Test-Path -Path $_})]
        [Parameter(Mandatory=$true)]
        [string]$CertPath
    )

    $Collection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new() #Because I could not get the private key utilizing "cert:\etc\etc"
    $Collection.Import($CertPath, $CertPwd, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet)
    
    return $Collection[0]
}

function ConvertTo-Base64URL
{
    <#
    .SYNOPSIS
        Converts a byte[], to a Base64URL encoded string

    .PARAMETER Item
        A byte[]
    
    .EXAMPLE
        ConvertTo-Base64URL -Item "VGhpcyBpcyBhIHRlc3Q="
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        $Item
    )
    
    return [Convert]::ToBase64String($Item).Split("=")[0].Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-Base64URL
{
    <#
    .SYNOPSIS
        Converts a Base64Url string, to a decoded ASCII string

    .PARAMETER Item
        A base64url string
    
    .EXAMPLE
        ConvertFrom-Base64URL -Item "VGhpcyBpcyBhIHRlc3Q"
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$String
    )
    
    return [System.Text.ASCIIEncoding]::ASCII.GetString([convert]::FromBase64String((ConvertFrom-Base64URLToBase64 -String $String)))
}

function ConvertFrom-Base64URLToBase64
{
    
    <#
    .SYNOPSIS
        Converts a Base64Url string, to a .Net base64 string

    .PARAMETER Item
        A base64url string
    
    .EXAMPLE
        ConvertFrom-Base64URLToBase64 -Item "VGhpcyBpcyBhIHRlc3Q"
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$String
    )
    
    $String = $String.Replace('-', '+').Replace('_', '/')
    while ((($String.Length)*6)%8-ne 0)
    {
        $String = $String+"="
    }
    
    return $String
}

function ConvertTo-JavaTime
{
    <#
    .SYNOPSIS
        Converts the [datetime] object passed into a java compliant numerical representation. (milliseconds since 1/1/1970)

    .PARAMETER DateTimeObject
        A DateTime to be converted
    
    .EXAMPLE
        ConvertTo-JavaTime -DateTimeObject ([DateTime]::Now)
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        [DateTime]$DateTimeObject
    )
    
    # Take DateTime, convert to file time (100 nano second ticks since 1/1/1607). Subtract 1/1/1970 from that using the same 100nanoticks. Then multiply to convert from nanoticks to milliseconds since 1/1/1970. 
    return [int64](($DateTimeObject.ToFileTimeUtc()-[DateTime]::Parse("01/01/1970").ToFileTimeUtc())*0.0001)
}

function ConvertFrom-JavaTime
{
    <#
    .SYNOPSIS
        Converts the java compliant numerical representation of time to a .net [datetime] object.

    .PARAMETER JavaTime
        A JavaTime to be converted
    
    .EXAMPLE
        ConvertFrom-JavaTime -JavaTime 1500000000000
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        [int64]$JavaTime
    )
    
    # Take the javatime, multiply it by 10000 to convert from millisecond ticks to 100 nanosecond ticks. Then add the 100 nano second tickets since 1970 to that number. This gives us the current file time.
    # Then convert file time to [datetime] object
    return [DateTime]::FromFileTimeUtc($JavaTime*10000+[DateTime]::Parse("01/01/1970").ToFileTimeUtc())
}

function New-ClientInformation
{
    <#
    .SYNOPSIS
        Creates an object to contain client information such as service account details.

    .PARAMETER APIKey 
        Your service account's APIkey/ClientID as returned by https://console.adobe.io/

    .PARAMETER OrganizationID 
        Your OrganizationID as returned by https://console.adobe.io/

    .PARAMETER ClientSecret 
        Your service account's ClientSecret  as returned by https://console.adobe.io/

    .PARAMETER TechnicalAccountID 
        Your service account's TechnicalAccountID  as returned by https://console.adobe.io/

    .PARAMETER TechnicalAccountEmail 
        Your service account's TechnicalAccountEmail  as returned by https://console.adobe.io/

    .OUTPUTS
        ClientInformation object to be passed to further commands
    
    .EXAMPLE
        New-ClientInformation -APIKey "1111111111111222222333" -OrganizationID "22222222222222@AdobeOrg" -ClientSecret "xxxx-xxxx-xxxx-xxxx" -TechnicalAccountID "abcdf@techacct.adobe.com" -TechnicalAccountEmail "xxxx-xxxx-xxxx-xxxx@techacct.adobe.com"
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$APIKey, 

        [Parameter(Mandatory=$true)]
        [string]$OrganizationID, 

        [Parameter(Mandatory=$true)]
        [string]$ClientSecret,

        [Parameter(Mandatory=$true)]
        [string]$TechnicalAccountID,

        [Parameter(Mandatory=$true)]
        [string]$TechnicalAccountEmail
    )
    
    return New-Object -TypeName PSObject -ArgumentList @{
        APIKey = $APIKey; # ClientID
        ClientID = $APIKey; # Alias, adobe flip flops on what they call this
        OrgID = $OrganizationID;
        ClientSecret = $ClientSecret;
        TechnicalAccountID = $TechnicalAccountID;
        TechnicalAccountEmail = $TechnicalAccountEmail;
        Token=$null;
    }
}

function Get-AdobeAuthToken
{
    <#
    .SYNOPSIS
        Adds an adobe auth token to the ClientInformation object passed to it

    .PARAMETER ClientInformation 
        Your ClientInformation object

    .PARAMETER SignatureCert 
        The cert that is attached to the specified account. Must have private key. Check which cert at https://console.adobe.io/

    .PARAMETER AuthTokenURI 
        URI of the Adobe Auth Service. Defaults to https://ims-na1.adobelogin.com/ims/exchange/jwt/

    .PARAMETER ExpirationInHours 
        When the request token should expire in hours. Defaults to 1

    .OUTPUTS
        Attached auth token to ClientInformation.Token

    .NOTES
        Create JWT https://www.adobe.io/apis/cloudplatform/console/authentication/createjwt/jwt_nodeJS.html
        https://github.com/lambtron/nextbus/blob/master/node_modules/jwt-simple/lib/jwt.js
        https://jwt.io/
    
    .EXAMPLE
        Get-AdobeAuthToken -ClientInformation $MyClient -SignatureCert $Cert -ExpirationInHours 12
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        $ClientInformation,
        
        [ValidateScript({$null -ne $_.PrivateKey})] 
        [Parameter(Mandatory=$true)]
        $SignatureCert, 
        
        [string]$AuthTokenURI="https://ims-na1.adobelogin.com/ims/exchange/jwt/", 
        
        [int]$ExpirationInHours=1
    )

    $PayLoad = New-Object -TypeName PSObject -Property @{
        iss=$ClientInformation.OrgID;
        sub=$ClientInformation.TechnicalAccountID;
        aud="https://ims-na1.adobelogin.com/c/"+$ClientInformation.APIKey;
        "https://ims-na1.adobelogin.com/s/ent_user_sdk"=$true;#MetaScope
        exp=(ConvertTo-JavaTime -DateTimeObject ([DateTime]::Now.AddHours($ExpirationInHours)));
    }

    # Header for the JWT
    $Header = ConvertTo-Json -InputObject (New-Object PSObject -Property @{typ="JWT";"alg"="RS256"}) -Compress

    # Body of the JWT. This is our actual request
    $JWT = ConvertTo-Base64URL -Item ([System.Text.ASCIIEncoding]::ASCII.GetBytes((ConvertTo-Json -InputObject $PayLoad -Compress)))

    # Join them together. as base64 strings, with a "." between them
    $JWT = (ConvertTo-Base64URL -Item ([System.Text.ASCIIEncoding]::ASCII.GetBytes($Header)))+"."+$JWT

    # Sign the data
    $JWTSig = ConvertTo-Base64URL -Item ($SignatureCert.PrivateKey.SignData([System.Text.ASCIIEncoding]::UTF8.GetBytes($JWT), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1))

    # Append the signature. This is now a complete JWT
    $JWT = $JWT+"."+$JWTSig

    # Now we request the auth token
    $Body = "client_id=$($ClientInformation.APIKey)&client_secret=$($ClientInformation.ClientSecret)&jwt_token=$JWT"
    $ClientInformation.Token = Invoke-RestMethod -Method Post -Uri $AuthTokenURI -Body $Body -ContentType "application/x-www-form-urlencoded"
}

function Get-AdobeUsers
{
    <#
    .SYNOPSIS
        Gets all users from the adobe API

    .PARAMETER ClientInformation 
        Your ClientInformation object

    .PARAMETER UM_Server 
        The adobe user management uri. Defaults to "https://usermanagement.adobe.io/v2/usermanagement/"

    .NOTES
        https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplequery.html
    
    .EXAMPLE
        Get-AdobeUsers -ClientInformation $MyClient
    #>

    Param
    (
        [string]$UM_Server="https://usermanagement.adobe.io/v2/usermanagement/", 
        
        [ValidateScript({$null -ne $_.Token})]
        [Parameter(Mandatory=$true)]$ClientInformation
    )

    #Store the results here
    $Results = @()

    # URI of the query endpoint
    $URIPrefix = "$UM_Server$($ClientInformation.OrgID)/users?page="
    $Page =0

    # Request headers
    $Headers = @{
        Accept="application/json";
        "Content-Type"="application/json";
        "x-api-key"=$ClientInformation.APIKey;
        Authorization="Bearer $($ClientInformation.Token.access_token)"
    }

    # Query, looping through each page, until we have all users.
    while($true)
    {
        $QueryResponse = Invoke-RestMethod -Method Get -Uri ($URIPrefix+$Page.ToString()) -Header $Headers
        # Currently not required, but other queries will just keep dumping the same users as you loop though pages
        
        if ($null -ne $Results -and $QueryResponse[0].id -in $Results.id)
        {
            break;
        }
        
        $Results += $QueryResponse
        $Page++;
        
        # Different API endpoints have different ways of telling you if you are done.
        if ($QueryResponse.lastPage -eq $true -or $null -ne $QueryResponse -or $QueryResponse.Length -eq 0)
        {
            break; 
        }
    }

    return $Results
}

function Get-AdobeGroups
{
    <#
    .SYNOPSIS
        Grab a list of all groups, or if provided an ID, returns the group related to the ID

    .PARAMETER ClientInformation 
        Your ClientInformation object

    .PARAMETER UM_Server 
        The adobe user management uri. Defaults to "https://usermanagement.adobe.io/v2/usermanagement/"

    .PARAMETER GroupID
        If you wish to query for a single group instead, put the group ID here

    .NOTES
        https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplequery.html
    
    .EXAMPLE
        Get-AdobeGroups -ClientInformation $MyClient

    .EXAMPLE
        Get-AdobeGroups -ClientInformation $MyClient -GroupID "222242"
    #>

    Param
    (
        [string]$UM_Server="https://usermanagement.adobe.io/v2/usermanagement/",
        
        $GroupID=$null,
        
        [ValidateScript({$null -ne $_.Token})]
        [Parameter(Mandatory=$true)]$ClientInformation
    )

    #See https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplequery.html
    $Results = @()
    
    if ($null -eq $GroupID)
    {
        $URIPrefix = "$UM_SERVER$($ClientInformation.OrgID)/user-groups?page="
    } else
    {
        $URIPrefix = "$UM_SERVER$($ClientInformation.OrgID)/user-groups/$GroupID"
    }
    
    $Page =0

    # Request headers
    $Headers = @{Accept="application/json";
            "Content-Type"="application/json";
            "x-api-key"=$ClientInformation.APIKey;
            Authorization="Bearer $($ClientInformation.Token.access_token)"}
    if ($null -eq $GroupID)
    {
        while($true)
        {
            $QueryResponse = Invoke-RestMethod -Method Get -Uri ($URIPrefix+$Page.ToString()) -Header $Headers
            if ($null -ne $Results -and $QueryResponse[0].groupId -in $Results.groupId)
            {
                break; #Why you ask? Because Adobe will just return any results they can anyway! If you have 1 page of results, and you ask for page 4, do they error? Noooo. Do they say last page? Nooo!
            }
            $Results += $QueryResponse
            $Page++;
            if ($QueryResponse.lastPage -eq $true -or $null -ne $QueryResponse -or $QueryResponse.Length -eq 0)
            {
                break
            }
        }
    } else
    {
        $Results = Invoke-RestMethod -Method Get -Uri $URIPrefix -Header $Headers
    }

    return $Results
}

function Get-AdobeGroupMembers
{
    <#
    .SYNOPSIS
        Grab all members of the specified group

    .PARAMETER ClientInformation 
        Your ClientInformation object

    .PARAMETER UM_Server 
        The adobe user management uri. Defaults to "https://usermanagement.adobe.io/v2/usermanagement/"

    .PARAMETER GroupID
        The ID of the group to query

    .NOTES
        https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplequery.html
    
    .EXAMPLE
        Get-AdobeGroupMembers -ClientInformation $MyClient -GroupID "222424"
    #>

    Param
    (
        [string]$UM_Server="https://usermanagement.adobe.io/v2/usermanagement/",

        [ValidateScript({$null -ne $_.Token})]
        [Parameter(Mandatory=$true)]
        $ClientInformation, 

        [Parameter(Mandatory=$true)]
        [string]$GroupID
    )

    #See https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplequery.html
    $Results = @()

    $URIPrefix = "$UM_SERVER$($ClientInformation.OrgID)/user-groups/$GroupID/users?page="
    $Page =0

    # Request headers
    $Headers = @{Accept="application/json";
            "Content-Type"="application/json";
            "x-api-key"=$ClientInformation.APIKey;
            Authorization="Bearer $($ClientInformation.Token.access_token)"}

    while($true)
    {
        $QueryResponse = Invoke-RestMethod -Method Get -Uri ($URIPrefix) -Header $Headers
        if ($null -ne $Results -and $QueryResponse[0].id -in $Results.id)
        {
            break; #Why you ask? Because Adobe will just return any results they can anyway! If you have 1 page of results, and you ask for page 4, do they error? Noooo. Do they say last page? Nooo!
        }
        $Results += $QueryResponse
        $Page++;
        if ($QueryResponse.lastPage -eq $true -or $null -eq $QueryResponse -or $QueryResponse.Length -eq 0)
        {
            break
        }
    }

    return $Results
}

function Get-AdobeGroupAdmins
{
    <#
    .SYNOPSIS
        Grab all admins of the specified group

    .PARAMETER ClientInformation 
        Your ClientInformation object

    .PARAMETER UM_Server 
        The adobe user management uri. Defaults to "https://usermanagement.adobe.io/v2/usermanagement/"

    .PARAMETER GroupID
        The ID of the group to query

    .NOTES
        https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplequery.html
    
    .EXAMPLE
        Get-AdobeGroupAdmins -ClientInformation $MyClient -GroupID "222424"
    #>

    Param
    (
        $UM_Server="https://usermanagement.adobe.io/v2/usermanagement/",

        [ValidateScript({$null -ne $_.Token})]
        [Parameter(Mandatory=$true)]
        $ClientInformation, 
        
        [Parameter(Mandatory=$true)]
        [string]$GroupID
    )

    #See https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplequery.html
    $Results = @()

    $URIPrefix = "$UM_SERVER$($ClientInformation.OrgID)/user-groups/$GroupID/admins?page="
    $Page =0

    # Request headers
    $Headers = @{Accept="application/json";
            "Content-Type"="application/json";
            "x-api-key"=$ClientInformation.APIKey;
            Authorization="Bearer $($ClientInformation.Token.access_token)"}

    while($true)
    {
        $QueryResponse = Invoke-RestMethod -Method Get -Uri ($URIPrefix) -Header $Headers
        if ($null -ne $Results -and $QueryResponse[0].id -in $Results.id)
        {
            break; #Why you ask? Because Adobe will just return any results they can anyway! If you have 1 page of results, and you ask for page 4, do they error? Noooo. Do they say last page? Nooo!
        }

        $Results += $QueryResponse
        $Page++;
        
        if ($QueryResponse.lastPage -eq $true -or $null -eq $QueryResponse -or $QueryResponse.Length -eq 0)
        {
            break
        }
    }

    return $Results
}

function New-CreateUserRequest
{
    <#
    .SYNOPSIS
        Creates a "CreateUserRequest" object. This object can then be converted to JSON and sent to create a new user

    .PARAMETER FirstName
        User's First name

    .PARAMETER LastName
        User's Last Name

    .PARAMETER Email
        User's Email and ID

    .PARAMETER Country
        Defaults to AU. This cannot be changed later. (Per adobe documentation)

    .PARAMETER AdditionalActions
        An array of additional actions to add to the request. (Like add to group)

    .NOTES
        See https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplemultiaction.html
        This should be posted to https://usermanagement.adobe.io/v2/usermanagement/action/{myOrgID}
    
    .EXAMPLE
        New-CreateUserRequest -FirstName "John" -LastName "Doe" -Email "John.Doe@domain.com"
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$FirstName,

        [Parameter(Mandatory=$true)]
        [string]$LastName, 

        [Parameter(Mandatory=$true)]
        [string]$Email, 

        [string]$Country="AU", 

        $AdditionalActions=@()
    )

    # Parameters to create a new federatedID
    $FederatedIDParameters = New-Object -TypeName PSObject -Property @{email=$Email;country=$Country;firstname=$FirstName;lastname=$LastName}

    # Federated ID creation action
    $FederatedIDAction = New-Object -TypeName PSObject -Property @{createFederatedID=$FederatedIDParameters}

    # Add any additional actions
    $AdditionalActions = @()+ $FederatedIDAction + $AdditionalActions

    # Return the new request
    return (New-Object -TypeName PSObject -Property @{user=$Email;do=@()+$AdditionalActions})
}

function New-RemoveUserRequest
{
    <#
    .SYNOPSIS
        Creates a "RemoveUserRequest" object. This object can then be converted to JSON and sent to remove a user frin adibe

    .PARAMETER UserName
        User's ID, usually e-mail

    .PARAMETER AdditionalActions
        An array of additional actions to add to the request. (Like add to group)

    .NOTES
        See https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplemultiaction.html
        This should be posted to https://usermanagement.adobe.io/v2/usermanagement/action/{myOrgID}
    
    .EXAMPLE
        New-RemoveUserRequest -UserName "john.doe@domain.com"
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$UserName, 
        
        $AdditionalActions=@()
    )

    $RemoveAction = New-Object -TypeName PSObject -Property @{removeFromOrg=(New-Object -TypeName PSObject)}

    $AdditionalActions = @() + $RemoveAction + $AdditionalActions

    return (New-Object -TypeName PSObject -Property @{user=$UserName;do=@()+$AdditionalActions})
}

function New-UpdateUserRequest
{
    <#
    .SYNOPSIS
        Creates a "UpdateUserRequest" object. This object can then be converted to JSON and sent to update an existing user

    .PARAMETER UserName
        User's ID, usually e-mail

    .PARAMETER AdditionalActions
        An array of additional actions to add to the request. (Like add to group)

    .NOTES
        See https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplemultiaction.html
        This should be posted to https://usermanagement.adobe.io/v2/usermanagement/action/{myOrgID}
    
    .EXAMPLE
        New-UpdateUserRequest -FirstName "John" -LastName "Doe" -Email "John.Doe@domain.com"
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$UserName, 
        
        $AdditionalActions=@()
    )

    $UpdateAction = New-Object -TypeName PSObject -Property @{update=(New-Object -TypeName PSObject)}

    # Add any additional actions
    $AdditionalActions = @()+ $UpdateAction + $AdditionalActions

    # Return the new request"
    return (New-Object -TypeName PSObject -Property @{user=$UserName;do=@()+$AdditionalActions})
}

function New-RemoveUserFromGroupRequest
{
    <#
    .SYNOPSIS
        Creates a request to remove a user from an Adobe group. This will need to be posted after being converted to a JSON

    .PARAMETER UserName
        User's ID, usually e-mail

    .PARAMETER GroupName
        Name of the group to remove the user from

    .NOTES
        See https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplemultiaction.html
        This should be posted to https://usermanagement.adobe.io/v2/usermanagement/action/{myOrgID}
    
    .EXAMPLE
        New-RemoveUserFromGroupRequest -UserName "john.doe@domain.com" -GroupName "My User Group"
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$UserName,
        
        [Parameter(Mandatory=$true)]
        $GroupName
    )

    $RemoveMemberAction = New-GroupUserRemoveAction -Groups $GroupName

    return (New-Object -TypeName PSObject -Property @{user=$UserName;do=@()+$RemoveMemberAction})
}

function New-GroupUserAddAction
{
    <#
    .SYNOPSIS
        Creates a "Add to group" action. Actions fall under requests. This will have to be added to a request, then json'd and submitted to adobe's API

    .PARAMETER Groups
        An array of groups that something should be added to

    .NOTES
        See https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplemultiaction.html
        This should be posted to https://usermanagement.adobe.io/v2/usermanagement/action/{myOrgID}
    
    .EXAMPLE
        New-GroupUserAddAction -Groups "My User Group"
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        $Groups
    )

    $Params = New-Object -TypeName PSObject -Property @{group=@()+$Groups}

    return (New-Object -TypeName PSObject -Property @{add=$Params})
}

function New-GroupUserRemoveAction
{
    <#
    .SYNOPSIS
        Creates a "Remove from group" action. Actions fall under requests. This will have to be added to a request, then json'd and submitted to adobe's API

    .PARAMETER Groups
        An array of groups that something should be removed from

    .NOTES
        See https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplemultiaction.html
        This should be posted to https://usermanagement.adobe.io/v2/usermanagement/action/{myOrgID}
    
    .EXAMPLE
        New-GroupUserRemoveAction -Groups "My User Group"
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        $Groups
    )

    $Params = New-Object -TypeName PSObject -Property @{usergroup=@()+$Groups}

    return (New-Object -TypeName PSObject -Property @{remove=$Params})
}

function New-AddToGroupRequest
{
    <#
    .SYNOPSIS
        Creates a "Add user to group" request. This will need to be json'd and sent to adobe

    .PARAMETER Groups
        An array of groups that something should be added to

    .PARAMETER User
        A User to be added to the Group(s)

    .NOTES
        See https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplemultiaction.html
        This should be posted to https://usermanagement.adobe.io/v2/usermanagement/action/{myOrgID}
    
    .EXAMPLE
        New-AddToGroupRequest -Groups "My User Group" -User "John.Doe@domain.com"
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$User,

        [Parameter(Mandatory=$true)]
        $Groups
    )

    $GroupAddAction = New-GroupUserAddAction -GroupNames $Groups
    
    return (New-Object -TypeName PSObject -Property @{user=$User;do=@()+$GroupAddAction})
}

function New-RemoveFromGroupRequest
{
    <#
    .SYNOPSIS
        Creates a "Remove user from group" request. This will need to be json'd and sent to adobe

    .PARAMETER Groups
        An array of groups that something should be removed from
    
    .PARAMETER User
        A User to be removed from the Group(s)

    .NOTES
        See https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplemultiaction.html
        This should be posted to https://usermanagement.adobe.io/v2/usermanagement/action/{myOrgID}
    
    .EXAMPLE
        New-RemoveFromGroupRequest -Groups "My User Group" -User "John.Doe@domain.com"
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$User, 

        [Parameter(Mandatory=$true)]
        $Groups
    )

    $GroupRemoveAction = Create-GroupRemoveAction -GroupNames $Groups
    
    return (New-Object -TypeName PSObject -Property @{user=$User;do=@()+$GroupRemoveAction})
}

function Expand-JWTInformation
{
    <#
    .SYNOPSIS
        Unpacks a JWT object into it's header, and body components. (Human readable format)

    .PARAMETER JWTObject
        JWT To unpack. In format of {Base64Header}.{Base64Body}.{Base64Signature}

    .PARAMETER SigningCert
        A certificate with the necesary public key to verify signature block. Can be null, will not validate signature.

    .NOTES
        See https://www.adobe.io/apis/cloudplatform/usermanagement/docs/samples/samplemultiaction.html
        This should be posted to https://usermanagement.adobe.io/v2/usermanagement/action/{myOrgID}
    
    .EXAMPLE
        Expand-JWTInformation -JWTObject "xxxx.xxxx.xxx"
    #>

    Param
    (
        [ValidateScript({$_.Split(".").Length -eq 3})]
        [Parameter(Mandatory=$true)][string]$JWTObject,

        $SigningCert
    )

    $JWTParts = $JWTObject.Split(".")
    $Header =(ConvertFrom-Json -InputObject (ConvertFrom-Base64URL -String $JWTParts[0]));
    $RawData = [System.Text.ASCIIEncoding]::ASCII.GetBytes($JWTParts[0]+"."+$JWTParts[1])

    $Signature = [System.Convert]::FromBase64String((ConvertFrom-Base64URLToBase64 -String $JWTParts[2]))

    $Valid= $null
    if ($SigningCert -and $Header.alg.StartsWith("RS"))
    {
        $HAN=$null
        if ($Header.alg.EndsWith("256"))
        {
            $HAN = [System.Security.Cryptography.HashAlgorithmName]::SHA256
        } elseif ($Header.alg.EndsWith("512"))
        {
            $Han = [System.Security.Cryptography.HashAlgorithmName]::SHA512
        } elseif ($Header.alg.EndsWith("384"))
        {
            $Han = [System.Security.Cryptography.HashAlgorithmName]::SHA384
        }

        if ($HAN)
        {
            $Valid = $SigningCert.PublicKey.Key.VerifyData($RawData, $Signature, $Han, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        }
    }

    return (New-Object -TypeName PSObject -ArgumentList @{
        Header=$Header;
        Body=(ConvertFrom-Json -InputObject (ConvertFrom-Base64URL -String $JWTParts[1]));
        SignatureValid=$Valid
    })
}

function Send-UserManagementRequest
{
    <#
    .SYNOPSIS
        Sends a request, or array of requests, to adobe's user management endpoint

    .PARAMETER ClientInformation
        ClientInformation object containing service account info and token

    .PARAMETER Requests
        An array of requests to send to adobe

    .NOTES
        See the Create-*Request
    
    .EXAMPLE
        Send-UserManagementRequest -ClientInformation $MyClientInfo -Requests (New-CreateUserRequest -FirstName "John" -LastName "Doe" -Email "john.doe@domain.com" -Country="AU")
    #>

    Param
    (
        [ValidateScript({$null -ne $_.Token})]
        [Parameter(Mandatory=$true)]$ClientInformation,

        $Requests
    )
    
    # Ensure is array
    $Request = @()+$Requests
    $Request = ConvertTo-Json -InputObject $Request -Depth 10 -Compress

    $URI = "https://usermanagement.adobe.io/v2/usermanagement/action/$($ClientInformation.OrgID)"
    $Headers = @{Accept="application/json";
            "Content-Type"="application/json";
            "x-api-key"=$ClientInformation.APIKey;
            Authorization="Bearer $($ClientInformation.Token.access_token)"}

    return (Invoke-RestMethod -Method Post -Uri $URI -Body $Request -Header $Headers)
}

function New-SyncADGroupRequest
{
    <#
    .SYNOPSIS
        Creates an array of requests that, when considered together, ensures an Adobe group will mirror an AD group

    .PARAMETER ADGroupID
        Active Directory Group Identifier. The source group to mirror to adobe

    .PARAMETER AdobeGroupID
        Adobe group ID as retured from Get-AdobeGroups

    .PARAMETER ClientInformation
        Service account information including token
    
    .EXAMPLE
        New-SyncADGroupRequest -ADGroupID "SG-My-Approved-Adobe-Users" -AdobeGroupID "111222422" -ClientInformation $MyClientInfo
    #>

    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$ADGroupID,

        [Parameter(Mandatory=$true)]
        [string]$AdobeGroupID, 

        [ValidateScript({$null -ne $_.Token})]
        [Parameter(Mandatory=$true)]$ClientInformation
    )

    # Grab a list of all adobe groups
    $AdobeGroupInfo = Get-AdobeGroups -GroupID $AdobeGroupID -ClientInformation $ClientInformation
    
    # Grab a list of users in the Active Directory group
    $ADGroupMembers = Get-AzureADGroup -SearchString $ADGroupID | Get-AzureADGroupMember
    
    # Get extended property data on all users. (So we can get e-mail)
    $ADUsers = @()
    foreach ($ADGroupMember in $ADGroupMembers)
    {
        $ADUsers += Get-AzureADUser -ObjectID $ADGroupMember.ObjectId
    }

    # Grab a list of users from the adobe group
    $Members = (Get-AdobeGroupMembers -ClientInformation $ClientInformation -GroupID $AdobeGroupID).username
    $FederatedIDs = Get-AdobeUsers -ClientInformation $ClientInformation | Where-Object userType -eq federatedID

    #Results
    $Request = @()

    # Find missing users, and create requests to add them to adobe
    foreach ($ADUser in $ADUsers)
    {
        #If adobe group does not contain ad user
        if ($Members.Length -le 0 -or $ADUser.mail -notin $Members)
        {
            $AddToGroup = New-GroupUserAddAction -Groups $AdobeGroupInfo.name
            #Need to add
            if ($ADUser.mail -in $FederatedIDs.email)
            {
                $Request += New-UpdateUserRequest -UserName $ADUser.mail -AdditionalActions $AddToGroup
            } else {
                $Request += New-CreateUserRequest -FirstName $ADUser.GivenName -LastName $ADUser.SurName -Email $ADUser.mail -Country "AU" -AdditionalActions $AddToGroup
            }
        }
    }
    
    # Find excess members and create requests to remove them
    foreach ($Member in $Members)
    {
        if ($null -ne $ADUsers -or $Member -notin $ADUsers.mail)
        {
            #Need to remove
            $Request += New-RemoveUserFromGroupRequest -UserName $Member -GroupName $AdobeGroupInfo.name
        }
    }
    
    # return our list of requests
    return $Request
}

function New-RemoveUnusedAbobeUsersRequest
{
    <#
    .SYNOPSIS
        Creates an array of requests that, when considered together, removes all users that are not admins, and not part of any user groups

    .PARAMETER ClientInformation
        Service account information including token
    
    .EXAMPLE
        New-RemoveUnusedAbobeUsersRequest -ClientInformation $MyClientInfo
    #>

    Param
    (
        [ValidateScript({$null -ne $_.Token})]
        [Parameter(Mandatory=$true)]
        $ClientInformation
    )

    $AdobeUsers = Get-AdobeUsers -ClientInformation $ClientInformation
    
    $Requests = @()
    foreach ($User in $AdobeUsers)
    {
        if (($null -eq $User.groups -or $User.groups.length -eq 0) -and 
            ($null -eq $User.adminRoles -or $User.adminRoles.length -eq 0))
        {
            #Account not used
            $Requests += New-RemoveUserRequest -UserName $User.username
        }
    }

    return $Requests
}

Export-ModuleMember -Function @(
    'Import-PFXCert', 
    'ConvertTo-Base64URL', 
    'ConvertFrom-Base64URL', 
    'ConvertFrom-Base64URLToBase64', 
    'ConvertTo-JavaTime', 
    'New-ClientInformation', 
    'Get-AdobeAuthToken', 
    'Get-AdobeUsers', 
    'Get-AdobeGroups', 
    'Get-AdobeGroupMembers', 
    'Get-AdobeGroupAdmins', 
    'New-CreateUserRequest', 
    'New-RemoveUserRequest',
    'New-UpdateUserRequest',
    'New-RemoveUserFromGroupRequest',
    'New-GroupUserAddAction',
    'New-GroupUserRemoveAction',
    'New-AddToGroupRequest',
    'New-RemoveFromGroupRequest',
    'Expand-JWTInformation',
    'Send-UserManagementRequest',
    'New-SyncADGroupRequest',
    'New-RemoveUnusedAbobeUsersRequest'
)