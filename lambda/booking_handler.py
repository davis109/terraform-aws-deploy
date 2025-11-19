import json
import os
import boto3
from datetime import datetime
from decimal import Decimal
import uuid

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

# Environment variables
TABLE_NAME = os.environ['DYNAMODB_TABLE']
SQS_QUEUE_URL = os.environ['SQS_QUEUE_URL']

table = dynamodb.Table(TABLE_NAME)


class DecimalEncoder(json.JSONEncoder):
    """Helper class to convert DynamoDB Decimal types to JSON"""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)


def lambda_handler(event, context):
    """
    Main handler for event booking operations
    Supports POST (create booking) and GET (list bookings)
    """
    print(f"Received event: {json.dumps(event)}")
    
    http_method = event.get('httpMethod', '')
    
    try:
        if http_method == 'POST':
            return create_booking(event)
        elif http_method == 'GET':
            return get_bookings(event)
        else:
            return {
                'statusCode': 405,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Method not allowed'})
            }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error', 'message': str(e)})
        }


def create_booking(event):
    """
    Create a new event booking
    Expected body: {
        "event_id": "event-123",
        "user_name": "John Doe",
        "user_email": "john@example.com"
    }
    """
    try:
        body = json.loads(event['body'])
    except (json.JSONDecodeError, KeyError):
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Invalid request body'})
        }
    
    # Validate required fields
    required_fields = ['event_id', 'user_name', 'user_email']
    for field in required_fields:
        if field not in body:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': f'Missing required field: {field}'})
            }
    
    # Create booking record
    booking_id = f"booking-{uuid.uuid4()}"
    timestamp = datetime.utcnow().isoformat()
    
    booking_item = {
        'event_id': body['event_id'],
        'booking_id': booking_id,
        'user_name': body['user_name'],
        'user_email': body['user_email'],
        'booking_status': 'confirmed',
        'created_at': timestamp
    }
    
    # Store in DynamoDB
    table.put_item(Item=booking_item)
    print(f"Created booking: {booking_id}")
    
    # Send notification to SQS
    notification_message = {
        'booking_id': booking_id,
        'event_id': body['event_id'],
        'user_email': body['user_email'],
        'user_name': body['user_name'],
        'action': 'booking_created',
        'timestamp': timestamp
    }
    
    sqs.send_message(
        QueueUrl=SQS_QUEUE_URL,
        MessageBody=json.dumps(notification_message)
    )
    print(f"Sent notification to SQS for booking: {booking_id}")
    
    return {
        'statusCode': 201,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Booking created successfully',
            'booking': booking_item
        }, cls=DecimalEncoder)
    }


def get_bookings(event):
    """
    Get all bookings or filter by event_id
    Query params: ?event_id=event-123
    """
    query_params = event.get('queryStringParameters', {}) or {}
    event_id = query_params.get('event_id')
    
    if event_id:
        # Query bookings for specific event
        response = table.query(
            KeyConditionExpression='event_id = :event_id',
            ExpressionAttributeValues={
                ':event_id': event_id
            }
        )
        bookings = response.get('Items', [])
        message = f"Found {len(bookings)} booking(s) for event {event_id}"
    else:
        # Scan all bookings (use cautiously in production)
        response = table.scan()
        bookings = response.get('Items', [])
        message = f"Found {len(bookings)} total booking(s)"
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': message,
            'bookings': bookings
        }, cls=DecimalEncoder)
    }
