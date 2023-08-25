# get paramteres from json files
$secretParameters = Get-Content -Raw -Path '.\secrets.json' | ConvertFrom-Json
$parameters = Get-Content -Raw -Path '.\parameters.json' | ConvertFrom-Json

$SubscriptionID = $secretParameters.SubscriptionID
$resourceGroupName = $parameters.resourceGroupName
$location = $parameters.location
$vnetName = $parameters.vnetName
$vnetAddressPrefix = $parameters.vnetAddressPrefix
$subnetName = $parameters.subnetName
$subnetAddressPrefix = $parameters.subnetAddressPrefix

$keyVaultName = $parameters.keyVaultName
$encryptionKeyName = "DiskEncryptionCMK"

$DESEncryptionAtRestWithCustomerKeyName = $parameters.DESEncryptionAtRestWithCustomerKeyName
$DESConfidentialVmEncryptedWithCustomerKeyName = $parameters.DESConfidentialVmEncryptedWithCustomerKeyName
$DESEncryptionAtRestWithPlatformAndCustomerKeysName = $parameters.DESEncryptionAtRestWithPlatformAndCustomerKeysName

$adminUsername = $secretParameters.adminUsername
$adminPassword = $secretParameters.adminPassword
$image = $parameters.image

$BackupVaultName = $parameters.BackupVaultName
$AZBUidentityName = $parameters.AZBUidentityName

az account set --subscription $SubscriptionID

# Create resource group
az group create --name $resourceGroupName --location $location

# Create virtual network
az network vnet create `
    --name $vnetName `
    --resource-group $resourceGroupName `
    --location $location `
    --address-prefixes $vnetAddressPrefix

# Create subnet
az network vnet subnet create `
    --name $subnetName `
    --resource-group $resourceGroupName `
    --vnet-name $vnetName `
    --address-prefixes $subnetAddressPrefix

# Create key vault
az keyvault create `
    --name $keyVaultName `
    --resource-group $resourceGroupName `
    --location $location `
    --sku premium `
    --enable-rbac-authorization true `
    --enable-purge-protection true `
    --retention-days 8

$keyVaultID = $(az keyvault show --resource-group $resourceGroupName --name $keyVaultName --query id --output tsv)

#give yourself permissions on the keyvault
$azureCurrentLoggedOnUserUPN = $(az ad signed-in-user show --query userPrincipalName --output tsv)
az role assignment create `
    --role "Key vault Administrator"  `
    --assignee $azureCurrentLoggedOnUserUPN  `
    --scope $keyVaultID

# Create encryption key
az keyvault key create `
    --name $encryptionKeyName `
    --vault-name $keyVaultName `
    --protection software
####------------------------------------------------------------------------------------------------------------------------------------


# Create an identity for the backup vault to access the key
az identity create `
  --name $AZBUidentityName `
  --resource-group $resourceGroupName

# Grant the backup access to the keys in the key vault (not sure if the permissions are least privilege)
$backupServicePrincipalObjectId = (az identity show --resource-group $resourceGroupName --name $AZBUidentityName --query principalId --output tsv)

az role assignment create `
    --role "Key Vault Administrator"  `
    --assignee-object-id $backupServicePrincipalObjectId  `
    --assignee-principal-type "ServicePrincipal" `
    --scope $keyVaultID

# Create a backup vault
az backup vault create `
    --name $BackupVaultName `
    --resource-group $resourceGroupName `
    --location $location

# assign the identity to the backup vault
$backupServiceId = (az identity show --resource-group $resourceGroupName --name $AZBUidentityName --query id --output tsv)
az backup vault identity assign `
    --user-assigned $backupServiceId `
    --resource-group $resourceGroupName `
    --name $BackupVaultName

####------------------------------------------------------------------------------------------------------------------------------------

# Create disk encryption sets for CMK
az disk-encryption-set create `
    --name $DESEncryptionAtRestWithCustomerKeyName `
    --resource-group $resourceGroupName `
    --location $location `
    --source-vault $keyVaultName `
    --encryption-type "EncryptionAtRestWithCustomerKey" `
    --enable-auto-key-rotation true `
    --key-url $(az keyvault key show --name $encryptionKeyName --vault-name $keyVaultName --query [key.kid] -o tsv)

# create an identity for the disk set to access the key
$desIdentity = az disk-encryption-set show -n $DESEncryptionAtRestWithCustomerKeyName --resource-group $resourceGroupName --query [identity.principalId] --output tsv

# Grant permissions to disk encryption set
az role assignment create `
    --role "Key Vault Crypto Service Encryption User" `
    --assignee-principal-type ServicePrincipal `
    --assignee-object-id $desIdentity `
    --scope $keyVaultID


# Create disk encryption sets for CMK + Confidential VM encryption
az disk-encryption-set create `
    --name $DESConfidentialVmEncryptedWithCustomerKeyName `
    --resource-group $resourceGroupName `
    --location $location `
    --source-vault $keyVaultName `
    --encryption-type "ConfidentialVmEncryptedWithCustomerKey" `
    --enable-auto-key-rotation true `
    --key-url $(az keyvault key show --name $encryptionKeyName --vault-name $keyVaultName --query [key.kid] -o tsv)

# create an identity for the disk set to access the key
$desIdentity = az disk-encryption-set show -n $DESConfidentialVmEncryptedWithCustomerKeyName --resource-group $resourceGroupName --query [identity.principalId] --output tsv

# Grant permissions to disk encryption set
az role assignment create `
    --role "Key Vault Crypto Service Encryption User" `
    --assignee-principal-type ServicePrincipal `
    --assignee-object-id $desIdentity `
    --scope $keyVaultID


# Create disk encryption sets for CMK
az disk-encryption-set create `
    --name $DESEncryptionAtRestWithPlatformAndCustomerKeysName `
    --resource-group $resourceGroupName `
    --location $location `
    --source-vault $keyVaultName `
    --encryption-type "EncryptionAtRestWithPlatformAndCustomerKeys" `
    --enable-auto-key-rotation true `
    --key-url $(az keyvault key show --name $encryptionKeyName --vault-name $keyVaultName --query [key.kid] -o tsv)

# create an identity for the disk set to access the key
$desIdentity = az disk-encryption-set show -n $DESEncryptionAtRestWithPlatformAndCustomerKeysName --resource-group $resourceGroupName --query [identity.principalId] --output tsv

# Grant permissions to disk encryption set
az role assignment create `
    --role "Key Vault Crypto Service Encryption User" `
    --assignee-principal-type ServicePrincipal `
    --assignee-object-id $desIdentity `
    --scope $keyVaultID


####------------------------------------------------------------------------------------------------------------------------------------
# Create standard VM with default encryption and PMK
az vm create `
    --name "VM01" `
    --resource-group $resourceGroupName `
    --location $location `
    --image $image `
    --admin-username $adminUsername `
    --admin-password $adminPassword `
    --vnet-name $vnetName `
    --subnet $subnetName `
    --public-ip-address '""' `
    --nsg '""' `
    --size "Standard_D2s_v5"

# Create standard VM with default encryption and CMK
az vm create `
    --name "VM02" `
    --resource-group $resourceGroupName `
    --location $location `
    --image $image `
    --admin-username $adminUsername `
    --admin-password $adminPassword `
    --vnet-name $vnetName `
    --subnet $subnetName `
    --public-ip-address '""' `
    --nsg '""' `
    --size "Standard_D2s_v5" `
    --os-disk-encryption-set $DESEncryptionAtRestWithCustomerKeyName

# Create standard VM with host encryption and PMK
az vm create `
    --name "VM03" `
    --resource-group $resourceGroupName `
    --location $location `
    --image $image `
    --admin-username $adminUsername `
    --admin-password $adminPassword `
    --vnet-name $vnetName `
    --subnet $subnetName `
    --public-ip-address '""' `
    --nsg '""' `
    --size "Standard_D2s_v5" `
    --encryption-at-host true

# Create standard VM with host encryption and CMK
az vm create `
    --name "VM04" `
    --resource-group $resourceGroupName `
    --location $location `
    --image $image `
    --admin-username $adminUsername `
    --admin-password $adminPassword `
    --vnet-name $vnetName `
    --subnet $subnetName `
    --public-ip-address '""' `
    --nsg '""' `
    --size "Standard_D2s_v5" `
    --os-disk-encryption-set $DESEncryptionAtRestWithCustomerKeyName `
    --encryption-at-host true


####------------------------------------------------------------------------------------------------------------------------------------
# Create confidential VM with default encryption and PMK;  VMGuestStateOnly
az vm create `
    --name "VM05" `
    --resource-group $resourceGroupName `
    --location $location `
    --image $image `
    --admin-username $adminUsername `
    --admin-password $adminPassword `
    --vnet-name $vnetName `
    --subnet $subnetName `
    --public-ip-address '""' `
    --nsg '""' `
    --size "Standard_DC2as_v5" `
    --security-type "ConfidentialVM" `
    --enable-vtpm true `
    --enable-secure-boot true `
    --os-disk-security-encryption-type "VMGuestStateOnly"

# Create confidential VM with default encryption and PMK,:  DiskWithVMGuestState
az vm create `
    --name "VM06" `
    --resource-group $resourceGroupName `
    --location $location `
    --image $image `
    --admin-username $adminUsername `
    --admin-password $adminPassword `
    --vnet-name $vnetName `
    --subnet $subnetName `
    --public-ip-address '""' `
    --nsg '""' `
    --size "Standard_DC2as_v5" `
    --security-type "ConfidentialVM" `
    --enable-vtpm true `
    --enable-secure-boot true `
    --os-disk-security-encryption-type "DiskWithVMGuestState"


# Create confidential VM with default encryption and CMK VMGuestStateOnly 
# !!!! incompatible combination, deployment fails
az vm create `
    --name "VM07" `
    --resource-group $resourceGroupName `
    --location $location `
    --image $image `
    --admin-username $adminUsername `
    --admin-password $adminPassword `
    --vnet-name $vnetName `
    --subnet $subnetName `
    --public-ip-address '""' `
    --nsg '""' `
    --size "Standard_DC2as_v5" `
    --security-type "ConfidentialVM" `
    --enable-vtpm true `
    --enable-secure-boot true `
    --os-disk-security-encryption-type "VMGuestStateOnly" `


# Create confidential VM with default encryption and CMK DiskWithVMGuestState
az vm create `
    --name "VM08" `
    --resource-group $resourceGroupName `
    --location $location `
    --image $image `
    --admin-username $adminUsername `
    --admin-password $adminPassword `
    --vnet-name $vnetName `
    --subnet $subnetName `
    --public-ip-address '""' `
    --nsg '""' `
    --size "Standard_DC2as_v5" `
    --security-type "ConfidentialVM" `
    --enable-vtpm true `
    --enable-secure-boot true `
    --os-disk-security-encryption-type "DiskWithVMGuestState" `
    --os-disk-secure-vm-disk-encryption-set $DESConfidentialVmEncryptedWithCustomerKeyName

# Create confidential VM with default encryption and PMK + Host based encryption
# !!!! incompatible combination, deployment fails
az vm create `
    --name "VM09" `
    --resource-group $resourceGroupName `
    --location $location `
    --image $image `
    --admin-username $adminUsername `
    --admin-password $adminPassword `
    --vnet-name $vnetName `
    --subnet $subnetName `
    --public-ip-address '""' `
    --nsg '""' `
    --size "Standard_DC2as_v5" `
    --security-type "ConfidentialVM" `
    --enable-vtpm true `
    --enable-secure-boot true `
    --os-disk-security-encryption-type "VMGuestStateOnly" `
    --encryption-at-host true `
    --os-disk-encryption-set $DESConfidentialVmEncryptedWithCustomerKeyName

# Create confidential VM with default encryption and CMK + Host based encryption + confidential ecrypted VM
az vm create `
    --name "VM10" `
    --resource-group $resourceGroupName `
    --location $location `
    --image $image `
    --admin-username $adminUsername `
    --admin-password $adminPassword `
    --vnet-name $vnetName `
    --subnet $subnetName `
    --public-ip-address '""' `
    --nsg '""' `
    --size "Standard_DC2as_v5" `
    --security-type "ConfidentialVM" `
    --enable-vtpm true `
    --enable-secure-boot true `
    --os-disk-security-encryption-type "DiskWithVMGuestState" `
    --encryption-at-host true `
    --os-disk-secure-vm-disk-encryption-set $DESConfidentialVmEncryptedWithCustomerKeyName


####------------------------------------------------------------------------------------------------------------------------------------
az disk create `
    --name "datadisk01_EncryptionAtRestWithPlatformKey" `
    --resource-group $resourceGroupName `
    --location $location `
    --size-gb 128 `
    --sku "Premium_LRS"

az vm disk attach `
    --resource-group $resourceGroupName `
    --vm-name "VM10" `
    --name "datadisk01_EncryptionAtRestWithPlatformKey"


az disk create `
    --name "datadisk02_EncryptionAtRestWithCustomerKey" `
    --resource-group $resourceGroupName `
    --location $location `
    --size-gb 128 `
    --sku "Premium_LRS" `
    --encryption-type "EncryptionAtRestWithCustomerKey" `
    --disk-encryption-set $DESEncryptionAtRestWithCustomerKeyName

az vm disk attach `
    --resource-group $resourceGroupName `
    --vm-name "VM10" `
    --name "datadisk02_EncryptionAtRestWithCustomerKey"


az disk create `
    --name "datadisk03_EncryptionAtRestWithPlatformAndCustomerKeys" `
    --resource-group $resourceGroupName `
    --location $location `
    --size-gb 128 `
    --sku "Premium_LRS" `
    --encryption-type "EncryptionAtRestWithPlatformAndCustomerKeys" `
    --disk-encryption-set $DESEncryptionAtRestWithPlatformAndCustomerKeysName

az vm disk attach `
    --resource-group $resourceGroupName `
    --vm-name "VM10" `
    --name "datadisk03_EncryptionAtRestWithPlatformAndCustomerKeys"

####------------------------------------------------------------------------------------------------------------------------------------

az backup protection enable-for-vm `
    --resource-group $resourceGroupName `
    --vault-name $BackupVaultName `
    --vm VM01 `
    --policy-name "DefaultPolicy"

    
az backup protection enable-for-vm `
    --resource-group $resourceGroupName `
    --vault-name $BackupVaultName `
    --vm VM02 `
    --policy-name "DefaultPolicy"

az backup protection enable-for-vm `
    --resource-group $resourceGroupName `
    --vault-name $BackupVaultName `
    --vm VM03 `
    --policy-name "DefaultPolicy"

    
az backup protection enable-for-vm `
    --resource-group $resourceGroupName `
    --vault-name $BackupVaultName `
    --vm VM04 `
    --policy-name "DefaultPolicy"

az backup protection enable-for-vm `
    --resource-group $resourceGroupName `
    --vault-name $BackupVaultName `
    --vm VM05 `
    --policy-name "EnhancedPolicy"

    
az backup protection enable-for-vm `
    --resource-group $resourceGroupName `
    --vault-name $BackupVaultName `
    --vm VM06 `
    --policy-name "EnhancedPolicy"

az backup protection enable-for-vm `
    --resource-group $resourceGroupName `
    --vault-name $BackupVaultName `
    --vm VM07 `
    --policy-name "EnhancedPolicy"

    
az backup protection enable-for-vm `
    --resource-group $resourceGroupName `
    --vault-name $BackupVaultName `
    --vm VM08 `
    --policy-name "EnhancedPolicy"

az backup protection enable-for-vm `
    --resource-group $resourceGroupName `
    --vault-name $BackupVaultName `
    --vm VM09 `
    --policy-name "EnhancedPolicy"

az backup protection enable-for-vm `
    --resource-group $resourceGroupName `
    --vault-name $BackupVaultName `
    --vm VM10 `
    --policy-name "EnhancedPolicy"

