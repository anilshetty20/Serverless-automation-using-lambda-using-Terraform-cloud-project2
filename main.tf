# S3 Bucket Creation
resource "aws_s3_bucket" "Serverless_bucket" {
  bucket = var.bucket_name
}

#Dynamodb Table Creation
resource "aws_dynamodb_table" "files_table" {
    name = var.lambda_fucntion_name
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "fileName"
    attribute {
      name = "fileName"
      type = "S"
    }  
}

# IAM ROLE
resource "aws_iam_role" "lambda_role" {
  name = "lambda-serverless-role-tf"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM POLICY
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# LAMBDA
resource "aws_lambda_function" "file_processor" {
  function_name = var.lambda_fucntion_name
  runtime       = "python3.10"
  handler       = "lambda_function.lambda_handler"
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda/function.zip"
  source_code_hash = filebase64sha256("lambda/function.zip")
}

#LAMBDA PERMISSION
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.Serverless_bucket.arn
}

#S3 Trigger
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.Serverless_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.file_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# SNS 
resource "aws_sns_topic" "alerts" {
  name = "serverless-alerts-tf"
}

#SNS Subscription
resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.email
}

#cloudwatch
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "lambda-error-alarm-tf"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"

  dimensions = {
    FunctionName = aws_lambda_function.file_processor.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}