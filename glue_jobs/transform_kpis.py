"""
transform_kpis.py — Glue PySpark job (Step 2 of 3 in the state machine)

Joins the incoming streams file with the songs reference data, then computes
all six KPIs for every (genre, date) combination present in the file.

Writes three parquet datasets to S3 (one per DynamoDB table shape) that the
load job reads and batch-writes to DynamoDB.

Expected Glue job parameters:
  --source_key      : S3 key of the validated streams CSV, e.g. raw/streams/streams1.csv
  --bucket          : S3 bucket name
  --songs_key       : S3 key of the songs reference CSV, e.g. raw/songs/songs.csv
  --output_prefix   : S3 prefix to write parquet output, e.g. processed/kpis/run-xyz
"""

import sys
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.window import Window

# ── Glue boilerplate ──────────────────────────────────────────────────────────
args = getResolvedOptions(
    sys.argv,
    ["JOB_NAME", "source_key", "bucket", "songs_key", "output_prefix"],
)

sc          = SparkContext()
glueContext = GlueContext(sc)
spark       = glueContext.spark_session
job         = Job(glueContext)
job.init(args["JOB_NAME"], args)

# ── Parameters ────────────────────────────────────────────────────────────────
BUCKET        = args["bucket"]
SOURCE_KEY    = args["source_key"]
SONGS_KEY     = args["songs_key"]
OUTPUT_PREFIX = args["output_prefix"].rstrip("/")

s3 = lambda key: f"s3://{BUCKET}/{key}"


# ── 1. Load raw data ──────────────────────────────────────────────────────────

streams = (
    spark.read
    .option("header", "true")
    .option("inferSchema", "true")
    .csv(s3(SOURCE_KEY))
)

songs = (
    spark.read
    .option("header", "true")
    .option("inferSchema", "true")
    .option("quote", '"')
    .option("escape", '"')
    .csv(s3(SONGS_KEY))
    # Keep only the columns the transform actually needs
    .select("track_id", "track_genre", "duration_ms", "track_name", "artists")
)


# ── 2. Join and enrich ────────────────────────────────────────────────────────
# streams.track_id = songs.track_id
# Drop rows where the join produces no match (unknown track) — these can't be
# attributed to a genre so they are excluded from all KPIs.

enriched = (
    streams
    .join(songs, on="track_id", how="inner")
    .withColumn(
        "date",
        F.to_date(F.col("listen_time"))          # extract YYYY-MM-DD
    )
    .withColumn(
        "duration_ms",
        F.expr("try_cast(duration_ms as bigint)")  # null on bad values instead of error
    )
    .filter(F.col("date").isNotNull())           # drop rows with unparseable timestamps
    .filter(F.col("track_genre").isNotNull())    # drop rows with no genre
    .filter(F.col("duration_ms").isNotNull())    # drop rows where duration couldn't be parsed
)


# ── 3. Scalar KPIs per (genre, date) ─────────────────────────────────────────
# Produces one row per (genre, date) with four metrics.
# avg_listening_time_per_user_ms = total listening time / unique listeners
# (not the mean duration per play — it's total time spread across distinct users)

daily_genre_kpis = (
    enriched
    .groupBy("track_genre", "date")
    .agg(
        F.count("*")                          .alias("listen_count"),
        F.countDistinct("user_id")            .alias("unique_listeners"),
        F.sum("duration_ms")                  .alias("total_listening_time_ms"),
    )
    .withColumn(
        "avg_listening_time_per_user_ms",
        (F.col("total_listening_time_ms") / F.col("unique_listeners")).cast("long"),
    )
    .withColumnRenamed("track_genre", "genre")
)


# ── 4. Top-3 songs per genre per day ─────────────────────────────────────────
# play_count = number of times a (track_id, genre, date) combination appears.
# Ties broken by track_id descending (deterministic but arbitrary).

song_plays = (
    enriched
    .groupBy("track_genre", "date", "track_id", "track_name", "artists")
    .agg(F.count("*").alias("play_count"))
)

window_songs = (
    Window
    .partitionBy("track_genre", "date")
    .orderBy(F.col("play_count").desc(), F.col("track_id").desc())
)

top_songs_per_genre = (
    song_plays
    .withColumn("rank", F.rank().over(window_songs))
    .filter(F.col("rank") <= 3)
    .withColumn(
        "genre_date",
        F.concat_ws("#", F.col("track_genre"), F.col("date").cast("string")),
    )
    .select("genre_date", "rank", "track_id", "track_name", "artists", "play_count")
)


# ── 5. Top-5 genres per day ───────────────────────────────────────────────────
# Derived directly from daily_genre_kpis — no re-aggregation needed.

window_genres = (
    Window
    .partitionBy("date")
    .orderBy(F.col("listen_count").desc(), F.col("genre").desc())
)

top_genres_per_day = (
    daily_genre_kpis
    .withColumn("rank", F.rank().over(window_genres))
    .filter(F.col("rank") <= 5)
    .select("date", "rank", "genre", "listen_count")
)


# ── 6. Write outputs ──────────────────────────────────────────────────────────
# One parquet file per KPI shape. The load job reads these paths directly.
# Overwrite mode means re-running the transform for the same source file is safe.

daily_genre_kpis.write.mode("overwrite").parquet(
    f"{s3(OUTPUT_PREFIX)}/daily_genre_kpis/"
)

top_songs_per_genre.write.mode("overwrite").parquet(
    f"{s3(OUTPUT_PREFIX)}/top_songs_per_genre/"
)

top_genres_per_day.write.mode("overwrite").parquet(
    f"{s3(OUTPUT_PREFIX)}/top_genres_per_day/"
)

job.commit()
