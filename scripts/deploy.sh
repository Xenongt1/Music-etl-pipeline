#!/usr/bin/env bash
# deploy.sh — upload Glue scripts to S3 then apply Terraform
#
# Usage:
#   ./scripts/deploy.sh              # uses terraform output for bucket name
#   BUCKET=my-bucket ./scripts/deploy.sh  # override bucket
#
# Must be run from the pipeline/ root directory.
# Requires: aws cli, terraform

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/../glue_jobs" && pwd)"
TERRAFORM_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"

# ── Resolve bucket name ───────────────────────────────────────────────────────
if [[ -z "${BUCKET:-}" ]]; then
  echo "Resolving bucket name from terraform output..."
  BUCKET=$(cd "$TERRAFORM_DIR" && terraform output -raw s3_bucket_name)
fi

echo "Bucket: $BUCKET"

# ── Upload Glue scripts ───────────────────────────────────────────────────────
echo "Uploading Glue scripts to s3://$BUCKET/scripts/"

aws s3 cp "$SCRIPTS_DIR/validate_streams.py" "s3://$BUCKET/scripts/validate_streams.py"
aws s3 cp "$SCRIPTS_DIR/transform_kpis.py"   "s3://$BUCKET/scripts/transform_kpis.py"
aws s3 cp "$SCRIPTS_DIR/load_dynamodb.py"    "s3://$BUCKET/scripts/load_dynamodb.py"

echo "Scripts uploaded."

# ── Terraform apply ───────────────────────────────────────────────────────────
echo "Running terraform apply..."
cd "$TERRAFORM_DIR"
terraform apply -auto-approve

echo ""
echo "Deploy complete."
