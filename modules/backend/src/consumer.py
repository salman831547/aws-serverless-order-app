import json
import boto3
import os

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["DYNAMODB_TABLE"]
table = dynamodb.Table(TABLE_NAME)


def lambda_handler(event, context):
    for record in event["Records"]:
        try:
            # SQS payload wraps the EventBridge payload
            sqs_body = json.loads(record["body"])
            order_detail = sqs_body["detail"]

            # Write to DynamoDB
            table.put_item(
                Item={
                    "OrderId": order_detail["order_id"],
                    "Quantity": order_detail["quantity"],
                    "Item": order_detail["item"],
                    "Status": "PROCESSED",
                }
            )
            print(f"Processed Order: {order_detail['order_id']}")

        except Exception as e:
            print(f"Error processing record: {e}")
            raise e  # Raise to trigger SQS retry/DLQ
