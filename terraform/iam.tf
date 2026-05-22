# ─── Glue execution role ──────────────────────────────────────────────────────
# All three Glue jobs (validate, transform, load) share this role.
# Principle of least privilege: only this bucket and these three tables.

data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue" {
  name               = "${var.project}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# AWS-managed policy: covers CloudWatch Logs, default Glue service S3 paths,
# and EC2 network access needed for Glue to spin up executors
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Inline policy: scoped to this project's specific S3 bucket and DynamoDB tables
data "aws_iam_policy_document" "glue_inline" {
  statement {
    sid    = "S3PipelineBucket"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.pipeline.arn,
      "${aws_s3_bucket.pipeline.arn}/*",
    ]
  }

  statement {
    sid    = "DynamoDBKPIWrites"
    effect = "Allow"

    # PutItem and BatchWriteItem are the only DynamoDB operations the load job needs
    actions = [
      "dynamodb:PutItem",
      "dynamodb:BatchWriteItem",
    ]

    resources = [
      aws_dynamodb_table.daily_genre_kpis.arn,
      aws_dynamodb_table.top_songs_per_genre.arn,
      aws_dynamodb_table.top_genres_per_day.arn,
    ]
  }
}

resource "aws_iam_role_policy" "glue_inline" {
  name   = "glue-pipeline-access"
  role   = aws_iam_role.glue.id
  policy = data.aws_iam_policy_document.glue_inline.json
}


# ─── Step Functions execution role ───────────────────────────────────────────
# Needs to start Glue jobs and write execution logs.
# The Glue resource ARN is locked down to this project's prefix.

data "aws_iam_policy_document" "step_functions_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "step_functions" {
  name               = "${var.project}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.step_functions_assume_role.json

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

data "aws_iam_policy_document" "step_functions_inline" {
  statement {
    sid    = "GlueJobControl"
    effect = "Allow"

    actions = [
      "glue:StartJobRun",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:BatchStopJobRun",
    ]

    # Scoped to jobs whose names start with the project prefix
    resources = [
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:job/${var.project}-*",
    ]
  }

  statement {
    sid    = "CloudWatchLogsDelivery"
    effect = "Allow"

    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "step_functions_inline" {
  name   = "sfn-pipeline-access"
  role   = aws_iam_role.step_functions.id
  policy = data.aws_iam_policy_document.step_functions_inline.json
}


# ─── EventBridge role ─────────────────────────────────────────────────────────
# Only permission needed: start a Step Functions execution.
# The state machine ARN is referenced in step_functions.tf (Step 7).

data "aws_iam_policy_document" "eventbridge_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge" {
  name               = "${var.project}-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume_role.json

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

data "aws_iam_policy_document" "eventbridge_inline" {
  statement {
    sid    = "StartStepFunctionsExecution"
    effect = "Allow"

    actions = ["states:StartExecution"]

    # Will be narrowed to the specific state machine ARN once step_functions.tf is written
    resources = [
      "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project}-*",
    ]
  }
}

resource "aws_iam_role_policy" "eventbridge_inline" {
  name   = "eventbridge-sfn-trigger"
  role   = aws_iam_role.eventbridge.id
  policy = data.aws_iam_policy_document.eventbridge_inline.json
}
