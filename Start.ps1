$vmserver =@("scavm101","scavm102")
$SiteServer = 'SCACM101.sca.oper.no'
$SiteCode = 'SCX'
#$CollectionName = 'Prg-SCA-SoftwareUpdates-Device'
$CollectionName = 'Prg-Oleksii-Device'

$host.ui.RawUI.WindowTitle = "Snapshot Updater: collecting information..."

#Get all members from a collection
$Collections = Get-WmiObject -ComputerName $SiteServer -Namespace  "ROOT\SMS\site_$SiteCode" -Class SMS_Collection | where {$_.Name -like "$CollectionName"}
$computers = New-Object System.Collections.ArrayList
foreach ($Collection in $Collections){
    $SMSClients = Get-WmiObject -ComputerName $SiteServer -Namespace  "ROOT\SMS\site_$SiteCode" -Query "SELECT * FROM SMS_FullCollectionMembership WHERE CollectionID='$($Collection.CollectionID)' order by name" | select *
    foreach ($SMSClient in $SMSClients){
        $computers.Add($SMSClient.Name) > $null
    }
}

$host.ui.RawUI.WindowTitle = "Snapshot Updater: starting jobs ..."
#Start job for collection members only
foreach ($vms in $vmserver) {
    $vm = Get-VM -ComputerName $vms
    foreach($v in $vm){
        If ($computers.Contains($v.name.substring(4))) {
            #Write-host $v.name
            Start-Job -Name $v.name -filepath ($PSScriptRoot+"\Jobs.ps1") -ArgumentList $v.name,$vms|Select-Object -Property ID,Name|Format-List
            Start-Sleep -Seconds 10

        }
    }
}
$host.ui.RawUI.WindowTitle = "Snapshot Updater: waiting for jobs ..."
Get-Job | Wait-Job
#Get-Job | Stop-Job; Get-Job | Remove-Job