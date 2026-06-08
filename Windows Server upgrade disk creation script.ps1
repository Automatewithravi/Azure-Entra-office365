#
# Customer specific parameters
# Resource group of the source VM
$resourceGroup = "WS2025-Upgrade-RG"
# Location of the source VM
$location = "UKSouth"
# Zone of the source VM, if any
$zone = ""
# Disk name for the that will be created
$diskName = "WS2025-Upgrade-OSDisk"
# Target version for the upgrade - must be one of these five strings: server2025Upgrade, server2022Upgrade, server2019Upgrade, server2016Upgrade or server2012Upgrade
$sku = "server2025Upgrade"
# Common parameters
$publisher = "MicrosoftWindowsServer"
$offer = "WindowsServerUpgrade"
$managedDiskSKU = "Standard_LRS"
#
# Get the latest version of the special (hidden) VM Image from the Azure Marketplace
$versions = Get-AzVMImage -PublisherName $publisher -Location $location -Offer $offer -Skus $sku | sort-object -Descending {[version] $_.Version	}
$latestString = $versions[0].Version
# Get the special (hidden) VM Image from the Azure Marketplace by version - the image is used to create a disk to upgrade to the new version
$image = Get-AzVMImage -Location $location -PublisherName $publisher -Offer $offer -Skus $sku -Version $latestString
#
# Create Resource Group if it doesn't exist
#
if (-not (Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $resourceGroup -Location $location    
}
#
# Create managed disk from LUN 0
#
if ($zone){
    $diskConfig = New-AzDiskConfig -SkuName $managedDiskSKU -CreateOption FromImage -Zone $zone -Location $location
} else {
    $diskConfig = New-AzDiskConfig -SkuName $managedDiskSKU -CreateOption FromImage -Location $location
}
Set-AzDiskImageReference -Disk $diskConfig -Id $image.Id -Lun 0
New-AzDisk -ResourceGroupName $resourceGroup -DiskName $diskName -Disk $diskConfig
