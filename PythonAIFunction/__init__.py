from ast import keyword
import logging
import azure.functions as func
import os
from msrest import ServiceClient
import pytesseract
from PIL import Image
from pdf2image import convert_from_path
from PIL import Image
from numpy import asarray
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobClient
from azure.storage.blob import BlobServiceClient
import time


def main(msg: func.ServiceBusMessage):
    logging.info('Python ServiceBus queue trigger processed message: %s', msg.get_body().decode('utf-8'))

    print("CONFIGURATION VALUES:")
    #URL of the storage account containing the files
    storage_url = os.environ["STORAGE_ACCT_URL"]   
    print(storage_url)
    #Name of the blob container with the source fies 
    source_container_name = os.environ["SOURCE_CONTAINER_NAME"]  
    print(source_container_name) 
    #Name of the blob container where the trimmed, single page JPEG will be saves
    destination_container_name = os.environ["DESTINATION_CONTAINER_NAME"]   
    print(destination_container_name) 

    #Comma separated list of keywords to find in docs
    keywords_list = os.environ["KEYWORDS_LIST"].split(",")   
    print(keywords_list)

    token_credential = DefaultAzureCredential()
    serviceClient = BlobServiceClient(account_url=storage_url, credential=token_credential)
    message_file_name = msg.get_body().decode('utf-8')

    source_blob_client = serviceClient.get_blob_client(container=source_container_name, blob=message_file_name)
 
    filePath = "/home/"+message_file_name
    with open(filePath, "wb") as my_blob:
       download_stream = source_blob_client.download_blob()
       my_blob.write(download_stream.readall())
    print("file was saved")
    print(filePath)

    doc = convert_from_path(filePath, fmt='jpeg')

    path, fileName = os.path.split(filePath)
    fileBaseName, fileExtension = os.path.splitext(fileName)
    
    start = time.process_time()
    print(doc)
    for page_number, page_data in enumerate(doc):
        txt = pytesseract.image_to_string(Image.fromarray(asarray(page_data))).encode("utf-8")
        for keyword in keywords_list:
            if keyword in txt.decode("utf-8"):
                print(keyword + " string is present")
                temp_file_name = fileBaseName+ "-page-"+ str(page_number) +'.jpg'
                Image.fromarray(asarray(page_data)).save('/home/'+temp_file_name)
                print('Image created \n')
                print("Page # {} - {}".format(str(page_number),txt))

                dest_blob_client = serviceClient.get_blob_client(container=destination_container_name, blob=temp_file_name)

                with open('/home/'+temp_file_name, "rb") as my_dest_blob:
                    dest_blob_client.upload_blob(my_dest_blob)
                print("File '" + temp_file_name + "' uploaded to storage")
                break
            else:
                print("No matches of '"+ keyword +"' on page '"+ str(page_number) + "' of file '" + message_file_name + "'")


    print("TOTAL PROCESS TIME: " + str(time.process_time() - start))
