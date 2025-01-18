<# 
 .Synopsis 
	Scans .\SteamApps\ for app manifests, adds them to a lookup table and then writes that able to a JSON file.

 .Description 
    This script will search for app manifests in .\SteamApps\(*.acf), and extract the AppID, Name and Install Directory from each to store in a lookup table. This table is then
	output to a JSON file, to be used as a reference for matching Steam apps to install folders.

 .Parameter OutputFile
     This specifies the path to the JSON file for output. Default is ".\AppLookup.json"

 .Parameter InputFile
     This specifies the path to an existing JSON file so that a lookup table can be appended. Default is ".\AppLookup.json"

 .Example 
     .\Initialise-SteamAppLookup.ps1 -OutputFile ".\steamapps.json" -InputFile ".\existingapps.json"

     Description 
     ----------- 
     Reads in ".\existingapps.json", Scans .\SteamApps\ for app manifests, appends them and writes out to ".\steamapps.json"
 #>

[cmdletBinding(SupportsShouldProcess=$false)]
param(
	[Parameter(Position=0, Mandatory=$false)]
	[String]$OutputFile = ".\AppLookup.json"
	,
	[Parameter(Position=1, Mandatory=$false)]
	[String]$InputFile = ".\AppLookup.json"
)

Import-Module $PSScriptRoot\Modules\VDFTools
Import-Module $PSScriptRoot\Modules\LogTools

#find Steam, and if necessary offer choice when a drive search found multiple steam.exe files
[string[]]$steamPaths = Get-SteamPath
[string]$mySteamPath = $steamPaths[0]
if ($steamPaths.Count -gt 1)
{
	[System.Management.Automation.Host.ChoiceDescription[]]$choicesSteam = @()
	$choiceTextSteam = [String]::Empty
	$i = 0
	foreach ($path in $steamPaths)
	{
		$choicesSteam += "`&$i"
		$choiceTextSteam += "$i -- $path`n"
		$i++
	}
	$titleSteam = "`nThe following possible Steam paths were found on your system:" + $choiceTextSteam
	$promptSteam = "Please choose the location of your Steam install..."
	$mySteamChoice = $host.UI.PromptForChoice($titleSteam, $promptSteam, $choicesSteam, 0)
	$mySteamPath = $steamPaths[$mySteamChoice]
	Write-Log -InputObject "`n"
}
Write-Log -InputObject "Using Steam client found at $mySteamPath"

$LookupTablePath = ".\AppLookup.json"
if (Test-Path $LookupTablePath) {
	$AppLookup = Get-Content $LookupTablePath | ConvertFrom-Json
}

[array]$apps = @()

if ($AppLookup -ne $null) {
	[array]$apps += $AppLookup
}

ForEach ($file in (Get-ChildItem "$($mySteamPath)\SteamApps\*.acf") ) {
	$acf = ConvertFrom-VDF (Get-Content $file -Encoding UTF8)
	if ($acf.AppState.appID -notin $apps.AppID) {
		[array]$apps += $acf.AppState | Select-Object -Property AppId, Name, InstallDir
	}
}

$apps | ConvertTo-Json | Out-File $LookupTablePath -Encoding UTF8
