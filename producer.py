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
            'body': json.dumps('Order placed successfully!')
        }
    except Exception as e:
        return {'statusCode': 500, 'body': str(e)}