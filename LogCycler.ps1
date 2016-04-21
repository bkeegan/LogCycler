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
		
		[parameter(Mandatory=$false)]
		[alias("ld")] 
		[int]$lowDiskThreshold
		
		[parameter(Mandatory=$false)]
		[alias("ex")] 
		[int]$expireAfter
		
	)
	
	$dateStamps = @()
	
	
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
	
	#zip up log files (targets any files in the directory that are not other directories or zip files (which should be there from previous times this script was run))
	$logFiles = Get-ChildItem $logLocation | where {$_.Attributes -ne "Directory" -and $_.Extension -ne ".zip"} | Sort LastWriteTime
	Foreach($logFile in $logFiles)
	{
		
		$dateStamp =  "$($logFile.LastWriteTime.Month)" + "$($logFile.LastWriteTime.Day)" + "$($logFile.LastWriteTime.Year)"
		if(!(Test-Path $logLocation\$dateStamp))
		{
			New-Item $logLocation\$dateStamp -ItemType Directory | out-Null
		}
		
		Move-Item $logFile.FullName "$logLocation\$dateStamp"
		$logDirectories = Get-ChildItem $logLocation -Directory | where {$_.Name -match "\d{6,8}"}
		foreach($logDirectory in $logDirectories)
		{
			$logDirectory
			[System.IO.Compression.ZipFile]::CreateFromDirectory("$($logDirectory.FullName)", "$logLocation\$($logDirectory.name).zip") 
			Remove-Item $logDirectory.Fullname -Force -Recurse
		}
	}
	
	#deletes zipped log files if they are older than the number of days specified
	if($expireAfter)
	{
		$currentDate = Get-Date
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
