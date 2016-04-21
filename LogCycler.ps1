<# 
.SYNOPSIS 
	Cycles log files in a specified folder.
.DESCRIPTION 
	Cycles log files in a specified folder. Default behavior is to compress log files with the same date modified day,month,year in a zip file. 
	Can optionally delete log files if free disk space drops below a specified amount or delete log files that are older than a specified number of days.
	Script will delete only delete .zip files and will start with the oldest (based on lastWriteTime). Will delete the minimum amount of files to get the freespace above the specified threshold.
.NOTES 
    File Name  : LogCycler.ps1
    Author     : Brenton keegan - brenton.keegan@gmail.com 
    Licenced under GPLv3  
.LINK 
	https://github.com/bkeegan/LogCycler
    License: http://www.gnu.org/copyleft/gpl.html
.EXAMPLE 
	Will zip log files located in "C:\ProgramFolder\LogFiles" and delete previous created zip files should the free space drop below 1 GB (1024 MB)
	LogCycler -l "C:\ProgramFolder\LogFiles" -ld 1024
#> 

#imports
Add-Type -Assembly "System.IO.Compression.FileSystem" ;

Function LogCycler 
{
	[cmdletbinding()]
	Param
	(
		[parameter(Mandatory=$true)]
		[alias("l")] 
		[string]$logLocation,
		#file path of log location
		
		[parameter(Mandatory=$false)]
		[alias("ld")] 
		[int]$lowDiskThreshold,
		#clear oldest log archives if freespace drops below this size (in MB)
		
		[parameter(Mandatory=$false)]
		[alias("a")] 
		[int]$ageOfFilesToArchive=30,
		#archive files this may days or older - sent to zero to ignore
		
		[parameter(Mandatory=$false)]
		[alias("ex")] 
		[int]$expireAfter
		#delete pre-created archives older than this number of days
		
	)
	
	#if a low disk threshold is set, clear the minimum amount of files to get the freespace above the specified threshold.
	#this operation is done first in order to prevent the disk from filling while zip files are created.
	If($lowDiskThreshold)
	{
		$targetDrive = $logLocation.substring(0,2)
		$thresholdInBytes = 1MB * $lowDiskThreshold
		$disk = Get-WmiObject Win32_LogicalDisk -ComputerName . -Filter "DeviceID='$targetDrive'" | Select-Object Size,FreeSpace
		$freeSpace = $disk.FreeSpace
		if($freeSpace -lt $thresholdInBytes)
		{
			$amtToClear = $thresholdInBytes - $freeSpace
			$zippedLogs = Get-ChildItem $logLocation | where {$_.Extension -eq ".zip"} | Sort LastWriteTime
			Foreach($zippedLog in $zippedLogs)
			{
				#keeps track of total amount of bytes cleared
				$totalDeleted += $zippedLog.length
				Remove-Item $zippedLog.FullName
				If($totalDeleted -ge $amtToClear)
				{
					#stop deleting files once the total amount deleted is greater or equal to the target amount to clear (which means the freespace should be over the threshold)
					break
				}
			}
		}
	}

	$currentDate = Get-Date
	$ageThesholdTS = New-Timespan -Days $ageOfFilesToArchive
	$ageTheshold = $currentDate.Subtract($ageThesholdTS)
	
	#zip up log files (targets any files in the directory that are not other directories or zip files (which should be there from previous times this script was run))
	$logFiles = Get-ChildItem $logLocation | where {$_.Attributes -ne "Directory" -and $_.Extension -ne ".zip" -and $_.LastWriteTime -le $ageTheshold} | Sort LastWriteTime
	Foreach($logFile in $logFiles)
	{
		#attempts to open each for for writing, if fails determines file is locked and skips archival process for that file.
		$canOpen=$true
		Try { [IO.File]::OpenWrite($logFile.Name).close()}
		Catch {$canOpen=$true}
		if($canOpen)
		{
			#creates a directory with a datestamp of the log file and moves the log file into it. 
			$dateStamp =  "$($logFile.LastWriteTime.Month)" + "$($logFile.LastWriteTime.Day)" + "$($logFile.LastWriteTime.Year)"
			if(!(Test-Path $logLocation\$dateStamp))
			{
				New-Item $logLocation\$dateStamp -ItemType Directory | out-Null
			}
			Move-Item $logFile.FullName "$logLocation\$dateStamp"
		}
	}	
	
	#get a list of directories created by this script
	$logDirectories = Get-ChildItem $logLocation -Directory | where {$_.Name -match "\d{6,8}"}
	foreach($logDirectory in $logDirectories)
	{
		#if a zip file doesn't exist for that directory name - create a zip file out of it.
		if(!(Test-Path "$logLocation\$($logDirectory.name).zip"))
		{
			[System.IO.Compression.ZipFile]::CreateFromDirectory("$($logDirectory.FullName)", "$logLocation\$($logDirectory.name).zip") 
		}
		#else open the zip file for updating. The code below will keep searching thru the list of entries to see if an entry of the same name exists, if it does, it will keep prepending $i- until a open value is found.
		#for example if LogFile.log already exists in the .zip file, it will add the new LogFile.log file as 1-LogFile.log. If 1-LogFile.log exists, it will add 
		else
		{
			$existingZipFile =  [System.IO.Compression.ZipFile]::Open("$logLocation\$($logDirectory.name).zip","Update")
			$subLogFiles = Get-ChildItem $logDirectory.Fullname
			foreach($subLogFile in $subLogFiles)
			{
				if($existingZipFile.Entries.Fullname.Contains("$($subLogFile.name)"))
				{
					$i = 0
					$nameFound = $false
					while(!($nameFound))
					{
						$i++ 
						if(!($existingZipFile.Entries.Fullname.Contains("$i-$($subLogFile.name)")))
						{
							$nameFound = $true
							$newZipEntry = "$i-$($subLogFile.name)"
						}
					}
				}
				else
				{
					$newZipEntry = "$($subLogFile.name)"
				}
				[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($existingZipFile, "$($subLogFile.FullName)",$newZipEntry,"optimal")
				$existingZipFile.Dispose()
			}
		}
		Remove-Item $logDirectory.Fullname -Force -Recurse
	}
	
	#deletes zipped log files if they are older than the number of days specified
	if($expireAfter)
	{
		
		$zippedLogs = Get-ChildItem $logLocation | where {$_.Extension -eq ".zip"}
		foreach($zippedLog in $zippedLogs)
		{
			$cutOffDate = $zippedLog.LastWriteTime.AddDays($expireAfter)
			if($cutOffDate -le $currentDate)
			{
				Remove-Item $zippedLog.FullName -Force -Recurse
			}
		}
	}
}
