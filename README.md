# Python AI Function

This repository is offered to demonstrate a set of resources that will allow you to leverage an Azure Function that uses Tesseract OCR to identify pages within a PDF document that contains the desired text. It will then take that page from the document and save it as a JPEG image in Azure Storage.  When used in conjunction with the [High Throughput Form Recognizer](https://github.com/mmckechney/HighThroughputFormRecognizer) it will allow you to perform very efficient and scalable file processing and form recognition for millons of documents.  
**NOTE**: Sending the message to the Service Bus for the form recognition is still WIP

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
- **Azure Container Registry** - because this function is deployed as a Docker container, 


## Configuration

The solution leverages Azure Managed Identity for connections to Azure Storage and for sending messages to the `formqueue`. This identity needs to have `Storage Blob Data Contributor` role to the stogate account and `"Azure Service Bus Data Owner` role to the Service Bus. 

The function also require the following App Settings values:

- `KEYWORD_LIST` - comma separated list of keywords to find in the PDF documents. The matching will be case sensitive
- `SERVICEBUS_CONNECTION` - connection string for the Service Bus. This will be used by the function binding
- `STORAGE_ACCT_URL` - the URL for the storage account that will be used
- `SOURCE_CONTAINER_NAME` - the name of the blob container that will have the source PDF documents
- `DESTINATION_CONTAINER_NAME` - the name of the blob container that the trimmed JPEG files will be saved

The `function.json` file will need to have the `queueName` has the appropriate name of the queue that is located in the service bus

## Deployment

**NOTE:** Deployment instructions are WIP

Build the container using Azure Container Registry [build tasks](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-tasks-overview):
``` bash
az acr build --registry "<registry name>" --image "<name>:<tag>" --file ./DOCKERFILE . --no-logs
```


