provider "aws" {
  region = "us-west-2"
}

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}


resource "aws_iam_role" "scheduler_invoke_role" {
  name               = "${var.schedule_name}-invoke-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}


data "aws_iam_policy_document" "invoke_lambda" {
  statement {
    sid     = "AllowInvokeTargetLambda"
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.this.arn
    ]
  }
}

resource "aws_iam_policy" "invoke_lambda" {
  name   = "${var.schedule_name}-invoke-policy"
  policy = data.aws_iam_policy_document.invoke_lambda.json
}

resource "aws_iam_role_policy_attachment" "attach_invoke_lambda" {
  role       = aws_iam_role.scheduler_invoke_role.name
  policy_arn = aws_iam_policy.invoke_lambda.arn
}

resource "aws_scheduler_schedule_group" "group" {
  name = "${var.schedule_name}-group"
}

resource "aws_scheduler_schedule" "every_30m" {
  name                         = var.schedule_name
  group_name                   = aws_scheduler_schedule_group.group.name
  description                  = "Invoca a Lambda a cada 30 minutos"
  schedule_expression          = "rate(30 minutes)"
  schedule_expression_timezone = "America/Sao_Paulo"
  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.this.arn
    role_arn = aws_iam_role.scheduler_invoke_role.arn
  }
  depends_on = [aws_iam_role_policy_attachment.attach_invoke_lambda]

}


# --- Log group para a Lambda ---
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.lambda_name}"
  retention_in_days = 14
}

# --- Role da Lambda ---
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.lambda_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Política de acesso ao DynamoDB
data "aws_iam_policy_document" "lambda_dynamodb" {
  statement {
    sid = "DynamoDBAccess"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      aws_dynamodb_table.jobs.arn
    ]
  }
}

resource "aws_iam_policy" "lambda_dynamodb" {
  name   = "${var.lambda_name}-dynamodb-policy"
  policy = data.aws_iam_policy_document.lambda_dynamodb.json
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

# Tabela DynamoDB
resource "aws_dynamodb_table" "jobs" {
  name         = "jobs-table"
  billing_mode = "PAY_PER_REQUEST" # On-demand (sem gerenciar capacidade)

  hash_key  = "job_id"     # chave de partição (PK)
  range_key = "created_at" # chave de ordenação (SK), opcional

  attribute {
    name = "job_id"
    type = "S" # S=String, N=Number, B=Binary
  }

  attribute {
    name = "created_at"
    type = "S"
  }


  tags = {
    Environment = "dev"
    Owner       = "gabriel"
  }
}


resource "aws_lambda_function" "this" {
  function_name    = var.lambda_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")
  timeout          = 15
  memory_size      = 256


  environment {
    variables = {
      API_GET_URL    = var.api_get_url
      API_POST_URL   = var.api_post_url
      SECRETS_ID     = var.secrets_id
      DYNAMODB_TABLE = aws_dynamodb_table.jobs.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

