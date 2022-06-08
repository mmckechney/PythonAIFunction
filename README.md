# Python AI Function

This repository is offered to demonstrate a set of resources that will allow you to leverage an Azure Function that uses Tesseract OCR to identify pages within a PDF document that contains the desired text. It will then take that page from the document and save it as a JPEG image in Azure Storage.  When used in conjunction with the [High Throughput Form Recognizer](https://github.com/mmckechney/HighThroughputFormRecognizer) it will allow you to perform very efficient and scalable file processing and form recognition for millons of documents.  

**NOTE**: If you plan on using this solution in conjunction with the [High Throughput Form Recognizer](https://github.com/mmckechney/HighThroughputFormRecognizer), it is suggested to run the deployment script from that solution with the same `appName`, `location` and `myPublicIp` values that you use to run the `deploy.ps1` in this solution. This will ensure that they work well together.

## Features

The solution leverages the following Azure services:

- **Azure Blob Storage** with two containers
  - `incoming` - storage for the raw multipage PDF documents
  - `trimmed` - storage for the single page JPEG images 
- **Azure Service Bus** with two queues
  - `rawqueue` - identified the "raw" multipage PFD documents that need processing
  - `formqueue` - where a new queue message will be placed to hand off to the [High Throughput Form Recognizer](https://github.com/mmckechney/HighThroughputFormRecognizer) processing
- **Azure Functions**
  - `PythonAIFunction` - Containerized Python function that will use the `rawqueue` to identify PDF files for processing, perform Tesseract OCR to search for the specified keywords, then when found, create a JPEG of that page and save it to the `trimmed` storage container
- **Azure Container Registry** - because this function is deployed as a Docker container, it will use the container registry as its deployment source


## Configuration

The solution leverages Azure Managed Identity for connections to Azure Storage and for sending messages to the `formqueue`. This identity needs to have `Storage Blob Data Contributor` role to the stogate account and `Azure Service Bus Data Owner` role to the Service Bus. 

The function also require the following App Settings values:

- `KEYWORD_LIST` - comma separated list of keywords to find in the PDF documents. The matching will be case sensitive
- `SERVICEBUS_CONNECTION` - connection string for the Service Bus. This will be used by the function binding
- `STORAGE_ACCT_URL` - the URL for the storage account that will be used
- `SOURCE_CONTAINER_NAME` - the name of the blob container that will have the source PDF documents
- `DESTINATION_CONTAINER_NAME` - the name of the blob container that the trimmed JPEG files will be saved

The `function.json` file will need to have the `queueName` has the appropriate name of the queue that is located in the service bus

## Get Started

To try out the sample end-to-end process, you will need:

- An Azure subscription that you have privileges to create resources. 
- Your public IP address. You can easily find it by following [this link](https://www.bing.com/search?q=what+is+my+ip).
- Have the [Azure CLI installed](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli).

### Running deployment script

1. Login to the Azure CLI:  `az login`
2. Run the deployment command

    ``` PowerShell
    .\deploy.ps1 -appName "<less than 6 characters>" -location "<azure region>" -myPublicIp "<your public ip address>"

    ```

    This will create all of the azure resources needed to run the solution.

  
### Rebuilding the Container Image

The container image is built and added to the Azure Container Registry as part of the deploymet script. However if you need to rebuild the image, use the Azure Container Registry [build tasks](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-tasks-overview) command below. Because the function app is configured with Continuous Delivery, the new image will be automatically retrieved.
``` bash
az acr build --registry "<registry name>" --image "<name>:<tag>" --file ./DOCKERFILE . --no-logs
```


