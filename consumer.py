import json
import boto3
import os
import uuid

dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ['DYNAMODB_TABLE']
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    for record in event['Records']:
        # 1. Get message body from SQS
        payload = json.loads(record['body'])
        
        # 2. Prepare item for DynamoDB (Add a unique ID)
        item = {
            'OrderId': str(uuid.uuid4()),
            'Product': payload.get('product', 'Unknown'),
            'Quantity': payload.get('quantity', 1)
        }
        
        # 3. Write to DB
        table.put_item(Item=item)
        print(f"Order processed: {item}")