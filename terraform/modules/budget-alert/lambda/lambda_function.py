import json
import os
import urllib.request

def lambda_handler(event, context):
    webhook_url = os.environ["DISCORD_WEBHOOK_URL"]

    message = event["Records"][0]["Sns"]["Message"]
    subject = event["Records"][0]["Sns"].get("Subject", "AWS 비용 알림")

    payload = {
        "content": f"**{subject}**\n{message}"
    }

    data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        webhook_url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (compatible; AWS-Lambda-Budget-Alert/1.0)"
        },
        method="POST"
    )

    with urllib.request.urlopen(req) as response:
        print(f"Discord response status: {response.status}")

    return {"statusCode": 200}
