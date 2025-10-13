# Define the script's base directory (where it is being executed from)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Define the input file path for the blocklist
# The blocklist.txt file contains mixed entries that need to be categorized.
$InputFilePath = Join-Path -Path $ScriptDir -ChildPath "blocklist.txt"

# Ensure the input file exists
# If blocklist.txt is missing, exit with a message to the user.
if (-not (Test-Path $InputFilePath)) {
    Write-Output "blocklist.txt could not found in script directory: $ScriptDir"
    Write-Output "Please ensure the file exists and retry."
    exit
}


# Define output file paths for each category
# These files will be created or overwritten with one entry per line.
# Country Code TLDs
$ccTLDFile = Join-Path -Path $ScriptDir -ChildPath "ccTLDs.txt"
# Generic Top Level Domains
$gTLDFile = Join-Path -Path $ScriptDir -ChildPath "gTLDs.txt"
# Domain-Subdomain entries
$DomainSubdomainFile = Join-Path -Path $ScriptDir -ChildPath "domains.txt"
# Email Addresses
$EmailFile = Join-Path -Path $ScriptDir -ChildPath "emails.txt"
# IPv4 Addresses
$IPv4File = Join-Path -Path $ScriptDir -ChildPath "ipv4.txt"
# IPv6 Addresses
$IPv6File = Join-Path -Path $ScriptDir -ChildPath "ipv6.txt"



# Read all lines from the input file and adds the conent to a array of strings with one per line
$lines = Get-Content -Path $InputFilePath

# Initialize collections for each category in arraylist
$ccTLDs = New-Object System.Collections.ArrayList
$gTLDs = New-Object System.Collections.ArrayList
$DomainSubdomains = New-Object System.Collections.ArrayList
$Emails = New-Object System.Collections.ArrayList
$IPv4s = New-Object System.Collections.ArrayList
$IPv6s = New-Object System.Collections.ArrayList

# Process each line in the blocklist.txt file for whitespace cleanup
foreach ($line in $lines) {
    # Trim whitespace and skip empty lines after trim
    $line = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    # Check if the line is an IP address using .NET's IP address class for IPv4 or IPv6 to parse in correct file
    $ip = $null
    if ([System.Net.IPAddress]::TryParse($line, [ref]$ip)) {
        if ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
            # IPv4 address
            $IPv4s.Add($line) | Out-Null
            continue
        } elseif ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
            # IPv6 address
            $IPv6s.Add($line) | Out-Null
            continue
        }
    }

    # Check if the line is an email address using .Net email address class
    try {
        $mail = New-Object System.Net.Mail.MailAddress($line)
        $Emails.Add($line) | Out-Null
        continue
    } catch {
    }

    # From now Assume it's a domain-related entry orignized based on patterns for TLDs, ccTLDs, general or oether domains/subdomains.
    # block is for checking the domains
    if ($line.StartsWith('*.')) {
        $domainPart = $line.Substring(2)
        if ($domainPart -notmatch '\.') {
            if ($domainPart.Length -eq 2 -and $domainPart -cmatch '^[a-zA-Z]+$') {
                $ccTLDs.Add($line) | Out-Null
            } else {
                $gTLDs.Add($line) | Out-Null
            }
        } else {
            $DomainSubdomains.Add($line) | Out-Null
        }
    } elseif ($line.StartsWith('@.')) {
        $DomainSubdomains.Add($line) | Out-Null
    } else {
        $DomainSubdomains.Add($line) | Out-Null
    }
}

# Output one on each line to respective files
if ($ccTLDs.Count -gt 0) {
    $ccTLDs | Out-File -FilePath $ccTLDFile -Encoding UTF8 -Force
    Write-Output "Created/Updated: $ccTLDFile with $($ccTLDs.Count) entries"
} else {
    Write-Output "No Country Code TLDs found. $ccTLDFile not created."
}

if ($gTLDs.Count -gt 0) {
    $gTLDs | Out-File -FilePath $gTLDFile -Encoding UTF8 -Force
    Write-Output "Created/Updated: $gTLDFile with $($gTLDs.Count) entries"
} else {
    Write-Output "No Top Level Domains found. $gTLDFile not created."
}

if ($DomainSubdomains.Count -gt 0) {
    $DomainSubdomains | Out-File -FilePath $DomainSubdomainFile -Encoding UTF8 -Force
    Write-Output "Created/Updated: $DomainSubdomainFile with $($DomainSubdomains.Count) entries"
} else {
    Write-Output "No Domain-Subdomains found. $DomainSubdomainFile not created."
}

if ($Emails.Count -gt 0) {
    $Emails | Out-File -FilePath $EmailFile -Encoding UTF8 -Force
    Write-Output "Created/Updated: $EmailFile with $($Emails.Count) entries"
} else {
    Write-Output "No Email Addresses found. $EmailFile not created."
}

if ($IPv4s.Count -gt 0) {
    $IPv4s | Out-File -FilePath $IPv4File -Encoding UTF8 -Force
    Write-Output "Created/Updated: $IPv4File with $($IPv4s.Count) entries"
} else {
    Write-Output "No IPv4 Addresses found. $IPv4File not created."
}

if ($IPv6s.Count -gt 0) {
    $IPv6s | Out-File -FilePath $IPv6File -Encoding UTF8 -Force
    Write-Output "Created/Updated: $IPv6File with $($IPv6s.Count) entries"
} else {
    Write-Output "No IPv6 Addresses found. $IPv6File not created."
}

# Completed message
Write-Output "Script execution completed. Categorized files are in: $ScriptDir"