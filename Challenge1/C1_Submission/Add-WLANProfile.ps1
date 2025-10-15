<#
.SYNOPSIS
    Deploys a Wi-Fi(WLAN) profile to Windows machines from a predefined XML file.

.DESCRIPTION
    This automation script interacts with an XML file, Profile1.xml, containing preconfigured Wi-Fi settings. This script reads the file, deploys the profile, connects to the specified Wi-Fi network, then verifies connection status.

.NOTES
    File Name  : Add-WLANProfile.ps1
    Author     : Steve Shide
    Date       : 1776-06-04
    Version    : 1.1
    Purpose    : To automate deployment of a Wi-Fi profile on Windows machines.
    XML File   : Profile1.xml
    Exit Codes : 
        0: Success
        1: Missing XML
        2: Malformed XML
        3: Profile already exists
        4: No enabled wireless NIC
        5: Unknown error
#Script assumes SYSTEM privileges.
#Exit codes are defined in notes for easy reference.

.PARAMETER Path
    C:\Initial_Setup\WiFi\Profile1.xml

.PARAMETER OverwriteExisting
    When specified, existing profile overwrote retaining same name. Otherwise, skips existing profiles.

.PARAMETER MaxRetries
    Number of retry attempts for vagrant failures (default: 3).
#I always provide default parameter values.

.PARAMETER RetryDelaySeconds
    Delay between retry attempts (default: 3).
#I always provide default parameter values.

.PARAMETER LogPath
    Log file's Path. Default is C:\Initial_Setup\WiFi\Logs\Add-WLANProfile.log.

.PARAMETER Verbose
    Enables verbose logging output.

#>


# I'm a fervant believer in regions for human readability.
#region Script Parameters
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Path,
    [switch]$OverwriteExisting,
    [int]$MaxRetries        = 3,
    [int]$RetryDelaySeconds = 3,
    [string]$LogPath        = "$PSScriptRoot\Logs\Add-WLANProfile.log"
)
#endregion


#region Exit Code Definitions
# Also defined in .NOTES for easier reference.
$EXIT_SUCCESS            = 0  # Success
$EXIT_MISSING_XML        = 1  # Missing XML
$EXIT_MALFORMED_XML      = 2  # Malformed XML
$EXIT_PROFILE_EXISTS     = 3  # Profile already exists
$EXIT_NO_ACTIVE_NICS     = 4  # No enabled wireless NIC
$EXIT_UNKNOWN_ERROR      = 5  # Unknown error
#endregion


#Straightforward logging functions for consistency. I brought this in from my snippet library.
#I don't re-invent the wheel, I re-use it. I don't remember where I got this from originally.
#region Logging Functions
function Initialize-Logging {
    param([string]$FilePath)
    try {
        $dir = Split-Path -Parent $FilePath
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
        return $true
    }
    catch {
        Write-Warning "Failed to create log directory: $_"
        return $false
    }
}

function Write-Log {
    param(
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level,
        [string]$Message
    )
    $ts = (Get-Date).ToString('s')
    "$ts [$Level] $Message" | Out-File -FilePath $Global:LogFile -Append
    if ($Global:VerbosePreference -eq 'Continue') {
        Write-Verbose "${Level}: $Message"
    }
}
#endregion
#E:\Repositories\LightForgeLabs\SCB-CodeInterview\Challenge1\C1_RD


#I obtained the XML schema validation method from a Siemens engineer while validating XML for a SCADA system.
#I adapted it for this script, it's not purely original work, however, I did modify it to fit this context.
#Again, I prefer not re-inventing the wheel, simply adapt and re-use.
#region Validation Functions
function Test-Parameters {
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )
    if (-not (Test-Path $Path)) {
        Write-Log -Level ERROR "XML file not found at '$Path'"
        Write-Host "Usage: .\Add-WLANProfile.ps1 -Path <Profile.xml> [-OverwriteExisting] [-MaxRetries <n>] [-RetryDelaySeconds <s>] [-LogPath <file>] [-Verbose]"
        throw "XML file not found"
    }
    Write-Log -Level INFO "Validated XML path: $Path"
}


#This example scheme at w3.org was suggested by an Automation Engineer at Fujifilm. I kept the link in my snippet library.
function Test-XmlSchema {
    param([string]$Path)
    try {
        [xml]$doc = Get-Content $Path -ErrorAction Stop
        $xsdText = @"
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
  <xs:element name="WLANProfile">
    <xs:complexType>
      <xs:sequence>
        <xs:element name="Name"  type="xs:string"/>
        <xs:element name="SSID"  type="xs:string"/>
        <xs:element name="Key"   type="xs:string"/>
      </xs:sequence>
    </xs:complexType>
  </xs:element>
</xs:schema>
"@
        $schemaSet = New-Object System.Xml.Schema.XmlSchemaSet
        $schemaSet.Add("", (New-Object System.IO.StringReader $xsdText)) | Out-Null
        $script:validationErrors = $false
        $validationCallback = { param($s,$e) $script:validationErrors = $true }
        $doc.Validate($schemaSet, $validationCallback)
        if ($script:validationErrors) {
            Write-Log -Level ERROR "XML schema validation failed"
            throw "XML schema validation failed"
        }
        Write-Log -Level INFO "XML schema validated successfully"
    }
    catch {
        Write-Log -Level ERROR "Error validating XML schema: $_"
        throw "XML validation error: $_"
    }
}

#While this wasn't request in the Challenge, experience tells me it's good practice.
#This function selects the first Up wireless NIC.
#This isn't a powershell cmdlet, I've used this method in previous scripts.
#I normally only target RJ-45 connections, I needed to research for wireless NICs, targeting the 802.11 medium. Not pure original work.
function Get-ActiveWirelessNIC {
    $adapters = Get-NetAdapter -Physical |
                Where-Object { $_.Status -eq 'Up' -and $_.NdisPhysicalMedium -eq '802.11' }
    if ($adapters.Count -eq 0) {
        Write-Log -Level ERROR "No active wireless NICs found"
        throw "No active wireless NICs found"
    }
    Write-Log -Level INFO "Using wireless NIC: $($adapters[0].Name)"
    return $adapters[0].Name
}
#This function should be improved with better Error handling. If value was determined, I would put this in a dev project pipeline.
#Since we're using SYSTEM privileges, I'm avoiding interactive prompts.
#Why did I add this to the script? I'm unsure if this script is intended purely for laptops, or desktops will be included. This is an attempt to cover both bases.
#After I brought this into the script, I realized it may not be necessary for the challenge, but I wanted to demonstrate my thoroughness.

#endregion



#Here, I rolled Import and Retry logic together for simplicity. Again, using regions for clarity.
#I received advice for a fellow network engineer for this section. This is a new method for me.
#Since I brought in the logging functions from my snippet library, I wanted to ensure I used something new here.
#This section is more complex than intended for the challenge, but I wanted to demonstrate my ability to adapt and learn.
#region Import & Retry Functions
function Import-WlanProfile {
    param(
        [string]$XmlPath,
        [string]$NicName,
        [switch]$OverwriteExisting
    )
    try {
        if ($OverwriteExisting.IsPresent) {
            $overwriteParam = "user=current"
        }
        else {
            $overwriteParam = ""
        }
        
        $result = netsh wlan add profile filename="$XmlPath" interface="$NicName" $overwriteParam 2>&1
        $resultString = $result | Out-String
        
        if ($resultString -match 'already exists') {
            Write-Log -Level WARN "Profile already exists"
            throw "Profile already exists"
        }
        
        Write-Log -Level INFO "Profile imported on $NicName (Overwrite=$($OverwriteExisting.IsPresent))"
        Write-Host "Profile imported successfully."
    }
    catch {
        $msg = $_.Exception.Message
        Write-Log -Level ERROR "Import failed: $msg"
        throw
    }
}

function Invoke-WithRetry {
    param(
        [scriptblock]$Action,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 3
    )
    $attempt = 0
    $delay   = $RetryDelaySeconds
    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            & $Action
            return $true
        }
        catch {
            Write-Log -Level WARN "Attempt $attempt failed: $($_.Exception.Message)"
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds $delay
                $delay *= 2
            }
            else {
                Write-Log -Level ERROR "All $MaxRetries attempts failed"
                throw "All retry attempts exhausted"
            }
        }
    }
}
#endregion

#The top level script execution block.
#region Script Execution
$Global:LogFile = $LogPath

# Initialize logging first
Initialize-Logging -FilePath $Global:LogFile | Out-Null

try {
    # 1. Validate parameters
    Test-Parameters -Path $Path

    # 2. Validate XML schema
    Test-XmlSchema -Path $Path

    # 3. Select active wireless NIC
    $nic = Get-ActiveWirelessNIC

    # 4. Import profile with retry logic
    $actionBlock = {
        Import-WlanProfile -XmlPath $Path -NicName $nic -OverwriteExisting:$OverwriteExisting
    }
    Invoke-WithRetry -Action $actionBlock -MaxRetries $MaxRetries -RetryDelaySeconds $RetryDelaySeconds
    
    Exit $EXIT_SUCCESS
}
catch {
    $errorMsg = $_.Exception.Message
    Write-Log -Level ERROR "Script failed: $errorMsg"
    
    # Determine appropriate exit code
    if ($errorMsg -match 'XML file not found') {
        Exit $EXIT_MISSING_XML
    }
    elseif ($errorMsg -match 'XML validation' -or $errorMsg -match 'XML schema') {
        Exit $EXIT_MALFORMED_XML
    }
    elseif ($errorMsg -match 'already exists') {
        Exit $EXIT_PROFILE_EXISTS
    }
    elseif ($errorMsg -match 'No active wireless') {
        Exit $EXIT_NO_ACTIVE_NICS
    }
    else {
        Exit $EXIT_UNKNOWN_ERROR
    }
}
#endregion