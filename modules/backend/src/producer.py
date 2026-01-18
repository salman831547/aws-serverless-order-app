import json
import boto3
import os
import datetime

events = boto3.client("events")
BUS_NAME = os.environ["EVENT_BUS_NAME"]


def lambda_handler(event, context):
    try:
        # Parse body for HTTP API (v2 payload)
        body = json.loads(event.get("body", "{}"))

        # Structure the event
        detail = {
            "order_id": body.get("order_id", "unknown"),
            "quantity": int(body.get("quantity", 1)),
            "item": body.get("item", "generic-item"),
        }

        response = events.put_events(
            Entries=[
                {
                    "Source": "com.mycompany.orderapp",
                    "DetailType": "OrderCreated",
                    "Detail": json.dumps(detail),
                    "EventBusName": BUS_NAME,
                }
            ]
        )

        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Order submitted", "id": response["Entries"][0]["EventId"]}),
        }
    except Exception as e:
        print(e)
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
