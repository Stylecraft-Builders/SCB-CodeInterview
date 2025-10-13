# Variable Creation including $path which can be adjusted for manual script manipulation or leave to enter filepath
[string]$Path = Read-Host -Prompt "Enter the file path for Wireless Connection Profile XML File"
$WLAN_ErrorsforVariables = @()
$contentCheck = $false
$WLAN_Profile = $null
$profileName = $null
$profileAdded = $false

# Checking for file exsistance
try {
if (-not (Test-Path $Path)){
$WLAN_ErrorsforVariables += "The Wireless Local Area Network profile file is missing or cannot found: $Path"
$contentCheck = $true
}
else {
# Parse and validate XML against WPA2-PSK schema
try {
$WLAN_Profile = [xml](Get-Content -Path $Path -ErrorAction Stop)
if (-not $WLAN_Profile.DocumentElement) {
$WLAN_ErrorsforVariables += "The Wireless Local Area Network profile file is empty or invalid: $Path"
$contentCheck = $true
}
else {
# Validate WPA2-PSK schema elements
if (-not $WLAN_Profile.WLANProfile -or
$WLAN_Profile.WLANProfile.NamespaceURI -ne "http://www.microsoft.com/networking/WLAN/profile/v1"){
$WLAN_ErrorsforVariables += "Invalid or missing XML namespace for WLANProfile. Expected 'http://www.microsoft.com/networking/WLAN/profile/v1'."
}
# Check and confirm the <name> is filled out and element matches schema
if (-not $WLAN_Profile.WLANProfile.name -or
$WLAN_Profile.WLANProfile.name.Trim() -eq "") {
$WLAN_ErrorsforVariables += "The <name> element is missing required information or is blank."
}
# remove white space from the network name
else{
$profileName = $WLAN_Profile.WLANProfile.name.Trim()
}

# Check to confirm the SSIDConfig / SSID / Name of the network are all filled out and elements are present
if (-not $WLAN_Profile.WLANProfile.SSIDConfig -or
-not $WLAN_Profile.WLANProfile.SSIDConfig.SSID -or
-not $WLAN_Profile.WLANProfile.SSIDConfig.SSID.name -or
$WLAN_Profile.WLANProfile.SSIDConfig.SSID.name.Trim() -eq "") {
$WLAN_ErrorsforVariables += "The <SSIDConfig> or <SSID><name> is Missing or empty."
}

# Checking to confirm the connection type for the Wireless Network Connection Profile is either ESS or IBSS
if (-not $WLAN_Profile.WLANProfile.connectionType -or
$WLAN_Profile.WLANProfile.connectionType -notin "ESS", "IBSS") {
$WLAN_ErrorsforVariables += "The <connectionType> is either invalid or is missing. Expected 'ESS' or 'IBSS', found '$($WLAN_Profile.WLANProfile.connectionType)'."
}

# Checking to confirm the connection mode element is present and is set to auto or manual
if ($WLAN_Profile.WLANProfile.connectionMode -and
$WLAN_Profile.WLANProfile.connectionMode -notin "auto", "manual") {
$WLAN_ErrorsforVariables += "The <connectionMode> is invalid or is missing. Expected 'auto' or 'manual', found '$($WLAN_Profile.WLANProfile.connectionMode)'."
}

# Checking to confirm the MSM,securitkey and authEncryption elements are present
if (-not $WLAN_Profile.WLANProfile.MSM -or
-not $WLAN_Profile.WLANProfile.MSM.security -or
-not $WLAN_Profile.WLANProfile.MSM.security.authEncryption) {
$WLAN_ErrorsforVariables += " The <MSM>, <security>, or <authEncryption> is missing."
}
# Checks to confirm the authentication element is present and is set to WPA2PSK
elseif (-not $WLAN_Profile.WLANProfile.MSM.security.authEncryption.authentication -or
$WLAN_Profile.WLANProfile.MSM.security.authEncryption.authentication -ne "WPA2PSK") {
$WLAN_ErrorsforVariables += "The <authentication> element is missing or invalid . Expected 'WPA2PSK', found '$($WLAN_Profile.WLANProfile.MSM.security.authEncryption.authentication)'."
}
# Checks to confirm encrption element is present and set to AES
elseif (-not $WLAN_Profile.WLANProfile.MSM.security.authEncryption.encryption -or
$WLAN_Profile.WLANProfile.MSM.security.authEncryption.encryption -ne "AES") {
$WLAN_ErrorsforVariables += "The <encryption> element is missing or invalid. Expected 'AES', found '$($WLAN_Profile.WLANProfile.MSM.security.authEncryption.encryption)'."
}

# Checks to confirm the userOneX element is present and is set to true or false
elseif ($WLAN_Profile.WLANProfile.MSM.security.authEncryption.useOneX -ne $null -and
$WLAN_Profile.WLANProfile.MSM.security.authEncryption.useOneX -notin "true", "false") {
$WLAN_ErrorsforVariables += "The <useOneX> is missing or invalid. Expected 'true' or 'false', found '$($WLAN_Profile.WLANProfile.MSM.security.authEncryption.useOneX)'."
}
# Checks to confirm the passkey and keytype element are present and data is present
elseif (-not $WLAN_Profile.WLANProfile.MSM.security.sharedKey -or
-not $WLAN_Profile.WLANProfile.MSM.security.sharedKey.keyType -or
$WLAN_Profile.WLANProfile.MSM.security.sharedKey.keyType -ne "passPhrase") {
$WLAN_ErrorsforVariables += "The <sharedKey> or <keyType> is missing or invalid . Expected ' passPhrase'."
}
# Checks to confirm the keymatierial element is present
elseif (-not $WLAN_Profile.WLANProfile.MSM.security.sharedKey.keyMaterial -or
[string]::IsNullOrWhiteSpace($WLAN_Profile.WLANProfile.MSM.security.sharedKey.keyMaterial)) {
$WLAN_ErrorsforVariables += "The <keyMaterial> is missing or invalid."
}

# Checks to see if the profile has already been created and added (Please not if their is a profile already present this will trigger)
if ($WLAN_ErrorsforVariables.Count -eq 0 -and $profileName) {
$existingProfiles = netsh wlan show profiles | Select-String "All User Profile\s*:\s*(.+)" | ForEach-Object { $_.Matches.Groups[1].Value }
if ($existingProfiles -contains $profileName) {
$WLAN_ErrorsforVariables += "The network profile '$profileName' has already been added."
$contentCheck = $true
}
}
}
}
# Catch loops to determine if the Wirless Network Profile is malformed or cannot be read by script
catch {
$WLAN_ErrorsforVariables += "The WLAN profile file is malformed or cannot be read: $Path. Error: $_"
$contentCheck = $true
}

# Will attempt to add profile if no errors are present from above lines series of catches for all other errors
if (-not $contentCheck) {
try {
$netshOutput = netsh wlan add profile filename="$Path" user=all 2>&1
if ($LASTEXITCODE -eq 0 -and $netshOutput -match "is added on interface") {
$profileAdded = $true
}
else {
$WLAN_ErrorsforVariables += "Failed to add profile '$profileName'. Netsh error: $netshOutput"
$contentCheck = $true
}
}
catch {
$WLAN_ErrorsforVariables += "Unknown error adding profile '$profileName'. Error: $_"
$contentCheck = $true
}
}
}
}
catch {
$WLAN_ErrorsforVariables += "Unknown error processing file: $Path. Error: $_"
$contentCheck = $true
}

# Output results to host
if ($profileAdded -and $WLAN_ErrorsforVariables.Count -eq 0) {
Write-Host "$profileName has been successfully added!"
}
else {
Write-Host "Failed to add WLAN profile. Reasons for failure:"
$WLAN_ErrorsforVariables | ForEach-Object { Write-Host "  - $_" }
try {
Write-Host($WLAN_ErrorsforVariables -join "; ", "Error Adding Profile", "OK", "Error")
}
catch {
Write-Error "Cannot display error popup: $_"
}
}