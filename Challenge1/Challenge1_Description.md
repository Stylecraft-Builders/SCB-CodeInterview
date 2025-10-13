<p align="center">
  <a href="https://stylecraft.com" target="_blank" alt="Stylecraft Builders Home"><img src="../img/scb_white-background.png" width="450" /></a>
</p>

# Challenge 1: WLAN Network Deployment

## Scenario

You are working in an environment where there are potentially multiple business networks with different WLAN configurations, for example between regions or business units. To help users stay connected as they move between locations, you need to deploy premade WLAN profiles to their computers during initial setup.

For simplicity, assume that these are WPA2-PSK networks, rather than enterprise.

## Task

Write a **Powershell** script to deploy a WLAN profile to a computer. This script should be generic, taking an XML profile file as a parameter.

For this scenario, you can assume the script and XML file will be placed locally on the machine before execution and don't need to worry about other deployment details. You can also assume that the script is invoked with SYSTEM privileges.

Make sure to anticipate the following scenarios in addition to success:

1. The supplied XML profile is malformed
2. The supplied XML profile is missing
3. The network was already added
4. There was an unknown error

## Example

```PowerShell
>>> .\Add-WLANProfile -Path Profile1.xml
Profile1 has been successfully added!
```

## Helpful Hints

1. Check out [Microsoft Learn](https://learn.microsoft.com) for documentation on adding and removing wireless profiles in Windows.
2. Use PowerShell for your error checking and scaffolding, but remember it's not the only scripting resource available on Windows.
//

