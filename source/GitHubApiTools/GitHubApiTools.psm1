
################
# Global settings
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

<#
#>
Function Invoke-GithubApi
{
    [CmdletBinding(DefaultParameterSetName="Content")]
    param(
        [Parameter(Mandatory=$false,ParameterSetName="Content")]
        [Parameter(Mandatory=$false,ParameterSetName="File")]
        [ValidateNotNullOrEmpty()]
        [string]$ApiBase = "https://api.github.com",

        [Parameter(Mandatory=$false,ParameterSetName="Content")]
        [Parameter(Mandatory=$false,ParameterSetName="File")]
        [ValidateNotNullOrEmpty()]
        [string]$Method = "GET",

        [Parameter(Mandatory=$true,ParameterSetName="Content")]
        [Parameter(Mandatory=$true,ParameterSetName="File")]
        [ValidateNotNullOrEmpty()]
        [string]$RequestUri,

        [Parameter(Mandatory=$false,ParameterSetName="Content")]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Body,

        [Parameter(Mandatory=$true,ParameterSetName="File")]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory=$true,ParameterSetName="Content")]
        [Parameter(Mandatory=$true,ParameterSetName="File")]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [Parameter(Mandatory=$false,ParameterSetName="Content")]
        [Parameter(Mandatory=$true,ParameterSetName="File")]
        [ValidateNotNullOrEmpty()]
        [string]$ContentType = "application/json"
    )

    process
    {
        # Build the URI for the request
        $uri = $ApiBase

        if (!$RequestUri.StartsWith("/"))
        {
            $uri += "/"
        }

        $uri += $RequestUri

        # Build parameters for passing to Invoke-WebRequest
        $webParams = @{
            Headers = @{
                Authorization = "token XXXX"
                Accept = "application/vnd.github.v3+json"
            }
            UseBasicParsing = $true
            Uri = $uri
            ContentType = $ContentType
            Method = $Method
        }

        # Add the body, if it contains content. Allows null body to be passed
        if (![string]::IsNullOrEmpty($Body))
        {
            $webParams["Body"] = $Body
        }

        # Add the file, if it as been specified
        if (![string]::IsNullOrEmpty($FilePath))
        {
            $webParams["InFile"] = (Get-Item $FilePath).FullName
        }

        # Display sanitised version of the web request
        Write-Verbose ("Request parameters: " + ($webParams | ConvertTo-Json))
        $webParams["Headers"]["Authorization"] = "token $Token"

        # Actual request
        $result = Invoke-WebRequest @webParams

        Write-Verbose ("API Response: " + $result)

        $result.Content | ConvertFrom-Json
    }
}

<#
#>
Function Add-GithubReleaseAsset
{
    [CmdletBinding(SupportsShouldProcess,DefaultParameterSetName="File")]
    param(
        [Parameter(Mandatory=$true,ParameterSetName="Content")]
        [Parameter(Mandatory=$true,ParameterSetName="File")]
        [ValidateNotNullOrEmpty()]
        [string]$Owner,

        [Parameter(Mandatory=$true,ParameterSetName="Content")]
        [Parameter(Mandatory=$true,ParameterSetName="File")]
        [ValidateNotNullOrEmpty()]
        [string]$Repo,

        [Parameter(Mandatory=$true,ParameterSetName="Content")]
        [Parameter(Mandatory=$true,ParameterSetName="File")]
        [ValidateNotNull()]
        [int]$ReleaseId,

        [Parameter(Mandatory=$true,ParameterSetName="Content")]
        [Parameter(Mandatory=$false,ParameterSetName="File")]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory=$false,ParameterSetName="Content")]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Content,

        [Parameter(Mandatory=$false,ParameterSetName="File",ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory=$true,ParameterSetName="Content")]
        [Parameter(Mandatory=$true,ParameterSetName="File")]
        [ValidateNotNullOrEmpty()]
        [string]$Token
    )

    process
    {
        # Build API parameters
        $apiParams = @{
            ApiBase = "https://uploads.github.com"
            Method = "POST"
            Token = $Token
            ContentType = "application/octet-stream"
        }

        switch ($PSCmdlet.ParameterSetName)
        {
            "Content" {
                # Make sure content is at least an empty string
                if ($null -eq $Content)
                {
                    $Content = ""
                }

                $apiParams["Body"] = $Content
                break
            }

            "File" {
                if (!(Test-Path -PathType Leaf $FilePath))
                {
                    Write-Error "Path $FilePath does not exist or is not a file"
                    return
                }

                # Update Name, if not supplied
                if ($PSBoundParameters.Keys -notcontains "Name")
                {
                    $Name = (Get-Item $FilePath).Name
                }

                $apiParams["FilePath"] = (Get-Item $FilePath).FullName

                break
            }

            default {
                Write-Error "Unknown parameter set name"
            }
        }

        # Build request URI, including the name, derived from file or supplied
        $apiParams["RequestUri"] = ("/repos/{0}/{1}/releases/{2}/assets?name={3}" -f $Owner, $Repo, $ReleaseId, $Name)

        # Pass request to Invoke-GithubApi
        if ($PSCmdlet.ShouldProcess($Name, "Add Release Asset"))
        {
            Invoke-GithubApi @apiParams
        }
    }
}

<#
#>
Function New-GithubRelease
{
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Owner,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Repo,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TagName,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Commitish,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [bool]$Draft = $false,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [bool]$Prerelease = $false,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Token
    )

    process
    {
        # Add base parameters for request
        $content = @{
            tag_name = $TagName
            name = $Name
            draft = $Draft
            prerelease = $Prerelease
        }

        # Add commitish, if supplied
        if ($PSBoundParameters.Keys -contains "Commitish")
        {
            $content["commitish"] = $Commitish
        }

        # Build API parameters
        $apiParams = @{
            Method = "POST"
            RequestUri = ("/repos/{0}/{1}/releases" -f $Owner, $Repo)
            Body = ([PSCustomObject]$content | ConvertTo-Json)
            Token = $Token
        }

        if ($PSCmdlet.ShouldProcess($TagName, "Create Release"))
        {
            Invoke-GithubApi @apiParams
        }
    }
}

<#
#>
Function Get-GithubRelease
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Owner,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Repo,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TagName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Token
    )

    process
    {
        # Build API parameters
        $apiParams = @{
            RequestUri = ("/repos/{0}/{1}/releases/tags/{2}" -f $Owner, $Repo, $TagName)
            Token = $Token
        }

        Invoke-GithubApi @apiParams
    }
}
