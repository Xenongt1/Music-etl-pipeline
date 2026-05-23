# Sample DynamoDB Queries

All examples use the AWS CLI. Replace table names and values as needed.

---

## Get all KPIs for a genre on a specific day

```bash
aws dynamodb get-item \
  --table-name music-etl-daily-genre-kpis \
  --key '{"genre": {"S": "pop"}, "date": {"S": "2024-01-15"}}'
```

---

## Get top 3 songs for a genre on a specific day

```bash
aws dynamodb query \
  --table-name music-etl-top-songs-per-genre \
  --key-condition-expression "genre_date = :gd" \
  --expression-attribute-values '{":gd": {"S": "pop#2024-01-15"}}' \
  --scan-index-forward true
```

Returns rank 1, 2, 3 in ascending order.

---

## Get top 5 genres for a specific day

```bash
aws dynamodb query \
  --table-name music-etl-top-genres-per-day \
  --key-condition-expression "#d = :date" \
  --expression-attribute-names '{"#d": "date"}' \
  --expression-attribute-values '{":date": {"S": "2024-01-15"}}' \
  --scan-index-forward true
```

`date` is a reserved word in DynamoDB expression syntax — the `#d` alias is required.

---

## Get all dates available for a genre

```bash
aws dynamodb query \
  --table-name music-etl-daily-genre-kpis \
  --key-condition-expression "genre = :g" \
  --expression-attribute-values '{":g": {"S": "pop"}}' \
  --projection-expression "#d, listen_count" \
  --expression-attribute-names '{"#d": "date"}'
```

---

## Trigger a pipeline run manually (skip EventBridge)

```bash
# Upload a streams file — EventBridge fires automatically
aws s3 cp ../data/streams/streams1.csv \
  s3://music-etl-dev-899957567386/raw/streams/streams1.csv

# Or start the state machine directly with a custom input
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:us-east-1:899957567386:stateMachine:music-etl-pipeline \
  --input '{
    "bucket":        "music-etl-dev-899957567386",
    "source_key":    "raw/streams/streams1.csv",
    "result_key":    "tmp/validation/raw/streams/streams1.csv.result.json",
    "songs_key":     "raw/songs/songs.csv",
    "output_prefix": "processed/kpis/raw/streams/streams1.csv"
  }'
```
