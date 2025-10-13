# Define the script's base directory (where it is being executed from)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Define file paths for api key and json output file and creates file if not present
$ApiKeyFile = Join-Path -Path $ScriptDir -ChildPath "api.txt"
$OutputFilePath = Join-Path -Path $ScriptDir -ChildPath "unrate.json"

# Ensure api.txt exists if noy make api.text for inputting api key
if (-not (Test-Path $ApiKeyFile)) {
    Write-Output "api.txt not found. Creating a blank file at: $ApiKeyFile"
    New-Item -Path $ApiKeyFile -ItemType File -Force | Out-Null
    Write-Output "Please open api.txt file and add your API key and retry."
    exit
}

# Check if api.txt is empty
$ApiKey = Get-Content -Path $ApiKeyFile -ErrorAction Stop | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Output "api.txt is empty. Please add your FRED API key to the file and retry."
    exit
}


try {
    # Check network connectivity
    if (-not (Test-Connection -ComputerName "api.stlouisfed.org" -Count 1 -Quiet)) {
        throw "Network is unavailable. Cannot reach api.stlouisfed.org."
    }

    # Build FRED API URI
    $uri = "https://api.stlouisfed.org/fred/series/observations?series_id=UNRATE&api_key=$ApiKey&file_type=json"

    Start-Sleep -Seconds 30

    # Make the API request
    $response = Invoke-WebRequest -Uri $uri -Method Get -ErrorAction Stop

    if ($response.StatusCode -eq 200) {
        $jsonContent = $response.Content

        try {
            $jsonObject = ConvertFrom-Json $jsonContent -ErrorAction Stop
            if (-not $jsonObject.observations) {
                throw "API response does not contain expected 'observations' data."
            }
        }
        catch {
            throw "Invalid JSON response from API. Details: $($_.Exception.Message)"
        }

        $jsonContent | Out-File -FilePath $OutputFilePath -Encoding UTF8 -Force
        Write-Output "Successfully retrieved data and saved to $OutputFilePath"
    }
    else {
        throw "API request failed with status code $($response.StatusCode): $($response.StatusDescription)"
    }
}
catch {

    # error catching for all possible condidtions
    $errorMessage = $_.Exception.Message
    switch -Regex ($errorMessage) {
        "Network is unavailable" {
            Write-Output "Error: $errorMessage Check your internet connection."
        }
        "Invalid output file path" {
            Write-Output "Error: $errorMessage"
        }
        "429" {
            Write-Output "Error: API rate limit exceeded (429). Please wait and try again later."
        }
        "400|401|403" {
            Write-Output "Error: Authentication or request issue. Verify your API key in api.txt."
        }
        "503|502" {
            Write-Output "Error: API is unavailable. Try again later."
        }
        default {
            Write-Output "Error: Unexpected failure. Details: $errorMessage"
        }
    }
}
finally
{
    Write-Verbose "Script execution completed."
}