"""
validate_streams.py — Glue Python Shell job (Step 1 of 3 in the state machine)

Receives the S3 path of a newly landed streams CSV and validates it before
any transformation runs. Writes a JSON result file that Step Functions reads
to decide whether to proceed or branch to quarantine.

Expected Glue job parameters:
  --source_key   : S3 key of the incoming file, e.g. raw/streams/streams1.csv
  --bucket       : S3 bucket name
  --result_key   : S3 key to write the validation result JSON to
"""

import sys
import json
import logging
from typing import Tuple
import boto3
import pandas as pd
from io import StringIO
from awsglue.utils import getResolvedOptions

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger(__name__)

# ── Constants ─────────────────────────────────────────────────────────────────
REQUIRED_COLUMNS = {"user_id", "track_id", "listen_time"}
MAX_NULL_RATE    = 0.05   # 5% — reject if key columns exceed this
MIN_ROWS         = 1      # zero-row files are invalid


def get_args():
    return getResolvedOptions(sys.argv, ["source_key", "bucket", "result_key"])


def read_csv_from_s3(s3_client, bucket: str, key: str) -> pd.DataFrame:
    response = s3_client.get_object(Bucket=bucket, Key=key)
    body = response["Body"].read().decode("utf-8")
    return pd.read_csv(StringIO(body))


def write_result(s3_client, bucket: str, key: str, status: str, reason: str = ""):
    result = {"status": status, "reason": reason}
    log.info("Validation result: %s", result)
    s3_client.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(result).encode("utf-8"),
        ContentType="application/json",
    )


def validate(df: pd.DataFrame) -> Tuple[bool, str]:
    """
    Run all checks against the dataframe.
    Returns (passed: bool, reason: str).
    reason is empty on success.
    """

    # 1. Row count
    if len(df) < MIN_ROWS:
        return False, f"File contains {len(df)} rows — must have at least {MIN_ROWS}"

    # 2. Required columns
    missing = REQUIRED_COLUMNS - set(df.columns.str.strip().str.lower())
    if missing:
        return False, f"Missing required columns: {sorted(missing)}"

    # Normalise column names to lowercase for the rest of the checks
    df.columns = df.columns.str.strip().str.lower()

    # 3. Null rate on key columns
    for col in ("user_id", "track_id"):
        null_rate = df[col].isna().mean()
        if null_rate > MAX_NULL_RATE:
            return False, (
                f"Column '{col}' has {null_rate:.1%} null values "
                f"(threshold {MAX_NULL_RATE:.0%})"
            )

    # 4. listen_time is parseable — sample up to 1000 rows to keep this fast
    sample = df["listen_time"].dropna().head(1000)
    if len(sample) == 0:
        return False, "Column 'listen_time' has no non-null values to parse"
    try:
        pd.to_datetime(sample, infer_datetime_format=True)
    except Exception as exc:
        return False, f"Column 'listen_time' is not parseable as timestamps: {exc}"

    # 5. track_id is not degenerate (all identical values is a sign of bad data)
    if df["track_id"].nunique() == 1:
        return False, (
            f"Column 'track_id' contains only a single distinct value "
            f"({df['track_id'].iloc[0]!r}) — likely corrupt file"
        )

    return True, ""


def main():
    args       = get_args()
    bucket     = args["bucket"]
    source_key = args["source_key"]
    result_key = args["result_key"]

    s3 = boto3.client("s3")

    log.info("Validating s3://%s/%s", bucket, source_key)

    try:
        df = read_csv_from_s3(s3, bucket, source_key)
    except Exception as exc:
        write_result(s3, bucket, result_key, "FAILED", f"Could not read file: {exc}")
        sys.exit(1)

    passed, reason = validate(df)

    if passed:
        write_result(s3, bucket, result_key, "PASSED")
        log.info("Validation passed — %d rows, %d columns", len(df), len(df.columns))
    else:
        write_result(s3, bucket, result_key, "FAILED", reason)
        log.error("Validation failed — %s", reason)
        sys.exit(1)


if __name__ == "__main__":
    main()
