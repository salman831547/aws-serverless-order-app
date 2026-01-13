import json
import boto3
import os

sqs = boto3.client('sqs')
QUEUE_URL = os.environ['SQS_QUEUE_URL']

def lambda_handler(event, context):
    try:
        # 1. Parse incoming body from API Gateway
        body = json.loads(event['body'])
        
        # 2. Send message to SQS
        sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=json.dumps(body)
        )
        
        return {
            'statusCode': 200,
            # --- CORS HEADERS START ---
            'headers': {
                'Access-Control-Allow-Origin': '*', # Allows any domain to read the response
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
            },
            # --- CORS HEADERS END ---
            'body': json.dumps('Order placed successfully!')
        }
    except Exception as e:
        return {
            'statusCode': 500,
            # Add headers here too in case of error!
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
            },
            'body': str(e)
        }