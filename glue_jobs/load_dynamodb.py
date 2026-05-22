"""
load_dynamodb.py — Glue Python Shell job (Step 3 of 3 in the state machine)

Reads the three parquet datasets written by transform_kpis.py and batch-writes
them into the three DynamoDB tables. All writes use PutItem semantics via
boto3's batch_writer, so re-running for the same date is fully idempotent.

Expected Glue job parameters:
  --input_prefix   : S3 prefix where transform wrote its output,
                     e.g. processed/kpis/run-xyz
  --bucket         : S3 bucket name
  --table_kpis     : DynamoDB table name for daily_genre_kpis
  --table_songs    : DynamoDB table name for top_songs_per_genre
  --table_genres   : DynamoDB table name for top_genres_per_day
"""

import sys
import logging
import boto3
import pandas as pd
from io import BytesIO
from awsglue.utils import getResolvedOptions

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger(__name__)

# ── Args ──────────────────────────────────────────────────────────────────────
args = getResolvedOptions(
    sys.argv,
    ["input_prefix", "bucket", "table_kpis", "table_songs", "table_genres"],
)

BUCKET       = args["bucket"]
INPUT_PREFIX = args["input_prefix"].rstrip("/")
TABLE_KPIS   = args["table_kpis"]
TABLE_SONGS  = args["table_songs"]
TABLE_GENRES = args["table_genres"]

s3       = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")


# ── Helpers ───────────────────────────────────────────────────────────────────

def read_parquet_from_s3(prefix: str) -> pd.DataFrame:
    """
    Read all parquet part-files under a given S3 prefix into one DataFrame.
    Glue PySpark writes one or more part files per output folder.
    """
    paginator = s3.get_paginator("list_objects_v2")
    frames = []

    for page in paginator.paginate(Bucket=BUCKET, Prefix=prefix + "/"):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not key.endswith(".parquet"):
                continue
            body = s3.get_object(Bucket=BUCKET, Key=key)["Body"].read()
            frames.append(pd.read_parquet(BytesIO(body)))

    if not frames:
        raise RuntimeError(f"No parquet files found at s3://{BUCKET}/{prefix}/")

    return pd.concat(frames, ignore_index=True)


def to_dynamodb_item(row: dict) -> dict:
    """
    Convert a pandas row dict to a DynamoDB-safe item.
    - Cast numpy int64 / float64 to Python native types (DynamoDB rejects numpy types)
    - Convert date objects to ISO strings
    - Drop NaN values (DynamoDB does not accept None/null attribute values)
    """
    import math
    from decimal import Decimal

    item = {}
    for k, v in row.items():
        if v is None:
            continue
        # numpy / pandas numeric types → Python int or Decimal
        if hasattr(v, "item"):          # numpy scalar
            v = v.item()
        if isinstance(v, float):
            if math.isnan(v):
                continue
            v = Decimal(str(round(v, 6)))
        if hasattr(v, "isoformat"):     # date / datetime
            v = v.isoformat()
        item[k] = v
    return item


def batch_write(table_name: str, df: pd.DataFrame):
    """
    Write all rows in df to a DynamoDB table using batch_writer.
    batch_writer handles 25-item batching and automatic retries on
    UnprocessedItems — no manual chunking needed.
    """
    table = dynamodb.Table(table_name)
    count = 0

    with table.batch_writer() as batch:
        for row in df.to_dict(orient="records"):
            item = to_dynamodb_item(row)
            batch.put_item(Item=item)
            count += 1

    log.info("Wrote %d items to %s", count, table_name)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    log.info("Loading KPIs from s3://%s/%s", BUCKET, INPUT_PREFIX)

    # 1. daily_genre_kpis
    log.info("Reading daily_genre_kpis parquet...")
    df_kpis = read_parquet_from_s3(f"{INPUT_PREFIX}/daily_genre_kpis")
    log.info("  %d rows", len(df_kpis))
    batch_write(TABLE_KPIS, df_kpis)

    # 2. top_songs_per_genre
    log.info("Reading top_songs_per_genre parquet...")
    df_songs = read_parquet_from_s3(f"{INPUT_PREFIX}/top_songs_per_genre")
    log.info("  %d rows", len(df_songs))
    batch_write(TABLE_SONGS, df_songs)

    # 3. top_genres_per_day
    log.info("Reading top_genres_per_day parquet...")
    df_genres = read_parquet_from_s3(f"{INPUT_PREFIX}/top_genres_per_day")
    log.info("  %d rows", len(df_genres))
    batch_write(TABLE_GENRES, df_genres)

    log.info("Load complete.")


if __name__ == "__main__":
    main()
