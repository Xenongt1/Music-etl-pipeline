# ─── daily_genre_kpis ────────────────────────────────────────────────────────
# One item per (genre, date). Holds the four scalar KPIs.
#
# PK  genre      S   e.g. "pop"
# SK  date       S   e.g. "2024-01-15"
#
# Attributes written by the load job (not declared here — DynamoDB is schemaless):
#   listen_count                  N
#   unique_listeners              N
#   total_listening_time_ms       N
#   avg_listening_time_per_user_ms N

resource "aws_dynamodb_table" "daily_genre_kpis" {
  name         = "${var.project}-daily-genre-kpis"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "genre"
  range_key    = "date"

  attribute {
    name = "genre"
    type = "S"
  }

  attribute {
    name = "date"
    type = "S"
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}


# ─── top_songs_per_genre ──────────────────────────────────────────────────────
# Three items per (genre, date) — one per rank position.
#
# PK  genre_date   S   e.g. "pop#2024-01-15"
# SK  rank         N   1, 2, or 3
#
# Attributes:
#   track_id    S
#   track_name  S
#   artists     S
#   play_count  N

resource "aws_dynamodb_table" "top_songs_per_genre" {
  name         = "${var.project}-top-songs-per-genre"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "genre_date"
  range_key    = "rank"

  attribute {
    name = "genre_date"
    type = "S"
  }

  attribute {
    name = "rank"
    type = "N"
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}


# ─── top_genres_per_day ───────────────────────────────────────────────────────
# Five items per date — one per rank position.
#
# PK  date   S   e.g. "2024-01-15"
# SK  rank   N   1 through 5
#
# Attributes:
#   genre         S
#   listen_count  N

resource "aws_dynamodb_table" "top_genres_per_day" {
  name         = "${var.project}-top-genres-per-day"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "date"
  range_key    = "rank"

  attribute {
    name = "date"
    type = "S"
  }

  attribute {
    name = "rank"
    type = "N"
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}
