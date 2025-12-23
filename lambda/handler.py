import json
import os
import urllib.request
import logging
import boto3
from datetime import datetime
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def get_next_job_id(table):
    """Gera o próximo ID de forma atômica usando contador no DynamoDB"""
    response = table.update_item(
        Key={'job_id': 'COUNTER', 'created_at': 'COUNTER'},
        UpdateExpression='ADD next_id :inc',
        ExpressionAttributeValues={':inc': 1},
        ReturnValues='UPDATED_NEW'
    )
    return int(response['Attributes']['next_id'])

def lambda_handler(event, context):
    try:
        api_get_url = os.environ.get('API_GET_URL')
        api_post_url = os.environ.get('API_POST_URL')

        if not api_get_url or not api_post_url:
            logger.error("API URLs not configured")
            return {
                "statusCode": 500,
                "body": json.dumps({"error": "API URLs not configured"})
            }

        # GET request
        logger.info(f"Making GET request to {api_get_url}")
        req = urllib.request.Request(api_get_url, method="GET")
        with urllib.request.urlopen(req, timeout=10) as resp:
            data_1 = json.loads(resp.read().decode("utf-8"))

        if data_1 is not None:
            logger.info("Data retrieved successfully")
            data = json.dumps(data_1).encode("utf-8")
            headers = {
                "Content-Type": "application/json",
                "Accept": "application/json",
            }

            # POST request
            logger.info(f"Making POST request to {api_post_url}")
            req = urllib.request.Request(api_post_url, data=data, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=10) as resp:
                status = resp.getcode()
                body = resp.read().decode("utf-8")
                result = json.loads(body)

                logger.info(f"Request completed with status {status}")

                # Salvar no DynamoDB com auto-incremento
                dynamodb = boto3.resource('dynamodb')
                table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

                # Gerar próximo ID automaticamente
                next_id = get_next_job_id(table)

                # Salvar o job
                table.put_item(Item={
                    'job_id': str(next_id),
                    'created_at': datetime.utcnow().isoformat(),
                    'result': result
                })

                logger.info(f"Job {next_id} saved to DynamoDB")

                return {
                    "statusCode": status,
                    "body": json.dumps(result)
                }
        else:
            logger.warning("No data retrieved from GET request")
            return {
                "statusCode": 404,
                "body": json.dumps({"error": "No data found"})
            }

    except urllib.error.HTTPError as e:
        logger.error(f"HTTP Error: {e.code} - {e.reason}")
        return {
            "statusCode": e.code,
            "body": json.dumps({"error": str(e.reason)})
        }
    except urllib.error.URLError as e:
        logger.error(f"URL Error: {e.reason}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e.reason)})
        }
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Internal server error"})
        }


