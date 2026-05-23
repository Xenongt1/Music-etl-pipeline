#!/usr/bin/env bash
# upload_sample_data.sh — push local CSVs to S3 reference paths
#
# Uploads songs.csv and users.csv to the raw/ reference prefixes once.
# Streams files are uploaded one at a time to trigger pipeline executions.
#
# Usage:
#   ./scripts/upload_sample_data.sh              # resolves bucket from terraform
#   BUCKET=my-bucket ./scripts/upload_sample_data.sh
#
# Must be run from the pipeline/ root directory.

set -euo pipefail

DATA_DIR="$(cd "$(dirname "$0")/../../data" && pwd)"
TERRAFORM_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"

# ── Resolve bucket name ───────────────────────────────────────────────────────
if [[ -z "${BUCKET:-}" ]]; then
  echo "Resolving bucket name from terraform output..."
  BUCKET=$(cd "$TERRAFORM_DIR" && terraform output -raw s3_bucket_name)
fi

echo "Bucket: $BUCKET"

# ── Upload reference data (songs + users) ────────────────────────────────────
echo "Uploading reference data..."
aws s3 cp "$DATA_DIR/songs/songs.csv" "s3://$BUCKET/raw/songs/songs.csv"
aws s3 cp "$DATA_DIR/users/users.csv" "s3://$BUCKET/raw/users/users.csv"
echo "Reference data uploaded."

# ── Upload first streams file to trigger a pipeline run ──────────────────────
echo ""
echo "Uploading streams1.csv to raw/streams/ to trigger a pipeline execution..."
aws s3 cp "$DATA_DIR/streams/streams1.csv" "s3://$BUCKET/raw/streams/streams1.csv"

echo ""
echo "Done. Monitor the execution in the Step Functions console:"
REGION=${AWS_DEFAULT_REGION:-us-east-1}
echo "  https://$REGION.console.aws.amazon.com/states/home?region=$REGION"
echo ""
echo "To trigger additional runs:"
echo "  aws s3 cp ../data/streams/streams2.csv s3://$BUCKET/raw/streams/streams2.csv"
echo "  aws s3 cp ../data/streams/streams3.csv s3://$BUCKET/raw/streams/streams3.csv"
