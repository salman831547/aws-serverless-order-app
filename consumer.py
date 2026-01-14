import json
import boto3
import os
import uuid

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["DYNAMODB_TABLE"]
table = dynamodb.Table(TABLE_NAME)


def lambda_handler(event, context):
    for record in event["Records"]:
        # 1. Parse SQS Body
        sqs_body = json.loads(record["body"])

        # 2. Extract the "detail" from EventBridge envelope
        # If it comes from EventBridge, the real data is in 'detail'
        if "detail" in sqs_body:
            payload = sqs_body["detail"]
        else:
            payload = sqs_body

        # 3. Write to DB
        item = {
            "OrderId": str(uuid.uuid4()),
            "Product": payload.get("product", "Unknown"),
            "Quantity": payload.get("quantity", 1),
        }
        table.put_item(Item=item)
        print(f"Order processed: {item}")
