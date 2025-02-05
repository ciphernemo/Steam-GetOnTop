# --------- Functions ---------

# Formats a path to replace all forward slashes with back slashes and return its proper capitalization
function Format-ProperPath
{
	param
	(
		[parameter(Mandatory = $true)]
		[string]$Path
	)
	$Path = $Path.Replace('/', '\')
	$properPath = [String]::Empty
	if (!((Test-Path $Path -PathType Leaf) -or (Test-Path $Path -PathType Container)))
	{
		return $Path
	}
	foreach ($branch in $Path.Split("\"))
	{
		if ($properPath -eq "")
		{
			$properPath = $branch.ToUpper() + "\"
			continue
		}
		$properPath = [System.IO.Directory]::GetFileSystemEntries($properPath, $branch)[0];
	}
	return $properPath;
}

# Formats a string to trim leading and trailing quote marks
function Format-MemberString
{
	param
	(
		[parameter(Mandatory = $true)]
		[string]$myMember
	)
	return (($myMember).Substring(1, $myMember.Length - 2))
}

# Parses a VDF and converts it to a custom object
#	example: $vdf = ConvertFrom-VDF -source (Get-Content "C:\localconfig.vdf")
function ConvertFrom-VDF
{
	param
	(
		[parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[String[]]$Source
	)
	# Make one to two matches per line of quoted sections, separate by tabs only when next to quote marks,
	#	match empty and single character quoted sections,
	#	include escaped quotes \" in matches but don't make separate matches for \"",
	#	and include leading and trailing quote marks for safety as they will be removed when converting back to VDF
	$pattern = '(?<=^|\t|{|\n)"((?:[^"\\]|\\[\\"])*)"(?=\t|\n|$|})'
	$root = New-Object -TypeName PSObject
	$chain = [ordered]@{}
	$treeDepth = 0
	$parent = $root
	$element = $null
	$i = 0
	foreach ($line in $Source)
	{
		$quotedElements = (Select-String -Pattern $pattern -InputObject $line -AllMatches).Matches
		# Create a new sub object
		if ($quotedElements.Count -eq 1)
		{
			$myValue = Format-MemberString ($quotedElements[0].Value)
			$element = New-Object -TypeName PSObject
			Add-Member -InputObject $parent -MemberType NoteProperty -Name $myValue -Value $element
		}
		# Create a new string hash
		elseif ($quotedElements.Count -eq 2)
		{
			$myValue1 = Format-MemberString ($quotedElements[0].Value)
			$myValue2 = Format-MemberString ($quotedElements[1].Value)
			Add-Member -InputObject $element -MemberType NoteProperty -Name $myValue1 -Value $myValue2
		}
		elseif ($line -match "{")
		{
			$chain.Add($treeDepth, $element)
			$parent = $chain.$treeDepth
			$treeDepth++
		}
		elseif ($line -match "}")
		{
			$treeDepth--
			$treeDepthLower = $treeDepth - 1
			$parent = $chain.$treeDepthLower
			$element = $parent
			$chain.Remove($treeDepth)
		}
		$i++
	}
	return $root
}

# Converts an object to a VDF file
#	example: [System.IO.File]::WriteAllLines($vdfFile, (ConvertTo-VDF -Source $vdfObject))
function ConvertTo-VDF
{
	param
	(
		[parameter(Mandatory = $true, Position = 0)]
		[PSObject]$Source,
		[parameter(Mandatory = $false, Position = 1)]
		[int]$treeDepth = 0
	)
	$output = [String]::Empty
	$members = $Source.PSObject.Members | Where-Object { $_.MemberType -eq "NoteProperty" }
	for ($i = 0; $i -lt $members.Count; $i++)
	{
		$member = $members[$i]
		if ($member.TypeNameOfValue -eq "String")
		{
			$tabIndent = "`t" * $treeDepth
			$m1 = $member.Name
			$m2 = $Source.($member.Name)
			$output += $tabIndent + "`"" + $m1 + "`"`t`t`"" + $m2 + "`"`n"
		}
		elseif ($member.TypeNameOfValue -eq "System.Management.Automation.PSCustomObject")
		{
			$tabIndent = "`t" * $treeDepth
			$element = $Source.($member.Name)
			$output += $tabIndent + "`"" + ($member.Name) + "`"`n"
			$output += $tabIndent + "{`n"
			$treeDepth++
			$output += ConvertTo-VDF -Source $element -treeDepth $treeDepth
			$treeDepth--
			$output += $tabIndent + "}"
			if ($treeDepth -gt 0)
			{
				$output += "`n"
			}
		}
	}
	return $output
}

# Finds the Steam install path
function Get-SteamPath
{
	# Search for Steam in registry keys
	[string[]]$hive = @("HKCU:", "HKLM:")
	foreach ($h in $hive)
	{
		try
		{
			$key = "$h\Software\Valve\Steam\"
			if (Test-Path -Path $key)
			{
				$steam = Format-ProperPath ((Get-ItemProperty $key).SteamPath)
				if (Test-Path -Path $steam) { return $steam }
			}
		}
		catch
		{
			continue
		}
	}
	# Test for default install path
	$pfx86 = "${Env:ProgramFiles(x86)}"
	if (Test-Path -Path "$pfx86\Steam\steam.exe")
	{
		return "$pfx86\Steam\steam.exe"
	}
	# Search drives for steam.exe file
	else
	{
		Write-Host "Steam client not within the Registry or default location. Searching your drives for Steam..."
		# Set up system drive exclusions for search
		[string[]]$paths = @($Env:SystemRoot, $Env:ProgramData, $Env:TEMP, "$Env:SystemRoot\Temp", "$Env:SystemDrive\Recovery")
		$paths += ("$Env:USERPROFILE\GoogleDrive", "$Env:USERPROFILE\Box")
		if ($Env:OneDrive) { $paths += $Env:OneDrive }
		# Get all drives on the system
		[string[]]$driveLetters = Get-PSDrive | Select-Object -ExpandProperty "Name" | Select-String -Pattern '^[a-z]$'
		[string[]]$results = @()
		foreach ($d in $driveLetters)
		{
			$d = $d + ":\"
			Write-Host "Searching $d drive..."
			#recursively search a drive and add matches to results
			if ($items = Get-ChildItem -Path $d -Filter "steam.exe" -Exclude $paths -Recurse)
			{
				foreach ($item in $items)
				{
					$results += $item.FullName
				}
			}
		}
		if ($results.Count -gt 0)
		{
			return $results
		}
		else
		{
			# No results found
			Write-Host "Steam not found on the local system. Exiting..."
			Start-Sleep -Seconds 6
			exit
		}
	}
}

Function Get-SteamID64
{
	param
 	(
		[Parameter(Position=0, Mandatory=$true)]
		[System.Int32]$SteamID3
	)
	if (($SteamID3 % 2) -eq 0)
 	{
		$Y = 0;
		$Z = ($SteamID3 / 2);
	}
	else
	{
		$Y = 1;
		$Z = (($SteamID3 - 1) / 2);
	}
	return "7656119$(($Z * 2) + (7960265728 + $Y))"
}
