param($eventGridEvent, $TriggerMetadata)

Write-Host "PowerShell event trigger function processed a request."
write-host ($eventGridEvent | Convertto-json -depth 99)
$resId = $eventGridEvent.subject
$eveSub = $eventGridEvent.subject.split('/')
$vmName = $eveSub[8]
$ResourceGroupName = $eveSub[4]
$subId = $eventGridEvent.data.subscriptionId
$tenId = $eventGridEvent.data.tenantId
write-host "**********Resource Id: $resId**********"
write-host "**********VM Name: $vmName**********"
write-host "**********ResourceGroup Name: $ResourceGroupName**********"
write-host "**********Subscription Id: $subId**********"
write-host "**********Tenant Id: $tenId**********"

#Credentials
#$Cred = 
#Connect-AzAccount -Tenant "a47921a6-a2af-4dc4-ab75-dad1f90abb7e" -SubscriptionId "44a626a6-fda6-4de1-8b2c-122c7ff52c5e"
#Connect-AzAccount -Credential $Cred
#Get Credentials
#Set-AzContext -Subscription "44a626a6-fda6-4de1-8b2c-122c7ff52c5e"


#Connect
Connect-AzAccount -Identity

#test
$secret1 = Get-AzKeyVaultSecret -VaultName "test-keyvault-osversion" -Name "test-msp-function-osversion-id"
$ssPtr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret1.SecretValue)
try {
   $appId = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr1)
} finally {
   [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr1)
}
Write-Host "*******Username: $appId"
$secret2 = Get-AzKeyVaultSecret -VaultName "test-keyvault-osversion" -Name "test-msp-function-osversion-pass"
$ssPtr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret2.SecretValue)
try {
    $appPass = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr2)
} finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr2)
}
Write-Host "*******Pass: $appPass"
#end test

$Credential = New-Object –TypeName System.Management.Automation.PSCredential –ArgumentList ($appId, (ConvertTo-SecureString $appPass –AsPlainText –Force))
Connect-AzAccount -Credential $Credential -TenantId $tenId -ServicePrincipal
Set-AzContext -Subscription $subId

#Get VM resource details
$vmStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -Status
If(-not ($vmStatus)){
    Throw 'ERROR! VM not found'
}
$vmPowerState = $vmStatus.Statuses[1].Code
write-host "***********VM Power State: $vmPowerState**********"

#OS validation
if($vmPowerState -eq "PowerState/running"){
    $resource = Get-AzResource -Name $vmName -ResourceGroupName $ResourceGroupName
    $osArray = @('Ubuntu 18.04-LTS','RHEL 7.x','WindowsServer 2016-Datacenter','WindowsServer 2019-Datacenter')
    If(-not ($resource)){
        Throw 'ERROR! Resource not found'
    }
    $tag = $resource.Tags
    $val = $tag["AtosManaged"]
    $vmOsTagValue = $tag["AtosOsVersion"]
    $osName = $vmStatus.OsName
    $osVersion = $vmStatus.OsVersion
    write-host "***********OS Name: $osName**********"
    write-host "***********OS Version: $osVersion**********"
    if($val -eq "True"){
        if($osArray -notcontains $vmOsTagValue){
            if($osName -eq "ubuntu" -And $osVersion -eq "18.04"){
                $vmOsTagValue = $osArray[0] 
            }
            elseif($osName -eq "redhat" -And $osVersion -cge 7){
                if($osVersion -clt 8){
                    $vmOsTagValue = $osArray[1]
                }
                else{
                    #Remove AtosOsVersion tag for unsupported OS
                    $deleteTags = @{"AtosOsVersion"=$vmOsTagValue}
                    Update-AzTag -ResourceId $resId -Tag $deleteTags -Operation Delete
                    Throw "Unsupported OS $osName VM resource found"
                }
            }
            elseif($osName -eq "Windows Server 2016 Datacenter"){
                $vmOsTagValue = $osArray[2]
            }
            elseif($osName -eq "Windows Server 2019 Datacenter"){
                $vmOsTagValue = $osArray[3]
            }else{
                Throw "Unsupported OS $osName VM resource found"
            }
            #Assign AtosOsVersion tag
            $mergedTags = @{"AtosOsVersion"=$vmOsTagValue}
            Update-AzTag -ResourceId $resId -Tag $mergedTags -Operation Merge
            Write-Host "AtosOsVersion tag has been added to VM $vmName"
        }else{
            if($osName -eq "ubuntu" -And $osVersion -eq "18.04"){
                $newOsName = $osArray[0] 
            }
            elseif($osName -eq "redhat" -And $osVersion -cge 7){
                if($osVersion -clt 8){
                    $newOsName = $osArray[1]
                }
                else{
                    #Remove AtosOsVersion tag for unsupported OS
                    $deleteTags = @{"AtosOsVersion"=$vmOsTagValue}
                    Update-AzTag -ResourceId $resId -Tag $deleteTags -Operation Delete
                    Throw "Unsupported OS $osName found for VM $vmName"
                }
            }
            elseif($osName -eq "Windows Server 2016 Datacenter"){
                $newOsName = $osArray[2]
            }
            elseif($osName -eq "Windows Server 2019 Datacenter"){
                $newOsName = $osArray[3]
            }
            if(-not ($newOsName)){
                #Remove AtosOsVersion tag for unsupported OS
                $deleteTags = @{"AtosOsVersion"=$vmOsTagValue}
                Update-AzTag -ResourceId $resId -Tag $deleteTags -Operation Delete
                Throw "Unsupported OS $osName found for VM $vmName"
            }
            else{
                if($vmOsTagValue -ne $newOsName){
                    #Assign AtosOsVersion tag
                    $mergedTags = @{"AtosOsVersion"=$newOsName}
                    Update-AzTag -ResourceId $resId -Tag $mergedTags -Operation Merge
                    Write-Host "AtosOsVersion Tag is incorrect, hence tag has been updated for VM $vmName"
                }else{
                    Write-Host "VM $vmName already assgined with correct AtosOsVersion tag"
                }
            }
        }
    }
    else {
        Write-Host "AtosManaged:True tag is missing. This VM $vmName is not managed by Atos"
    }
}
else{
    Write-Host "VM is not running, hence OS details not validated"
}