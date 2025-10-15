<#
.SYNOPSIS
    Generic HTTPS data retrieval using JSON config for variables.

.DESCRIPTION
    Reads all settings from config.json in same folder (API key, URL template, output paths, log path).
    Validates config values and paths, tests network connection, invokes HTTPS request, and exports JSON output only.

.NOTES
    File Name : Generic_API_Data_Retrieval.ps1
    Author    : Steve Shide
    Date      : 1776-06-04
    Version   : 1.0
    Purpose   : Fully generic, config-driven HTTPS data fetch and JSON export.
    Usage     : Run from PowerShell 5.1 or newer
                Requires config.json in same folder, json file contains required variable.
                Requires valid API key in config.json for the target API.
                Outputs log file and JSON data file to paths specified in config.json, creating directories as needed.
    Trigger   : Scheduled Task two days after a financial month ends, at 6:00 AM.


#Under notes I have the detail of scheduled task. I'm approaching this script as if it's triggered once a month.
#The output file is sent to a network location. Ideally, there would be a check for network availability before running or failover of the data to a specific location.
    #I didn't builf this in due to the nature of the query, historical copper prices. If this script were to fail, it could be run again later picking up that month's missed data.
    #This isn't the most ideal situation, but it is workable, and I'm showing practicality in my approach.
#>



#region Load then Validate Config
# Enforce TLS 1.2
#I don't error protection against network being unable in a general sense, but I do enforce TLS 1.2
#If I had the time to continue building this out, I would add more error handling around network issues.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ScriptDir   = Split-Path -Parent $PSCommandPath
$configPath  = Join-Path $ScriptDir 'config.json'
#Anti-Concatenation 
#I don't have fail-safe handling for this, but I do check for the file's existence and validity.
#Some of the idea being this json is output to a network location then used by something like PowerBi. If a graph doesn't show up, the user can check the log file.

if (-not (Test-Path $configPath)) { throw "Missing config.json in $ScriptDir" }
try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    #the -raw handle is being used as the path is known to be simple and small.
} catch {
    throw "Invalid JSON in config.json: $_"
}

# Validate required config properties
foreach ($prop in 'ApiKey','UrlTemplate','JsonOutputDir','LogFilePath') {
    if (-not $config.PSObject.Properties.Name -contains $prop -or [string]::IsNullOrWhiteSpace($config.$prop)) {
        throw "config.json missing or empty '$prop'"
    }
}

# Assign variables
$ApiKey       = $config.ApiKey.Trim()
$UrlTemplate  = $config.UrlTemplate.Trim()
$JsonOutDir   = $config.JsonOutputDir.Trim()
$LogFilePath  = $config.LogFilePath.Trim()

# Ensure output directories
#Idealing permission handling should be built here.
#I have less experiance in this matter as I'm coming from an enviornment where permission enforcement policies are inplace via government oversight.
$dirs = @()
if ($JsonOutDir) { $dirs += $JsonOutDir }
$logDir = Split-Path $LogFilePath -Parent
if ($logDir) { $dirs += $logDir }
foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        try { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        catch { throw "Cannot create directory: $dir" }
        #THis script will attempt to create the directory if it doesn't exist.
        #This could have permissions issues.
    }
}
#endregion



#region Logging & Timestamp
function Write-Log {
    # Simple logging function with timestamp and level
    # I obtained this snippet utilizing Tee-Object from Siemens
    #Tee-Object is extremely useful to me
    param($Message,$Level='INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts [$Level] $Message" | Tee-Object -FilePath $LogFilePath -Append
}
function Get-Timestamp { Get-Date -Format 'yyyyMMdd_HHmm' }
#endregion



#region “Setup & Validation”

Write-Log "---Script started---"
#Visual cues to log start and end of script

# Extracts host from the URL template
$uriObj = [Uri]($UrlTemplate -replace '\{key\}',$ApiKey)
$apiHost = $uriObj.Host

# Tests connection to host over HTTPS
Write-Log "Checking network connectivity to $apiHost..."
if (-not (Test-NetConnection -ComputerName $apiHost -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded) {
    #I've learned it's important for silent failure. FOr this type of query, I don't want spammy logs or upsetting users. 
    #This query is a once a month query, so if it fails, it can be run again later.
    Write-Log "Network test to $apiHost failed. Cannot reach host." 'ERROR'
    exit 1
}
Write-Log "Network connectivity to $apiHost confirmed."
#Good confirmation, in my opinion. Makes use of apiHost variable
#endregion



#region Main Logic

#Meat and Potatoes
# Build request URL by inserting key
if ($UrlTemplate -notmatch '\{key\}') {
    Write-Log "UrlTemplate missing '{key}' placeholder" 'ERROR'; exit 1
}
$RequestUrl = $UrlTemplate -replace '\{key\}',$ApiKey
Write-Log "Request constructed."


# Evoke HTTPS request, with error handling
#I kept the script limited in error handling but doesn't expand or do anything with it.
#I fully believe more needs developed for error handling, however given the scope of the data and task, I believe mentions in notes are sufficient.
try {
    $data = Invoke-RestMethod -Uri $RequestUrl -ErrorAction Stop
    Write-Log "HTTPS request succeeded."
} catch [System.Net.WebException] {
    if ($_.Exception.Status -eq 'TrustFailure') {
        Write-Log "TLS certificate validation failed." 'ERROR'
    } else {
        Write-Log "WebException: $_" 'ERROR'
    }
    exit 1
    #I had to research how to close terminals for this script, simply because I forgot.
    #I'm not in practice of closing terminal sessions, as seeings them on the screen is a means of notification for machine or network errors
    #Roughtly the equivalent of an emergency stop button
} catch {
    Write-Log "Request failed: $_" 'ERROR'
    exit 1
}

# Prepare JSON output file path
$ts      = Get-Timestamp
$jsonOut = Join-Path $JsonOutDir "data_$ts.json"
#simple file name. The file-path contains details of what the data is.
#If this json were for use in PowerBi, then a more specific file name is needed.
#Why am I talking about this? Human readability and future thinking are important to me.
Write-Log "Output file will be $jsonOut"

# Export JSON
# I obtained this snippet and adapted it here
try {
    $data | ConvertTo-Json -Depth 3 | Set-Content -Path $jsonOut
    #I tested how deep to nest the JSON, 1 was unusable, 3 was perfect.
    #Why? I've never pulled financial data, so I didn't know what to expect.
    #Now that I'm looking at this on a different day, I realize I should have made this a variable in the config file.
    Write-Log "Saved JSON to $jsonOut"
} catch {
    Write-Log "Failed to save JSON: $_" 'ERROR'
    exit 1
}

Write-Log "---Script complete---"
#Visual cues to log start and end of script
#endregion
