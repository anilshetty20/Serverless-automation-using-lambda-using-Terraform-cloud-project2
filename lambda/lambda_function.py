import json
import boto3
import urllib.parse
from datetime import datetime

# AWS clients
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# DynamoDB table
TABLE_NAME = "ProcessedFilesTF"
table = dynamodb.Table(TABLE_NAME)

# Max file size limit (for validation)
MAX_FILE_SIZE = 10000


def lambda_handler(event, context):
    print("Event received:", json.dumps(event))

    # Safety check (important for testing)
    if 'Records' not in event:
        print("No Records found in event")
        return {"status": "No Records"}

    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])

        print(f"Processing file: {key}")

        try:
            # 🟢 Step 1: Read file from S3
            response = s3.get_object(Bucket=bucket, Key=key)
            content = response['Body'].read().decode('utf-8')

            file_size = len(content)

            # 🟢 Step 2: Validate file size
            if file_size > MAX_FILE_SIZE:
                raise Exception("File too large")

            file_type = "TEXT"
            json_valid = False

            # 🟢 Step 3: Process TEXT file
            if key.endswith('.txt'):
                word_count = len(content.split())
                line_count = len(content.splitlines())

            # 🟢 Step 4: Process JSON file
            elif key.endswith('.json'):
                file_type = "JSON"

                # Validate JSON
                json.loads(content)
                json_valid = True

                word_count = len(content.split())
                line_count = len(content.splitlines())

            else:
                raise Exception("Unsupported file type")

            print(f"Word count: {word_count}, Line count: {line_count}")

            # 🟢 Step 5: Store in DynamoDB
            table.put_item(
                Item={
                    'fileName': key,
                    'timestamp': str(datetime.now()),
                    'fileType': file_type,
                    'fileSize': file_size,
                    'wordCount': word_count,
                    'lineCount': line_count,
                    'jsonValid': json_valid,
                    'status': 'PROCESSED'
                }
            )

            # 🟢 Step 6: Move file to processed/
            move_file(bucket, key, "processed/")

        except Exception as e:
            print("Error occurred:", str(e))

            # 🔴 Store failure in DynamoDB
            table.put_item(
                Item={
                    'fileName': key,
                    'timestamp': str(datetime.now()),
                    'status': 'FAILED',
                    'error': str(e)
                }
            )

            # 🔴 Move file to failed/
            move_file(bucket, key, "failed/")

    return {
        'statusCode': 200,
        'body': json.dumps('Processing completed')
    }


def move_file(bucket, key, destination_folder):
    new_key = key.replace("uploads/", destination_folder)

    print(f"Moving file to: {new_key}")

    # Copy file
    s3.copy_object(
        Bucket=bucket,
        CopySource={'Bucket': bucket, 'Key': key},
        Key=new_key
    )

    # Delete original file
    s3.delete_object(Bucket=bucket, Key=key)