# ========================================
# DynamoDB Table (PROVISIONED - FREE TIER)
# ========================================
resource "aws_dynamodb_table" "event_bookings" {
  name           = "${var.project_name}-${var.environment}"
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "event_id"
  range_key      = "booking_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  attribute {
    name = "booking_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = false
  }

  tags = {
    Name = "${var.project_name}-table"
  }
}

# ========================================
# SQS Queue for Notifications
# ========================================
resource "aws_sqs_queue" "notification_queue" {
  name                       = "${var.project_name}-notifications-${var.environment}"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600  # 4 days
  receive_wait_time_seconds  = 0
  visibility_timeout_seconds = 300

  tags = {
    Name = "${var.project_name}-queue"
  }
}

# ========================================
# IAM Role for Lambda Functions
# ========================================
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda Basic Execution Policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom Policy for DynamoDB and SQS
resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.event_bookings.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.notification_queue.arn
      }
    ]
  })
}

# ========================================
# Lambda Function: Booking Handler
# ========================================
data "archive_file" "booking_handler_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/booking_handler.py"
  output_path = "${path.module}/../lambda/booking_handler.zip"
}

resource "aws_lambda_function" "booking_handler" {
  filename         = data.archive_file.booking_handler_zip.output_path
  function_name    = "${var.project_name}-booking-handler-${var.environment}"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "booking_handler.lambda_handler"
  source_code_hash = data.archive_file.booking_handler_zip.output_base64sha256
  runtime          = var.lambda_runtime
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.event_bookings.name
      SQS_QUEUE_URL  = aws_sqs_queue.notification_queue.url
      ENVIRONMENT    = var.environment
    }
  }

  tags = {
    Name = "${var.project_name}-booking-handler"
  }
}

# ========================================
# Lambda Function: Notification Handler
# ========================================
data "archive_file" "notification_handler_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/notification_handler.py"
  output_path = "${path.module}/../lambda/notification_handler.zip"
}

resource "aws_lambda_function" "notification_handler" {
  filename         = data.archive_file.notification_handler_zip.output_path
  function_name    = "${var.project_name}-notification-handler-${var.environment}"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "notification_handler.lambda_handler"
  source_code_hash = data.archive_file.notification_handler_zip.output_base64sha256
  runtime          = var.lambda_runtime
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = {
    Name = "${var.project_name}-notification-handler"
  }
}

# SQS Trigger for Notification Handler
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.notification_queue.arn
  function_name    = aws_lambda_function.notification_handler.arn
  batch_size       = 10
  enabled          = true
}

# ========================================
# API Gateway REST API
# ========================================
resource "aws_api_gateway_rest_api" "booking_api" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "Serverless Event Booking API"

  endpoint_configuration {
    types = ["EDGE"]
  }
}

# API Gateway Resource: /bookings
resource "aws_api_gateway_resource" "bookings" {
  rest_api_id = aws_api_gateway_rest_api.booking_api.id
  parent_id   = aws_api_gateway_rest_api.booking_api.root_resource_id
  path_part   = "bookings"
}

# POST /bookings
resource "aws_api_gateway_method" "post_booking" {
  rest_api_id   = aws_api_gateway_rest_api.booking_api.id
  resource_id   = aws_api_gateway_resource.bookings.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_booking_integration" {
  rest_api_id             = aws_api_gateway_rest_api.booking_api.id
  resource_id             = aws_api_gateway_resource.bookings.id
  http_method             = aws_api_gateway_method.post_booking.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.booking_handler.invoke_arn
}

# GET /bookings
resource "aws_api_gateway_method" "get_bookings" {
  rest_api_id   = aws_api_gateway_rest_api.booking_api.id
  resource_id   = aws_api_gateway_resource.bookings.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_bookings_integration" {
  rest_api_id             = aws_api_gateway_rest_api.booking_api.id
  resource_id             = aws_api_gateway_resource.bookings.id
  http_method             = aws_api_gateway_method.get_bookings.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.booking_handler.invoke_arn
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.booking_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.booking_api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.post_booking_integration,
    aws_api_gateway_integration.get_bookings_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.booking_api.id
  stage_name  = var.environment
}
