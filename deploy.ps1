param
(
    [Parameter(Mandatory=$true)]
    [string] $appName,
    [Parameter(Mandatory=$true)]
    [string] $location,
    [Parameter(Mandatory=$true)]
	[string] $myPublicIp
)

$apppNameLc = $appName.ToLower()
$resourceGroupName ="rg-$appName-demo-$location"
$serviceBusNs =  "sbns-$appName-demo-$location"
$formStorageAcct = "stor$($apppNameLc)demo$($location)"
$funcStorageAcct = "fstor$($apppNameLc)demo$($location)"
$vnet = "vnet-$appName-demo-$location"
$subnet = "subn-$appName-demo-$location"
$nsg =  "nsg-$appName-demo-$location"
$funcsubnet = "subn-$appName-func-demo-$location"
$trimAppsubnet = "subn-$appName-trim-demo-$location"
$funcAppPlanTrim = "fcnplan-$appName-trim-demo-$location"
$formQueueName = "formqueue"
$rawDocQueue = "rawqueue"
$registryName = "acr$($appName)demo$($location)"
$funcPreProcessTrim = "fcn-$($appName)Trim-demo-$location"
$imageNameAndTag = "pythonaifunc:latest"

$keywords="RECEIPT NUMBER,Ship-To,Ship To,Consigned to"

Write-Host "Creating Resource Group" -ForegroundColor DarkCyan
az group create --name $resourceGroupName --location $location -o table


###########################
## Networking
###########################
Write-Host "Creating Network Security Group" -ForegroundColor DarkCyan
az network nsg create --resource-group $resourceGroupName --name $nsg -o table

Write-Host "Creating Virtual Network" -ForegroundColor DarkCyan
az network vnet create --resource-group $resourceGroupName --name $vnet --address-prefixes 10.10.0.0/16 --subnet-name $subnet --subnet-prefixes 10.10.0.0/24 --network-security-group $nsg -o table
az network vnet subnet update --name $subnet --resource-group $resourceGroupName --vnet-name $vnet --service-endpoints Microsoft.Storage Microsoft.Web -o table

Write-Host "Creating Function Subnet" -ForegroundColor DarkCyan
az network vnet subnet create --resource-group $resourceGroupName --name $funcsubnet --vnet-name $vnet --address-prefixes 10.10.1.0/24 --network-security-group $nsg --delegations Microsoft.Web/serverFarms --service-endpoints Microsoft.Storage Microsoft.Web -o table

Write-Host "Creating Function Subnet for Linux Plan" -ForegroundColor DarkCyan
az network vnet subnet create --resource-group $resourceGroupName --name $trimAppsubnet --vnet-name $vnet --address-prefixes 10.10.2.0/24 --network-security-group $nsg --delegations Microsoft.Web/serverFarms --service-endpoints Microsoft.Storage Microsoft.Web -o table

###########################
## Azure Container Registry 
###########################
Write-Host "Creating Azure Container Registry" -ForegroundColor DarkCyan
az acr create --name $registryName --resource-group $resourceGroupName --sku Standard -o table
az acr update --name $registryName --resource-group $resourceGroupName --admin-enabled $true


$acrId = az acr show --name $registryName --resource-group $resourceGroupName -o tsv --query id
$acrServer = az acr show --name $registryName --resource-group $resourceGroupName -o tsv --query loginServer 
########################################
## Build Container
########################################
Write-Host "Building Comtainer Image"  -ForegroundColor DarkCyan
az acr build --registry $registryName --image $imageNameAndTag --file ./DOCKERFILE . --no-logs

###########################
## Service Bus
###########################
Write-Host "Creating Service Bus Namespace" -ForegroundColor DarkCyan
az servicebus namespace create --resource-group $resourceGroupName --name $serviceBusNs --sku Standard -o table

Write-Host "Creating Service Bus Queue" -ForegroundColor DarkCyan
az servicebus queue create --resource-group $resourceGroupName --name $rawDocQueue --namespace-name $serviceBusNs --enable-partitioning $true --max-size 4096 -o table

Write-Host "Creating Service Bus Queue Authorization Rule" -ForegroundColor DarkCyan
az servicebus namespace authorization-rule create --resource-group $resourceGroupName --namespace-name $serviceBusNs  --name FormProcessFuncRule --rights Listen Send -o table
$sbConnString = az servicebus namespace authorization-rule keys list --resource-group $resourceGroupName --namespace-name $serviceBusNs  --name FormProcessFuncRule -o tsv --query primaryConnectionString

###########################
## Storage Account
###########################
Write-Host "Creating Forms Storage Account" -ForegroundColor DarkCyan
az storage account create --resource-group $resourceGroupName --name $formStorageAcct --sku Standard_LRS --kind StorageV2 --location $location --allow-blob-public-access $false --default-action Deny -o table
$storageKey =  az storage account keys list --account-name $formStorageAcct -o tsv --query [0].value
$storageId =  az storage account show --resource-group $resourceGroupName --name $formStorageAcct -o tsv --query id
$storageUrl = az storage account show --resource-group $resourceGroupName --name $formStorageAcct --query primaryEndpoints.blob -o tsv


Write-Host "Creating Storage VNET Network Rules" -ForegroundColor DarkCyan
az storage account network-rule add  --account-name $formStorageAcct --vnet-name $vnet --subnet $funcsubnet -o table
az storage account network-rule add  --account-name $formStorageAcct --vnet-name $vnet --subnet $trimAppsubnet -o table
az storage account network-rule add  --account-name $formStorageAcct --vnet-name $vnet --subnet $subnet -o table

Write-Host "Creating Storage Local IP Network Rules" -ForegroundColor DarkCyan
az storage account network-rule add  --account-name $formStorageAcct --ip-address $myPublicIp -o table

Write-Host "Creating Storage Containers" -ForegroundColor DarkCyan
az storage container create --name "incoming" --account-name $formStorageAcct --account-key $storageKey -o table
az storage container create --name "processed" --account-name $formStorageAcct --account-key $storageKey -o table
az storage container create --name "output" --account-name $formStorageAcct --account-key $storageKey -o table
az storage container create --name "trimmed" --account-name $formStorageAcct --account-key $storageKey -o table

###########################
## Function storage account
###########################
Write-Host "Creating Function App Storage Account" -ForegroundColor DarkCyan
az storage account create --resource-group $resourceGroupName --name $funcStorageAcct --sku Standard_LRS --kind StorageV2 --location $location -o table
$webAppStorageConn = az storage account show-connection-string --resource-group $resourceGroupName --name $funcStorageAcct --query connectionString --output tsv

###########################
## Function App plan
###########################
Write-Host "Creating Function App Plan" -ForegroundColor DarkCyan
az functionapp plan create --name $funcAppPlanTrim --resource-group $resourceGroupName --sku EP1 --max-burst 4  --is-linux  -o table


########################################
## Form AI triming pre-Procesor Function
########################################
Write-Host "Creating Form pre-Processing Function App" -ForegroundColor DarkCyan
az functionapp create --resource-group $resourceGroupName --plan $funcAppPlanTrim --os-type Linux --functions-version 4  --name $funcPreProcessTrim --storage-account $funcStorageAcct --deployment-container-image-name "$($acrServer)/$($imageNameAndTag)" -o table

Write-Host "Assigning System Assigned Managed Identity to  pre-Processing Function App" -ForegroundColor DarkCyan
az functionapp identity assign --name $funcPreProcessTrim --resource-group $resourceGroupName --identities [system] -o table
$funcPreProcessTrimId = az functionapp identity show --name $funcPreProcessTrim --resource-group $resourceGroupName -o tsv --query principalId

Write-Host "Enabling Function App CD " -ForegroundColor DarkCyan
az functionapp config set --resource-group $resourceGroupName --name $funcPreProcessTrim --generic-configurations "{\""acrUseManagedIdentityCreds\"":\""true\""}" -o table
az functionapp deployment container config --resource-group $resourceGroupName --name $funcPreProcessTrim --enable-cd $true -o table

Write-Host "Creating Form pre-Processing VNET integration" -ForegroundColor DarkCyan
az functionapp vnet-integration add --name $funcPreProcessTrim --resource-group $resourceGroupName --vnet $vnet --subnet $trimAppsubnet -o table


Write-Host "Updating App Settings" -ForegroundColor DarkCyan

$settings= @(
"""SERVICEBUS_CONNECTION=$($sbConnString)""",  
"""STORAGE_ACCT_URL=$($storageUrl)""",
"""SOURCE_CONTAINER_NAME=incoming""",
"""DESTINATION_CONTAINER_NAME=trimmed""",
"""DESTINATION_QUEUE_NAME=$($formQueueName)""",
"""KEYWORDS_LIST=$($keywords)""",
"""AzureWebJobsStorage=$($webAppStorageConn)"""
)

az functionapp config appsettings set --resource-group $resourceGroupName --name $funcPreProcessTrim --settings @settings -o table


###########################
## Role Assignments
###########################
Write-Host "Adding Role Assignments For File pre-processing Trim Function " -ForegroundColor DarkCyan
az role assignment create --role "Storage Blob Data Contributor" --assignee $funcPreProcessTrimId --scope $storageId  -o table
az role assignment create --role "Storage Blob Data Reader" --assignee $funcPreProcessTrimId --scope $storageId  -o table
az role assignment create --role "AcrPull" --assignee $funcPreProcessTrimId --scope $acrId -o table
