import json
import os
from datetime import datetime

# Environment variables
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')


def lambda_handler(event, context):
    """
    Process notification messages from SQS
    In a real system, this would send emails/SMS
    For this demo, we just log the notification
    """
    print(f"Notification handler triggered in {ENVIRONMENT} environment")
    
    processed_count = 0
    failed_count = 0
    
    # Process each SQS message
    for record in event['Records']:
        try:
            message_body = json.loads(record['body'])
            process_notification(message_body)
            processed_count += 1
        except Exception as e:
            print(f"Error processing message: {str(e)}")
            failed_count += 1
    
    print(f"Processed {processed_count} notifications, {failed_count} failed")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': processed_count,
            'failed': failed_count
        })
    }


def process_notification(message):
    """
    Process individual notification message
    In production, integrate with AWS SES, SNS, or third-party email service
    """
    booking_id = message.get('booking_id')
    user_email = message.get('user_email')
    user_name = message.get('user_name')
    event_id = message.get('event_id')
    action = message.get('action', 'unknown')
    timestamp = message.get('timestamp', datetime.utcnow().isoformat())
    
    # Simulate sending notification
    notification_log = {
        'type': 'email_notification',
        'action': action,
        'recipient': user_email,
        'subject': f'Event Booking Confirmation - {event_id}',
        'message': f'Hello {user_name}, your booking {booking_id} has been confirmed!',
        'timestamp': timestamp
    }
    
    print(f"📧 Notification sent: {json.dumps(notification_log, indent=2)}")
    
    # TODO: In production, add actual email sending logic here
    # Example with AWS SES:
    # ses = boto3.client('ses')
    # ses.send_email(
    #     Source='noreply@yourdomain.com',
    #     Destination={'ToAddresses': [user_email]},
    #     Message={
    #         'Subject': {'Data': notification_log['subject']},
    #         'Body': {'Text': {'Data': notification_log['message']}}
    #     }
    # )
    
    return notification_log
