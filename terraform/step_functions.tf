# ── Step Functions state machine ──────────────────────────────────────────────

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.project}-pipeline"
  role_arn = aws_iam_role.step_functions.arn

  # templatefile injects the real resource names into the ASL placeholders
  definition = templatefile("${path.module}/../step_functions/state_machine.asl.json", {
    glue_validate_job  = aws_glue_job.validate_streams.name
    glue_transform_job = aws_glue_job.transform_kpis.name
    glue_load_job      = aws_glue_job.load_dynamodb.name
    table_kpis         = aws_dynamodb_table.daily_genre_kpis.name
    table_songs        = aws_dynamodb_table.top_songs_per_genre.name
    table_genres       = aws_dynamodb_table.top_genres_per_day.name
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/states/${var.project}-pipeline"
  retention_in_days = 30

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}


# ── Step Functions IAM: allow sdk integrations (S3 CopyObject / DeleteObject) ─
# The base sfn role covers Glue. SDK integrations need explicit S3 permissions.

resource "aws_iam_role_policy" "step_functions_s3" {
  name = "sfn-s3-archive-quarantine"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ArchiveAndQuarantine"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.pipeline.arn,
          "${aws_s3_bucket.pipeline.arn}/*"
        ]
      }
    ]
  })
}


# ── EventBridge rule — fires on every PutObject under raw/streams/ ─────────────

resource "aws_cloudwatch_event_rule" "s3_put" {
  name        = "${var.project}-s3-raw-streams"
  description = "Trigger pipeline state machine when a file lands in raw/streams/"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.pipeline.bucket] }
      object = { key  = [{ prefix = "raw/streams/" }] }
    }
  })

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "sfn" {
  rule     = aws_cloudwatch_event_rule.s3_put.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = aws_iam_role.eventbridge.arn

  # Build the input that the state machine expects as its starting context
  input_transformer {
    input_paths = {
      bucket     = "$.detail.bucket.name"
      source_key = "$.detail.object.key"
    }
    input_template = <<-EOT
      {
        "bucket":        "<bucket>",
        "source_key":    "<source_key>",
        "result_key":    "tmp/validation/<source_key>.result.json",
        "songs_key":     "raw/songs/songs.csv",
        "output_prefix": "processed/kpis/<source_key>"
      }
    EOT
  }
}


# ── S3 EventBridge notifications must be enabled on the bucket ─────────────────

resource "aws_s3_bucket_notification" "pipeline" {
  bucket      = aws_s3_bucket.pipeline.id
  eventbridge = true
}
