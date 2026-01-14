import json
import boto3
import os
import datetime

# Change Client to EventBridge
events = boto3.client("events")
EVENT_BUS_NAME = os.environ["EVENT_BUS_NAME"]


def lambda_handler(event, context):
    try:
        body = json.loads(event["body"])

        # Validation checks
        if not body.get("product"):
            raise ValueError("Product is required")

        # Create the EventBridge Entry
        entry = {
            "Source": "com.mycompany.orderapp",
            "DetailType": "OrderPlaced",
            "Detail": json.dumps(body),
            "EventBusName": EVENT_BUS_NAME,
            "Time": datetime.datetime.now(),
        }

        # Send to EventBridge
        events.put_events(Entries=[entry])

        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "Content-Type",
                "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
            },
            "body": json.dumps("Order received and routed!"),
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "Content-Type",
                "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
            },
            "body": str(e),
        }
