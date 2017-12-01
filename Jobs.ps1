$VirtualMachineName = $args[0]
$vms = $args[1]

$netbiosname = $VirtualMachineName.substring(4)

# Logs
$LogPath = "\\scafs001\PkgTmp\_TemporaryPackages\et5347\Snapshot Updater WMF 5.1\Logs\"
$LogFile = $LogPath + $VirtualMachineName + ".log"
$ReportFile = $LogPath + "Report.csv"

# Checks (Task Sequence will create NETBIOSNAME.chk or NETBIOSNAME.bad)

$CheckFolder = "\\scafs001\PkgTmp\_TemporaryPackages\et5347\Snapshot Updater WMF 5.1\Check\"
$CheckFolderBackup = "\\scafs001\PkgTmp\_TemporaryPackages\et5347\Snapshot Updater WMF 5.1\Check_Backup\"
$CheckFileOK = $CheckFolder + "*" + $netbiosname + ".chk"
$CheckFileER = $CheckFolder + "*" + $netbiosname + ".bad"

# Checking interval
$Chekouttime = 300
# Time to wait for installation
$Sleeptime = 6000
# New name of midified checkpoint
$NewSnapName = " - WMF-5.1"

if ((Test-Path $CheckFolder) -ne $true) {New-Item -Path $CheckFolder -type directory}
if ((Test-Path $CheckFolderBackup) -ne $true) {New-Item -Path $CheckFolder -type directory}
if ((Test-Path $LogPath) -ne $true) {New-Item -Path $LogPath -type directory}
If ((Test-Path $ReportFile) -ne $true) {"Check Date|VM Name|Snapshot Name|WMF 5.1 Installed|Last Updates installed on|User Name"| Out-File $ReportFile}

function Write-Log ($LogString, $LogFile)
{
    "$(Get-Date -Format yyyy-MM-dd", "HH:mm:ss) $LogString"| Out-File $LogFile -Append
}


function GetLastHotfixDate ()
{
$Result = $null
            Try {
                # Skip KBs installed with WMF 5.1 and HyperV Integration Servces (KB3158626)
                $GetRemoteHotfix = Invoke-Command -ScriptBlock {Get-hotfix | Where-Object { $_.HotFixID –notmatch "KB2809215|KB2872035|KB2872047|KB3033929|KB3191566|KB3191564|KB3191565|KB3158626"}} -ComputerName $netbiosname -ErrorAction Stop
            }
            Catch {
                $Result = $_.Exception.Message
                $FailedItem = $_.Exception.ItemName
            }
            if ($Result -eq $null) {
            [datetime]$LastUpdateInstalledOn = (($GetRemoteHotfix | Sort-Object -Property InstalledOn ).InstalledOn)[-1]
            $Result = $LastUpdateInstalledOn.ToString("dd.MM.yyyy")
            }
return $Result
}

Write-Log "******************************************* Start Logging *******************************************" $LogFile

# Stop VM
        Stop-VM -ComputerName $vms -VMName $VirtualMachineName -Force
# Get Snapshots
        $snaps = Get-VMSnapshot -ComputerName $vms -VMName $VirtualMachineName
# Exit script if there is no snapshots        
        If ($snaps.count -eq 0) {Write-Log "No Snapshots" $LogFile | Exit}
        
        Write-Log "--------------- Snapshots: ----------------" $LogFile
        $snaps.Name| Out-File $LogFile -Append
        Write-Log "-------------------------------------------" $LogFile

# Processing snapshots
foreach ($snap in $snaps)
{
    # Skip already created snapshots by name and all child snapshots
        If (($snap.name -notlike "*"+$NewSnapName+"*") -and ($Snap.ParentSnapshotName -notlike "*"+$NewSnapName+"*"))
        {
            If (Test-Path -Path $CheckFileOK){ Remove-Item -Path $CheckFileOK -force -ErrorAction Ignore}
            If (Test-Path -Path $CheckFileER){ Remove-Item -Path $CheckFileER -force -ErrorAction Ignore}
            Write-Log ("INFO: Checking snapshot: " + $snap.name) $LogFile

        # Restore Snapshot
            Write-Log " INFO: Restoring: 30 sec" $LogFile
            Restore-VMSnapshot -Name $snap.name -VMName $VirtualMachineName -ComputerName $vms -Confirm:$false
            Start-Sleep -Seconds 30
            $state = (Get-VM -ComputerName $vms -Name $VirtualMachineName).State
            Write-Log (" INFO: VM Status: " + $state) $LogFile
    
        # Restart VM if Running
            If ($state -eq "Running")
            {
                Write-Log " INFO: Restarting VM: 3 min" $LogFile
                Restart-VM -ComputerName $vms -VMName $VirtualMachineName -Force
                Start-Sleep -Seconds 180
            }

        # Start VM if Off
            If ( ($state -eq "Off") -or ($state -eq "Saved") )
            {
                Write-Log " INFO: Starting VM: 3 min" $LogFile
                Start-VM -ComputerName $vms -VMName $VirtualMachineName
                Start-Sleep -Seconds 180
            }
        
            Write-Log (" INFO: VM Status: " + (Get-VM -ComputerName $vms -Name $VirtualMachineName).State) $LogFile
    
        
        # Trigger application manager policy actions
            Write-Log " INFO: Trigger application manager policy actions:" $LogFile
            Invoke-WMIMethod -ComputerName $netbiosname -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000121}"
            Invoke-WMIMethod -ComputerName $netbiosname -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}"
            Invoke-WMIMethod -ComputerName $netbiosname -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000022}"
            Start-Sleep -Seconds 300
        
        # Wait for mandatory installation
            Write-Log (" INFO: Waiting for installation:" + $Sleeptime + " sec") $LogFile

            $time = 0
            $Installed = $false
            $NotInstalled = $false

            Do
            {
                if ($Installed -eq $true) {break}
                if ($NotInstalled -eq $true) {break}
                Start-Sleep -Seconds $Chekouttime
                $time = $time + $Chekouttime
                Write-Log (" INFO: Checking CHK or BAD:" + $time + "sec") $LogFile

                # If CHK file exists installation finished successfully
                If (Test-Path -Path $CheckFileOK)
                {
                    $Installed = $true
                    $NotInstalled = "skip"
                    copy-item -Path $CheckFileOK -Destination ($CheckFolderBackup + $netbiosname + " - OK - " + (get-date -uformat '%Y-%m-%d %H.%m.%S') + ".txt") -Force
                    $NewName = $snap.name + $NewSnapName
                    Write-Log " INFO: CHK file detected. Waiting for restart" $LogFile
                    Start-Sleep -Seconds 500
                    CHECKPOINT-VM -ComputerName $vms –Name $VirtualMachineName –Snapshotname $NewName
                    Write-Log (" OK: Software Installed. Saved new snapshot: "+ $NewName) $LogFile
                    $GetLastHotfixDate = $null
                    $GetLastHotfixDate = GetLastHotfixDate
                    Write-Log (" INFO: Last Hotfix Date: "+ $GetLastHotfixDate) $LogFile
                    Write-log ("|"+ $VirtualMachineName +"|" + $NewName +"|"+ "OK Installed"+"|"+$GetLastHotfixDate +"|"+ (Get-VM -ComputerName $vms -Name $VirtualMachineName).notes) $ReportFile
                }
                # If BAD file exists installation was not successfull
                Else
                {
                    If (Test-Path -Path $CheckFileER)
                    {
                        $NotInstalled = $true
                        $Installed = "skip"
                        copy-item -Path $CheckFileER -Destination ($CheckFolderBackup + $netbiosname + " - ER - " + (get-date -uformat '%Y-%m-%d %H.%m.%S') + ".txt") -Force
                        Write-Log " INFO: BAD file detected." $LogFile
                        Write-Log (" INFO: " + (Get-Content -Path $CheckFileER)) $LogFile
                        Start-Sleep -Seconds 300
                        Write-Log " ERROR: Failed updating VM." $LogFile
                        $GetLastHotfixDate = $null
                        $GetLastHotfixDate = GetLastHotfixDate
                        Write-Log (" INFO: Last Hotfix Date: "+ $GetLastHotfixDate) $LogFile
                        Write-log ("|"+ $VirtualMachineName +"|" + $snap.name +"|"+ "Error. Failed updating VM"+"|"+$GetLastHotfixDate +"|"+(Get-VM -ComputerName $vms -Name $VirtualMachineName).notes) $ReportFile
                    }
                }
                
            }
            While ($time -le $Sleeptime)
            
            if (($Installed -eq $false) -or ($NotInstalled -eq $false))
            {
            # TS was not executed
            Write-Log " ERROR: Software Not Installed. TS not launched" $LogFile
            $GetLastHotfixDate = $null
            $GetLastHotfixDate = GetLastHotfixDate
            Write-Log (" INFO: Last Hotfix Date: "+ $GetLastHotfixDate) $LogFile
            Write-log ("|"+ $VirtualMachineName +"|" + $snap.name +"|"+ "Error. TS not launched"+"|"+$GetLastHotfixDate +"|"+(Get-VM -ComputerName $vms -Name $VirtualMachineName).notes) $ReportFile
            }
        }
        Write-Log ("INFO: Skipped snapshot: "+ $snap.name) $LogFile
}


# Copy check files to backup folder
If (Test-Path -Path $CheckFileOK){ Remove-Item -Path $CheckFileOK -force -ErrorAction Ignore }
If (Test-Path -Path $CheckFileER){ Remove-Item -Path $CheckFileER -force -ErrorAction Ignore }

Write-Log "******************************************** End Logging ********************************************" $LogFile