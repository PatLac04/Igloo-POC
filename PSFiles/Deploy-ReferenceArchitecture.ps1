#******************************************************************************
# Script body
# Execution begins here
#******************************************************************************

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
$starttime = get-date

<#
#region Prep & signin
# sign in
gloo

# Define a credential object
$Linuxcred = Get-Credential -Message "UserName and Password for Linux VM"


#endregion
#>

#region Set Template and Parameter location

$Date=Get-Date -Format yyyyMMdd

# set  Root Uri of GitHub Repo (select AbsoluteUri)

$TemplateRootUriString = "https://raw.githubusercontent.com/pierreroman/Igloo-POC/master/"
$TemplateURI = New-Object System.Uri -ArgumentList @($TemplateRootUriString)

$VnetTemplate = $TemplateURI.AbsoluteUri + "vnet-subnet.json"
$DCTemplate = $TemplateURI.AbsoluteUri + "DC.json"
$StorageTemplate = $TemplateURI.AbsoluteUri + "VMStorageAccount.json"
$ASTemplate = $TemplateURI.AbsoluteUri + "AvailabilitySet.json"
$NSGTemplate = $TemplateURI.AbsoluteUri + "nsg.azuredeploy.json"
$DCTemplate = $TemplateURI.AbsoluteUri + "AD-2DC.json"

#endregion

#region Create the resource group

# Start the deployment
Write-Output "Starting deployment"

Get-AzureRmResourceGroup -Name $ResourceGroupName -ev notPresent -ea 0  | Out-Null

if ($notPresent) {
    Write-Output "Could not find resource group '$ResourceGroupName' - will create it."
    Write-Output "Creating resource group '$ResourceGroupName' in location '$Location'...."
    New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -Force | out-null

}
else {
    Write-Output "Using existing resource group '$ResourceGroupName'"
}

#endregion

#region Deployment of virtual network
Write-Output "Deploying virtual network..."
$DeploymentName = 'Vnet-Subnet-'+ $Date
New-AzureRmResourceGroupDeployment -Name $DeploymentName -ResourceGroupName $ResourceGroupName -TemplateUri $VnetTemplate -TemplateParameterObject `
    @{ `
        vnetname='Vnet-Igloo-POC'; `
        VnetaddressPrefix = '192.168.0.0/17'; `
        mgmtsubnetsname = 'mgmt'; `
        mgmtsubnetaddressPrefix = '192.168.105.0/24'; `
        publicdmzinsubnetsname = 'Inside'; `
        publicdmzinsubnetaddressPrefix = '192.168.114.0/24'; `
        publicdmzoutsubnetsname = 'Outside'; `
        publicdmzoutsubnetaddressPrefix = '192.168.113.0/24'; `
        websubnetsname = 'web'; `
        websubnetaddressPrefix = '192.168.115.0/24'; `
        bizsubnetsname = 'biz';`
        bizsubnetaddressPrefix = '192.168.116.0/24'; `
        datasubnetsname = 'data';`
        datasubnetaddressPrefix = '192.168.102.0/24'; `
        Gatewaysubnetsname = 'GatewaySubnet'; `
        GatewaysubnetaddressPrefix = '192.168.127.0/24'; `
    } -Force | out-null

#endregion

#region Deployment of Storage Account
Write-Output "Deploying Storage Accounts..."
$DeploymentName = 'storageAccount'+ $Date
New-AzureRmResourceGroupDeployment -Name $DeploymentName -ResourceGroupName $ResourceGroupName -TemplateFile $StorageTemplate -TemplateParameterObject `
    @{ `
        stdname = 'standardsa'; `
        premname = 'premiumsa'; `
    } -Force | out-null

#endregion

#region Deployment of Availability Sets

Write-Output "Starting deployment of Availability Sets"

$ASList = Import-CSV $VMListfile | Where-Object {$_.AvailabilitySet -ne "None"}
$ASListUnique = $ASList.AvailabilitySet | select-object -unique

ForEach ( $AS in $ASListUnique)
{
    $ASName=$AS
    $DeploymentName = $AS + $Date
    New-AzureRmResourceGroupDeployment -Name $DeploymentName -ResourceGroupName $ResourceGroupName -TemplateFile $ASTemplate -TemplateParameterObject `
        @{ AvailabilitySetName = $ASName.ToString() ; `
            faultDomains = 2 ; `
            updateDomains = 5 ; `
        } -Force | out-null
}
#endregion

#region Deployment of NSG

Write-Output "Starting deployment of NSG"

$NSGList = Import-CSV $VMListfile
$NSGListUnique = $NSGList.subnet | select-object -unique

ForEach ( $NSG in $NSGListUnique){
    $NSGName=$NSG+"-nsg"
    $DeploymentName = $AS + $Date
    New-AzureRmResourceGroupDeployment -Name $DeploymentName -ResourceGroupName $ResourceGroupName -TemplateUri $NSGTemplate -TemplateParameterObject `
        @{`
            networkSecurityGroupName=$NSGName.ToString(); `
         } -Force | out-null
}
#endregion

#region Deployment of DC
Write-Output "Deploying New Domain with Controller..."
$DeploymentName = 'Domain-DC-'+ $Date

$userName=$cred.UserName
$password=$cred.GetNetworkCredential().Password

New-AzureRmResourceGroupDeployment -Name $DeploymentName -ResourceGroupName $ResourceGroupName -TemplateUri $DCTemplate -TemplateParameterObject `
    @{ `
        storageAccountName = 'igloostdstore'; `
        DCVMName = 'poc-eus-dc1'; `
        adminUsername = $userName; `
        adminPassword = $password; `
        domainName = 'Iglooaz.local'
        adAvailabilitySetName = 'Igloo-POC-DC-AS'; `
        virtualNetworkName = 'Vnet-Igloo-POC'; `
    } -Force

#endregion

#region Update DNS with IP from DC set above

Write-Output "Updating Vnet DNS to point to the newly create DC..."

$vmname = "poc-eus-dc1"
$vms = get-azurermvm
$nics = get-azurermnetworkinterface | where VirtualMachine -NE $null #skip Nics with no VM

foreach($nic in $nics)
{
    $vm = $vms | where-object -Property Id -EQ $nic.VirtualMachine.id
    $prv =  $nic.IpConfigurations | select-object -ExpandProperty PrivateIpAddress
    if ($($vm.Name) -eq $vmname)
    {
        $IP = $prv
        break
    }
}

$vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $ResourceGroupName -name 'Vnet-Igloo-POC'
$vnet.DhcpOptions.DnsServers = $IP 
Set-AzureRmVirtualNetwork -VirtualNetwork $vnet | out-null

#endregion







$endtime = get-date
$procestime = $endtime - $starttime
$time = "{00:00:00}" -f $procestime.Minutes
write-host " Deployment completed in '$time' "









