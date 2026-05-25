locals {
  scripts_prefix = "scripts"
}

# ─── validate_streams ─────────────────────────────────────────────────────────
# Python Shell job — lightweight, no Spark overhead.
# Reads the incoming CSV, runs schema/quality checks, writes a JSON result.

resource "aws_glue_job" "validate_streams" {
  name     = "${var.project}-validate-streams"
  role_arn = aws_iam_role.glue.arn

  command {
    name            = "pythonshell"
    python_version  = "3.9"
    script_location = "s3://${aws_s3_bucket.pipeline.bucket}/${local.scripts_prefix}/validate_streams.py"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-job-insights"              = "true"
    "--TempDir"                          = "s3://${aws_s3_bucket.pipeline.bucket}/tmp/"
    # source_key, bucket, and result_key are passed at runtime by Step Functions
  }

  # 0.0625 DPU is the minimum for Python Shell — roughly 1 vCPU / 4 GB
  max_capacity = 0.0625

  # Keep the two most recent job runs for debugging; older runs are auto-purged
  execution_property {
    max_concurrent_runs = 1
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}


# ─── transform_kpis ──────────────────────────────────────────────────────────
# PySpark job — joins streams + songs + users and computes daily KPIs.
# Placeholder resource: the script will be written in Step 5.

resource "aws_glue_job" "transform_kpis" {
  name     = "${var.project}-transform-kpis"
  role_arn = aws_iam_role.glue.arn

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.pipeline.bucket}/${local.scripts_prefix}/transform_kpis.py"
  }

  default_arguments = {
    "--job-language"        = "python"
    "--enable-job-insights" = "true"
    "--TempDir"             = "s3://${aws_s3_bucket.pipeline.bucket}/tmp/"
    "--enable-glue-datacatalog" = "true"
  }

  glue_version      = "4.0"
  number_of_workers = 2
  worker_type       = "G.1X"   # 4 vCPU / 16 GB — sufficient for ~90k song rows

  execution_property {
    max_concurrent_runs = 1
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}


# ─── load_dynamodb ────────────────────────────────────────────────────────────
# Python Shell job — reads pre-aggregated KPIs and batch-writes to DynamoDB.
# Placeholder resource: the script will be written in Step 6.

resource "aws_glue_job" "load_dynamodb" {
  name     = "${var.project}-load-dynamodb"
  role_arn = aws_iam_role.glue.arn

  command {
    name            = "pythonshell"
    python_version  = "3.9"
    script_location = "s3://${aws_s3_bucket.pipeline.bucket}/${local.scripts_prefix}/load_dynamodb.py"
  }

  default_arguments = {
    "--job-language"              = "python"
    "--enable-job-insights"       = "true"
    "--TempDir"                   = "s3://${aws_s3_bucket.pipeline.bucket}/tmp/"
    "--additional-python-modules" = "pyarrow"
  }

  max_capacity = 0.0625

  execution_property {
    max_concurrent_runs = 1
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}
