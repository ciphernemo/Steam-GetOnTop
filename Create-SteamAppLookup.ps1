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
	#Reads in ".\existingapps.json", Scans .\SteamApps\ for app manifests, appends them and writes out to ".\steamapps.json"
 #>

[cmdletBinding(SupportsShouldProcess=$false)]
param
(
	[Parameter(Position=0, Mandatory=$false)]
	[String]$OutputFile = ".\AppLookup.json",
	[Parameter(Position=1, Mandatory=$false)]
	[String]$InputFile = ".\AppLookup.json"
)

# --------- Imports and Variables ---------

# Get script's current parent path and import modules
[string]$root = $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $root
Import-Module $root\Modules\SteamTools
Import-Module $root\Modules\LogTools

# Variables
[string[]]$steamLibraries = @()
[string[]]$steamPaths = Get-SteamPath
[string[]]$libIDs = @()
[string]$LookupTablePath = "$root\AppLookup.json"

# --------- Main ---------

# Create Log File
$log = "$root\Create-SteamAppLookup.log"
Set-LogPath $log
Set-LogLevel "Standard"
New-Item -Path $log -ItemType File -Force | Out-Null
Write-LogHeader -InputObject "Create-SteamAppLookup.ps1"

# Get steam install location and then all library locations
foreach ($mySteamPath in $steamPaths)
{
	# Get all Steam library paths
	$vdfLibraryFile = $mySteamPath + "\steamapps\libraryfolders.vdf"
	Write-Log -InputObject "`nPath to library config file: $vdfLibraryFile `n"
	$vdfLibraryContent = Get-Content $vdfLibraryFile
	$vdfLibraryObject = ConvertFrom-VDF -Source $vdfLibraryContent
	$vdfLibraryObject.libraryfolders.PSObject.Properties | foreach-Object { $libIDs += $_.Name }
	foreach ($i in $libIDs)
	{
		$thisPath = $vdfLibraryObject.libraryfolders.$i.path
		$thisPath = $thisPath.Replace("\\", "\")
		if (Test-Path "$thisPath\steamapps\common")
		{
			Write-Log -InputObject "Found library ID $i with path $thisPath"
			$steamLibraries += $thisPath
		}
	}
}

# If AppLookup.json exists, get its contents
if (Test-Path $LookupTablePath)
{
	$AppLookup = Get-Content $LookupTablePath | ConvertFrom-Json
}
[array]$apps = @()
if ($null -ne $AppLookup) {	[array]$apps += $AppLookup }

# Parse acf files in libraries to get installed app listing, then compare to any existing AppLookup.json data
foreach ($mySteamPath in $steamPaths)
{
	foreach ($steamLibrary in $steamLibraries)
	{
		foreach ($file in (Get-ChildItem "$($steamLibrary)\SteamApps\*.acf"))
		{
			$acf = ConvertFrom-VDF (Get-Content $file -Encoding UTF8)
			$myApp = [pscustomobject] [ordered]@{ appid = $acf.AppState.appid; name = $acf.AppState.name; installdir = $acf.AppState.installdir }
			if ($myApp.appid -notin $apps.appid) { $apps += $myApp }
		}
	}
}
$apps | ConvertTo-Json | Out-File $LookupTablePath -Encoding UTF8
