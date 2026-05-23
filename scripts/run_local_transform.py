"""
run_local_transform.py — local PySpark sanity check (no AWS needed)

Runs the same KPI logic as transform_kpis.py against the local sample CSVs
and prints a summary of the outputs so you can verify the numbers make sense
before deploying.

Usage:
    python scripts/run_local_transform.py

Requires: pyspark (pip install pyspark)
"""

import os
import sys
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window

# ── Paths ─────────────────────────────────────────────────────────────────────
ROOT       = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR   = os.path.join(ROOT, "..", "data")
SONGS_CSV  = os.path.join(DATA_DIR, "songs", "songs.csv")
STREAMS_CSV = os.path.join(DATA_DIR, "streams", "streams1.csv")  # test with first file

if not os.path.exists(SONGS_CSV):
    sys.exit(f"songs.csv not found at {SONGS_CSV} — check your DATA_DIR path")
if not os.path.exists(STREAMS_CSV):
    sys.exit(f"streams1.csv not found at {STREAMS_CSV}")

# ── Spark session ─────────────────────────────────────────────────────────────
spark = (
    SparkSession.builder
    .appName("music-etl-local-verify")
    .master("local[*]")
    .config("spark.sql.shuffle.partitions", "4")   # keep it light locally
    .getOrCreate()
)
spark.sparkContext.setLogLevel("WARN")

# ── Load ──────────────────────────────────────────────────────────────────────
streams = spark.read.option("header", "true").option("inferSchema", "true").csv(STREAMS_CSV)
songs   = spark.read.option("header", "true").option("inferSchema", "true").csv(SONGS_CSV) \
               .select("track_id", "track_genre", "duration_ms", "track_name", "artists")

print(f"\nStreams rows : {streams.count()}")
print(f"Songs rows  : {songs.count()}")

# ── Enrich ────────────────────────────────────────────────────────────────────
enriched = (
    streams.join(songs, on="track_id", how="inner")
    .withColumn("date", F.to_date(F.col("listen_time")))
    .withColumn("duration_ms", F.col("duration_ms").cast("long"))
    .filter(F.col("date").isNotNull())
    .filter(F.col("track_genre").isNotNull())
)
print(f"Enriched rows (after join): {enriched.count()}")

# ── daily_genre_kpis ──────────────────────────────────────────────────────────
daily_genre_kpis = (
    enriched.groupBy("track_genre", "date")
    .agg(
        F.count("*").alias("listen_count"),
        F.countDistinct("user_id").alias("unique_listeners"),
        F.sum("duration_ms").alias("total_listening_time_ms"),
    )
    .withColumn(
        "avg_listening_time_per_user_ms",
        (F.col("total_listening_time_ms") / F.col("unique_listeners")).cast("long"),
    )
    .withColumnRenamed("track_genre", "genre")
    .orderBy("listen_count", ascending=False)
)

print("\n── daily_genre_kpis (top 10 by listen_count) ──")
daily_genre_kpis.show(10, truncate=False)

# ── top_songs_per_genre ───────────────────────────────────────────────────────
song_plays = (
    enriched.groupBy("track_genre", "date", "track_id", "track_name", "artists")
    .agg(F.count("*").alias("play_count"))
)
window_songs = Window.partitionBy("track_genre", "date").orderBy(F.col("play_count").desc())
top_songs = (
    song_plays.withColumn("rank", F.rank().over(window_songs))
    .filter(F.col("rank") <= 3)
    .withColumn("genre_date", F.concat_ws("#", F.col("track_genre"), F.col("date").cast("string")))
    .select("genre_date", "rank", "track_name", "artists", "play_count")
    .orderBy("genre_date", "rank")
)

print("\n── top_songs_per_genre (first 15 rows) ──")
top_songs.show(15, truncate=40)

# ── top_genres_per_day ────────────────────────────────────────────────────────
window_genres = Window.partitionBy("date").orderBy(F.col("listen_count").desc())
top_genres = (
    daily_genre_kpis.withColumn("rank", F.rank().over(window_genres))
    .filter(F.col("rank") <= 5)
    .select("date", "rank", "genre", "listen_count")
    .orderBy("date", "rank")
)

print("\n── top_genres_per_day ──")
top_genres.show(20, truncate=False)

print("\nLocal verification complete. Numbers look sensible? Then run deploy.sh.")
spark.stop()
