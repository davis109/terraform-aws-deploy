output "api_gateway_url" {
  description = "Base URL for API Gateway"
  value       = "${aws_api_gateway_deployment.api_deployment.invoke_url}/bookings"
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.event_bookings.name
}

output "sqs_queue_url" {
  description = "SQS Queue URL"
  value       = aws_sqs_queue.notification_queue.url
}

output "booking_lambda_arn" {
  description = "ARN of booking handler Lambda"
  value       = aws_lambda_function.booking_handler.arn
}

output "notification_lambda_arn" {
  description = "ARN of notification handler Lambda"
  value       = aws_lambda_function.notification_handler.arn
}
