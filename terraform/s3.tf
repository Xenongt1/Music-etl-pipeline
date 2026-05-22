locals {
  # Account ID suffix guarantees global uniqueness without a random resource
  bucket_name = "${var.project}-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "pipeline" {
  bucket = local.bucket_name

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# Versioning — lets us recover an accidentally overwritten script or data file
resource "aws_s3_bucket_versioning" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest with the default S3-managed key (SSE-S3)
# Switch to KMS here if compliance requires customer-managed keys later
resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access — this bucket is internal to the pipeline only
resource "aws_s3_bucket_public_access_block" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rules — keep storage costs low without manual housekeeping
resource "aws_s3_bucket_lifecycle_configuration" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id

  # raw/: safety net — a file lingering here after 7 days was never archived
  rule {
    id     = "expire-raw"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    expiration {
      days = 7
    }
  }

  # processed/: tier down for a cheap long-term audit trail
  rule {
    id     = "tier-processed"
    status = "Enabled"

    filter {
      prefix = "processed/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }

  # quarantine/: keep for 90 days so failed files can be debugged, then expire
  rule {
    id     = "expire-quarantine"
    status = "Enabled"

    filter {
      prefix = "quarantine/"
    }

    expiration {
      days = 90
    }
  }
}

# ─── Bucket prefix layout (no Terraform resources needed — prefixes are just key conventions) ───
#
#   raw/streams/          ← landing zone; EventBridge watches s3:ObjectCreated here
#   processed/streams/    ← archived after successful pipeline run
#   quarantine/streams/   ← moved here when validation fails
#   scripts/              ← Glue job Python files, synced by deploy.sh
#   tmp/                  ← Glue spark shuffle / intermediate results (auto-cleaned by Glue)
