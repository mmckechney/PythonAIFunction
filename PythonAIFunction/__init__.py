from ast import keyword
from email import message
from email.message import Message
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
from azure.servicebus import ServiceBusClient, ServiceBusMessage
import time
import json
import random


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
    #Name of the queue to send message to
    destination_queue_name = os.environ.get("DESTINATION_QUEUE_NAME", "")
    print(destination_queue_name) 

    servicebus_conn_string = os.environ["SERVICEBUS_CONNECTION"]   

    #Comma separated list of keywords to find in docs
    keywords_list = os.environ["KEYWORDS_LIST"].split(",")   
    print(keywords_list)


    #Retrieve the source file from Azure storage    
    token_credential = DefaultAzureCredential()
    serviceClient = BlobServiceClient(account_url=storage_url, credential=token_credential)
    message_file_name = msg.get_body().decode('utf-8')
    source_blob_client = serviceClient.get_blob_client(container=source_container_name, blob=message_file_name)
 
    #save the file locally
    filePath = "/home/"+message_file_name
    with open(filePath, "wb") as my_blob:
       download_stream = source_blob_client.download_blob()
       my_blob.write(download_stream.readall())
    print("file was saved locally")
    print(filePath)

    doc = convert_from_path(filePath, fmt='jpeg')

    path, fileName = os.path.split(filePath)
    fileBaseName, fileExtension = os.path.splitext(fileName)
    
    start = time.process_time()


    #loop through the pages in the PDF
    for page_number, page_data in enumerate(doc):
        #perform Tesseract OCR to extract text
        txt = pytesseract.image_to_string(Image.fromarray(asarray(page_data))).encode("utf-8")

        #look for matching keyword and if found continue processing
        for keyword in keywords_list:
            if keyword in txt.decode("utf-8"):
                print(keyword + " string is present")
                temp_file_name = fileBaseName+ "-page-"+ str(page_number) +'.jpg'
                Image.fromarray(asarray(page_data)).save('/home/'+temp_file_name)
                print('Image created \n')
                print("Page # {} - {}".format(str(page_number),txt))

                #upload to Azure storage
                try:
                    dest_blob_client = serviceClient.get_blob_client(container=destination_container_name, blob=temp_file_name)
                    with open('/home/'+temp_file_name, "rb") as my_dest_blob:
                        dest_blob_client.upload_blob(my_dest_blob)
                    print("File '" + temp_file_name + "' uploaded to storage")
                except Exception as e:
                    print("ERROR: Failed to upload '" + temp_file_name + "' to storage: " + e.message)

                #send the file message to the destination queue (if provided)
                try:
                    if(len(destination_queue_name) > 0):
                        with ServiceBusClient.from_connection_string(servicebus_conn_string) as sb_client:
                            with sb_client.get_queue_sender(destination_queue_name) as q_sender:
                                msgJson = {
                                    "FileName" : temp_file_name,
                                    "ContainerName" : destination_container_name,
                                    "RecognizerIndex" : random.randint(0,9)                
                                    }
                                message = ServiceBusMessage(json.dumps(msgJson))
                                q_sender.send_messages(message)
                    else:
                        print("No destination queue name provided")
                except Exception as e:
                    print("ERROR: Failed to send message for file'" + temp_file_name + "' to queue: " + e.message)
                
                #Delete the temp jpeg file
                try:
                    if os.path.exists('/home/'+temp_file_name):
                        os.remove('/home/'+temp_file_name)
                        print("Deleted temp file'" + temp_file_name + "' ")
                except Exception as e:
                    print("ERROR: Failed to delete local temp file'" + temp_file_name + "' " + e.message)
                break

            else:
                print("No matches of '"+ keyword +"' on page '"+ str(page_number) + "' of file '" + message_file_name + "'")

            #Delete the temp jpeg file
            try:
                if os.path.exists(filePath):
                    os.remove(filePath)
                    print("Deleted original source file'" + filePath + "' ")
            except Exception as e:
                print("ERROR: Failed to delete original source file'" + filePath + "' " + e.message)
            break

    print("TOTAL PROCESS TIME: " + str(time.process_time() - start))
