<#
.SYNOPSIS
    Parses a mixed-format blocklist file then categorizes entries into separate output files.

.DESCRIPTION
    Reads blocklist.txt then filters into six categories:
        ccTLDs
        generic TLDs
            I hate using "generic" but I don't have a better term right now)
            This change from "TLDs" to "generic TLDs" was made after feedback from a good friend
        domains/subdomains
        emails
        IPv4
        IPv6
    
    Classification/Categories Priority: 1. IPv6 > 2. IPv4 > 3. Email > 4. ccTLD > 5. Generic TLD > 6. Domain

.PARAMETER ConfigPath
    Path to configuration JSON file. Defaults to './config.json'

.NOTES
    Author    : Steve Shide
    Date      : 1776-06-04
    Version   : 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "./config.json"
)

$ErrorActionPreference = "Stop"



#region Configuration and Initialization

# Load config
# Needs an added validation for file existence and JSON parsing errors
$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

# Define classification lists
# Currently hardcoded for simplicity and time constraints
# I'd prefer config.json, or an expansionary "bigger_blocklist.json"
$ccTLDList = @('ru', 'cn', 'in', 'br')
$genericTLDList = @('info', 'solutions', 'dad', 'hello')

# Initialize category collections
# genericTLD was changed from TLD
# I found this trick from AI and using it here. This hashtable of arrays is cleaner than multiple arrays
# This is the first script I've built integrating hashtables
$categories = @{
    ccTLD = @()
    genericTLD = @()
    domainSubdomain = @()
    email = @()
    ipv4 = @()
    ipv6 = @()
}
#https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-hashtable?view=powershell-7.5
#First major use of hashtables for me. This came up in research, I remembered and found notes I keep in Obsidian (my knowledge application)
#I'm use to arrays but I used this as a learning experience
# I wrote this out in my technical project charter


# Create out directory
# Add error handling for directory creation failures
# I'm not an expert in permissions, but I added -Force to help with that. Just like a GPUpdate /force
if (-not (Test-Path -Path $config.OutputDirectory)) {
    New-Item -Path $config.OutputDirectory -ItemType Directory -Force | Out-Null
}

#endregion



#region Regex Patterns

#I did not create these regularexpression patterns from scratch. I researched then adapted.
#I am not an expert, but I know how to research then use https://marketplace.visualstudio.com/items?itemName=Nishikanta12.regex
# Another good resource I used when reapproaching https://marketplace.visualstudio.com/items?itemName=chrmarti.regex
    # I used that extension for generating most of these patterns.
    # I tested these patterns with https://regex101.com/ and https://www.regextester.com/
#regexlib.com is another source I used
#https://therandomadmin.com/2025/05/01/powershell-regex-use-case/ is another


# IPv4
# XXX is 0-255
#  This could be strictened but I left here for praticality after researching it.
$ipv4Regex = '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'

# IPv6
# This was a major learning experience for me. I've never worked with IPv6
# I used VS Code Regex extension to help me build this pattern and regex101.com to test it.
$ipv6Regex = '^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:))$'

# Email 
$emailRegex = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

# Domain 
# Allows wildcards, subdomains, and standard formats
$domainRegex = '^(\*@)?\*?\.?[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$'

# TLD Pattern
# Matches *.tld format
$tldPatternRegex = '^\*\.([a-zA-Z0-9]+)$'

#endregion



#region Input Processing

# Read and normalize entries
# Erros will occur for file not found, permissions, or other errors
# If this was prodcution I'd add more and at-time-of-writing I don't have time
$entries = Get-Content -Path $config.InputFilePath | 
    Where-Object { $_.Trim() -ne "" } | 
    ForEach-Object { $_.Trim() } | 
    Select-Object -Unique

#endregion



#region Classification Logic

# Process each entry through classification hierarchy
# This Priority order starts with most specific matches first. I've found this from recommendations
#I wrote this in the Technical Project Charter I wrote in Asana, then built it out here.
# This is why they are titled/commented as such
foreach ($entry in $entries) {
    
    # Priority 1: IPv6
    if ($entry -match $ipv6Regex) {
        $categories.ipv6 += $entry
        continue
    }
    
    # Priority 2: IPv4
    if ($entry -match $ipv4Regex) {
        $categories.ipv4 += $entry
        continue
    }
    
    # Priority 3: Email addresses
    if ($entry -match $emailRegex -and $entry -notlike "*@**") {
        # this exclusion was recommended from a google search
        $categories.email += $entry
        continue
    }
    
    # Priority 4: ccTLDs
    if ($entry -match $tldPatternRegex) {
        $tld = $matches[1].ToLower()
        if ($ccTLDList -contains $tld) {
            $categories.ccTLD += $entry
            continue
        }
        
        # Priority 5: TLDs
        if ($genericTLDList -contains $tld) {
            $categories.genericTLD += $entry
            continue
        }
    }
    
    # Priority 6: Domain/Subdomains
    if ($entry -match $domainRegex) {
        $categories.domainSubdomain += $entry
        continue
    }
    
    # Unclassified entries (data quality issue indicator)
    # Production: Log these to a separate file for review
    Write-Host "Warning: Unclassified entry: $entry" -ForegroundColor Yellow
}

#endregion



#region Output Generation

# If ---> enableTimestamps is true, appends timestamp to filenames
# Snippet 
$timestamp = if ($config.EnableTimestamps) { 
    Get-Date -Format $config.TimestampFormat
    #allows for variations if not enabled in config
    #lack of calidation  
} else { 
    "" 
}
$suffix = if ($timestamp) { "_$timestamp" } else { "" }

## VS Code Snippet suggested approach, but I found it too complex for this use case and I don't fully understand it.
## This is simply an alternative approach if you want to explore it further.
#{ 
## Build a timestamp only when enabled, using a safe default and removing invalid filename chars
#$defaultFormat = 'yyyyMMdd_HHmmss'
#$format = if ($null -ne $config -and $config.TimestampFormat) { $config.TimestampFormat } else { $defaultFormat }
#
#if ($null -ne $config -and $config.EnableTimestamps) {
#    $rawTimestamp = Get-Date -Format $format
#    # Remove characters that are invalid in file names (cross-platform safe)
#    $invalid = [System.IO.Path]::GetInvalidFileNameChars() -join ''
#    $timestamp = ($rawTimestamp -replace "[$invalid]", '')
#} else {
#    $timestamp = ''
#}
#
#$suffix = if ($timestamp) { "_$timestamp" } else { '' }
#}


# Defines output filenames
# This could be a in the config.json
# It's here as I built this first in my Project Charter
$fileMap = @{
    ccTLD = "ccTLD-blocklist"
    genericTLD = "TLD-blocklist"
    #genericTLD being used for clarity in code for reduced confusion
    domainSubdomain = "domain-subdomain-blocklist"
    email = "email-blocklist"
    ipv4 = "ipv4-blocklist"
    ipv6 = "ipv6-blocklist"
}

# Write categorized entries via hastable to files
# Needs error handling for a live environment
foreach ($category in $fileMap.Keys) {
    #"Hashtable keys"
    $filename = "$($fileMap[$category])$suffix.txt"
    $filepath = Join-Path -Path $config.OutputDirectory -ChildPath $filename
    # Sort entries alphabetically and write one per line
    $categories[$category] | Sort-Object | Set-Content -Path $filepath
    
    Write-Host "Created $filename with $($categories[$category].Count) entries"
    #write-output maybe better, I'm using old habits however as I had this snippet from first learning about it. That means everything needs documented in a file that's sent other the network
    # If I'm hired for this role, there will be habits I'll need to lean away from
}

#endregion



#region Summary Output

Write-Host "`nProcessing Complete. Files created in: $($config.OutputDirectory)"
Write-Host "`nSummary:"
Write-Host "  Country Code TLDs:   $($categories.ccTLD.Count)"
Write-Host "  TLDs:                $($categories.genericTLD.Count)"
Write-Host "  Domains/Subdomains:  $($categories.domainSubdomain.Count)"
Write-Host "  Email Addresses:     $($categories.email.Count)"
Write-Host "  IPv4 Addresses:      $($categories.ipv4.Count)"
Write-Host "  IPv6 Addresses:      $($categories.ipv6.Count)"

#endregion