<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2017 v5.4.140
	 Created on:   	2018-09-01 00:00
	 Updated on:	2018-09-05 17:17
	 Created by:   	Aemony
	 Organization: 	-
	 Filename:     	Backup-SteamGames.ps1
	===========================================================================
	.DESCRIPTION
		Checks all Steam libraries and their appmanifest files to detect fully
		updated applications and copies these over to a specified location.

		Note that this script separates builds into different subfolders,
		meaning it isn't a simple 1:1 mirroring between the source and
		destination. The main purpose of this script is to enable automatic
		build backups of each version released for a game on Steam.

		As the script does not clean previous builds, THIS WILL result in
		massive storage requirements down the line.

#>

<# ============== CONFIGURATION ============== #>
# Destination folder where folders are backed up to, ex. $TargetFolder = "D:\testTargetFolder"
$TargetFolder = "\\AMYNAS\share\software\# Steam\backup"

# Exclude specific drives (Steam only supports one library per drive, so no need to be more specific), ex. $ExcludeDrives = @('Z', 'E', 'H', 'G')
#$ExcludeDrives = @('Z')
$ExcludeDrives = @('Z')

# Exclude specific app IDs, ex. $ExcludeAppIDs = @('26495', '7655', '4568') 
$ExcludeAppIDs = @()

# Log file / console output level. Accepts "None", "Standard", "Verbose", "Debug" (Verbose & Debug not currently being used)
$LogLevel = "Standard"

# Log file to use, ex. $LogFile = ".\Log.log"
$LogFile = ".\Logs\" + (Get-Date -f 'MM-dd-yyyy HHmmss') + ".log"

# Pause after execution (good for testing, bad for production)
$PausePostExecution = $false




<# ============== SCRIPT ============== #>

#region Initialization

# Import required modules. These two were obtained from https://github.com/ChiefIntegrator/Steam-GetOnTop
Import-Module .\Modules\SteamTools\SteamTools.psm1
Import-Module .\Modules\LogTools\LogTools.psm1

# Quick function to easily verify whether a path is excluded or not
function Confirm-PathNotExcluded ([string]$Path, [array]$ExclusionArray)
{
	foreach ($Exclusion in $ExclusionArray)
	{
		if ($Path -like "$Exclusion*")
		{
			return $false
		}
	}
	
	return $true
}

# After testing a ton of alternatives as well as trying my own, this is what I ended up using based on https://stackoverflow.com/a/25334958
# This shows a simplistic per-file progress without affecting time to completion all that much.
# Another alternative I tried had a fancier progress window but took 45% longer to complete, which is unacceptable when dealing with >1 TB libraries
function Copy-WithProgressBars
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Source
		 ,
		[Parameter(Mandatory = $true)]
		[string]$Destination
		 ,
		[Parameter(Mandatory = $true)]
		[string]$Name
	)
	
	# Dummy progress report as robocopy won't return anything until after it have compared source with dest
	Write-Progress "Comparing source and destination folders..." -Activity "Processing '$Name'" -CurrentOperation "" -ErrorAction SilentlyContinue;
	
	# Copy the files over!
	robocopy $Source $Destination /E /NDL /NJH /NJS | %{ $data = $_.Split([char]9); if ("$($data[4])" -ne "") { $file = "$($data[4])" }; Write-Progress "File percentage $($data[0])" -Activity "Processing '$Name'" -CurrentOperation "$($file)" ; }
}

#endregion Initialization


#region Start logging

Set-LogPath $LogFile
Set-LogLevel $LogLevel

if ($LogLevel -ne "None")
{
	New-Item -Path $LogFile -ItemType File -Force | Out-Null
	Write-LogHeader -InputObject "Backup-SteamGames.ps1"
}
Write-Log -InputObject " "

#endregion Start logging


#region Add Steam libraries

$SteamLibraries = New-Object System.Collections.ArrayList
$SteamPath = Get-SteamPath
Write-Log -InputObject "Steam is installed in '$SteamPath'"
$SteamLibraryFolders = ConvertFrom-VDF -InputObject (Get-Content "$SteamPath\steamapps\libraryfolders.vdf" -Encoding UTF8)

# Add main Steam library?
if (Confirm-PathNotExcluded -Path $SteamPath -ExclusionArray $ExcludeDrives)
{
	Write-Log -InputObject "Added library: '$SteamPath'"
	$SteamLibraries.Add($SteamPath) | Out-Null
}
else
{
	Write-Log -InputObject "Excluded library: '$SteamPath'"
}

# Add secondary Steam libraries?
for ($i = 1; $true; $i++)
{
	if ($null -eq $SteamLibraryFolders.LibraryFolders."$i")
	{
		break
	}
	
	$path = $SteamLibraryFolders.LibraryFolders."$i".Replace("\\", "\")
	
	if (Confirm-PathNotExcluded -Path $path -ExclusionArray $ExcludeDrives)
	{
		Write-Log -InputObject "Added library: '$path'"
		$SteamLibraries.Add($path) | Out-Null
	}
	else
	{
		Write-Log -InputObject "Excluded library: '$path'"
	}
}

#endregion Add Steam libraries


#region Main loop and execution (where the magic happens)

# Loop through each library

:libraryLoop foreach ($Library in $SteamLibraries)
{
	$Apps = New-Object System.Collections.ArrayList
	$SkippedApps = New-Object System.Collections.ArrayList
	Write-Log -InputObject " "
	Write-Log -InputObject " "
	Write-Log -InputObject "Processing library '$Library'..."
	
	# Read all appmanifests for the current library and throw them in a fitting array
	$AppManifests = Get-ChildItem -Path "$Library\steamapps\appmanifest_*.acf" | Select-Object -ExpandProperty FullName
	foreach ($AppManifest in $AppManifests)
	{
		$importedApp = ConvertFrom-VDF -InputObject (Get-Content -Path $AppManifest -Encoding UTF8) | Select-Object -ExpandProperty AppState
		
		if ($ExcludeAppIDs -contains $importedApp.appid -or $importedApp.StateFlags -ne 4)
		{
			$SkippedApps.Add($importedApp) | Out-Null
		}
		else
		{
			$Apps.Add($importedApp) | Out-Null
		}
	}
	
	Write-Log -InputObject "Found $($Apps.Count) item(s) ready to be backed up, and $($SkippedApps.Count) item(s) to skip."
	
	# List skipped apps, if any exist
	if ($SkippedApps.Count -gt 0)
	{
		Write-Log -InputObject "Skipped items: "
		$SkippedApps | foreach { Write-Log -InputObject "	$($_.appid), '$($_.name)'" }
	}
	
	
	# Loop through each manifest of the current library
	
	Write-Log -InputObject " "
	:manifestLoop foreach ($App in $Apps)
	{
		Write-Log -InputObject "Processing app $($App.appid), '$($App.name)'..."
		$source = ($Library + "\steamapps\common\" + $App.installdir)
		$destination = ($TargetFolder + "\" + $App.appid + "\" + $App.buildid)
		$command = 0
		
		if (Test-Path -Path $TargetFolder)
		{
			$command = Measure-Command {
				# Convert the app name into a safe file name to use
				$safeFileName = [String]::Join("", $App.name.Split([System.IO.Path]::GetInvalidFileNameChars()))
				
				Write-Log -InputObject "	Source: $source"
				Write-Log -InputObject "	Destination: $destination"
				
				# Copy appmanifest_#.acf file (this action also creates the target directory if it is missing)
				robocopy "$Library\steamapps" $destination "appmanifest_$($App.appid).acf" /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
				
				# Create dummy text with safe game title (this fails if the target directory haven't been created yet)
				New-Item -Path ($TargetFolder + "\" + $App.appid + "\" + $safeFileName + ".txt") -ItemType file -ErrorAction SilentlyContinue | Out-Null
				
				# Copy the install folder
				Copy-WithProgressBars -Source $source -Destination ($destination + "\" + $App.installdir) -Name $App.name
				
				# Simple steam_appid.txt creation to allow the game to be launched ouside of the regular install folder.
				# Note that since this doesn't check executable location, this file might be misplaced in some instances.
				# Oh, and don't overwrite it if it already exists (can otherwise cause issues with non-standard applications)
				$FileSteamAppID = ($destination + "\" + $App.installdir + "\steam_appid.txt")
				if ((Test-Path -Path $FileSteamAppID) -eq $false)
				{
					Out-File -FilePath $FileSteamAppID -InputObject $App.appid -Encoding ASCII -NoNewline
				}
			}
			
			Write-Log -InputObject "Task finished in $("{0:D2}" -f $command.Hours):$("{0:D2}" -f $command.Minutes):$("{0:D2}" -f $command.Seconds).$("{0:D3}" -f $command.Milliseconds)."
			Write-Log -InputObject " "
		}
		else
		{
			Write-Log -InputObject "'$TargetFolder' is not reachable or does not exist!" -MessageLevel Error
			break libraryLoop
		}
		
		<#
		$object = New-Object –TypeName PSObject
		$object | Add-Member –MemberType NoteProperty –Name App –Value $App.appid
		$object | Add-Member –MemberType NoteProperty –Name Build –Value $App.buildid
		$object | Add-Member –MemberType NoteProperty –Name Duration –Value $command
		$object | Add-Member –MemberType NoteProperty –Name Name –Value $App.name
		$object | Add-Member –MemberType NoteProperty –Name Source –Value $source
		$object | Add-Member –MemberType NoteProperty –Name Destination –Value $destination
		Write-Output $object
		#>
	}
	
	Write-Log -InputObject "Library complete."
}

#endregion Main loop and execution (where the magic happens)


#region Post-execution stuff

if ($LogLevel -ne "None")
{
	Write-LogFooter -InputObject "All libraries have been processed."
}

if ($PausePostExecution)
{
	pause
}

#endregion Post-execution stuff