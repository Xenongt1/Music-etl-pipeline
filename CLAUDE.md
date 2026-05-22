# CLAUDE.md — Project 1: Music Streaming ETL Pipeline

This file is read automatically by Claude Code when working in this folder.
It captures context, decisions, and the plan agreed with the user (Mubarak)
so any Claude session can pick up where the last one left off.

---

## 1. What this project is

A near-real-time ETL pipeline for a music streaming service, built on AWS.

**Source data:** CSV "batch files" land in S3 at unpredictable intervals
(simulating event-driven ingestion). Not true streaming — event-driven
micro-batch. Each file is bounded and processed as one unit when it arrives.

**Pipeline:**
`S3 PutObject → EventBridge → Step Functions → Glue (validate → transform → load) → DynamoDB`
Processed files are then archived to a separate S3 prefix.

**KPIs to compute, daily per genre:**
- Listen count
- Unique listeners
- Total listening time
- Average listening time per user
- Top 3 songs per genre per day
- Top 5 genres per day (overall, by listen count)

**Full brief:** `../2--ETL with s3, dynamo and Glue [updated].docx`

---

## 2. Sample data (already in the workspace)

Located at `../data/` relative to this folder:

| File | Rows | Columns |
|---|---|---|
| `data/songs/songs.csv` | ~89,741 | id, track_id, artists, album_name, track_name, popularity, duration_ms, explicit, danceability, energy, key, loudness, mode, speechiness, acousticness, instrumentalness, liveness, valence, tempo, time_signature, **track_genre** |
| `data/users/users.csv` | ~50,000 | user_id, user_name, user_age, user_country, created_at |
| `data/streams/streams1.csv` | ~11,346 | user_id, track_id, listen_time (timestamp) |
| `data/streams/streams2.csv` | ~11,346 | same |
| `data/streams/streams3.csv` | ~11,346 | same |

Joins:
- `streams.track_id = songs.track_id` → pulls `track_genre`, `duration_ms`
- `streams.user_id = users.user_id` → pulls demographics if needed later

`duration_ms` from songs is the source of truth for "listening time" per play
(the stream rows have no end time — they're play events, not sessions).

---

## 3. Decisions already made with the user

| Topic | Decision |
|---|---|
| Environment | Real AWS account (not LocalStack) |
| Infra-as-Code | Terraform |
| Working style | Claude writes code, user reviews |
| Output location | This `pipeline/` subfolder inside Project 1 |
| Hardening (tests, CI, multi-env, remote tfstate, monitoring) | Deferred — ship the spine first, then layer on. Only git + .gitignore from day one. |

---

## 4. Folder layout

```
pipeline/
├── CLAUDE.md                     ← you are here
├── README.md                     ← runbook / setup steps for the human
├── .gitignore
├── terraform/                    ← all AWS resources
│   ├── main.tf                   provider, backend (local for now)
│   ├── variables.tf
│   ├── outputs.tf
│   ├── s3.tf                     bucket + prefixes + lifecycle
│   ├── dynamodb.tf               KPI tables
│   ├── iam.tf                    roles for Glue, Step Functions, EventBridge
│   ├── glue.tf                   3 Glue jobs (validate, transform, load)
│   └── step_functions.tf         state machine + EventBridge rule
├── glue_jobs/                    ← uploaded to s3://.../scripts/ by deploy.sh
│   ├── validate_streams.py       Python Shell — schema/column checks
│   ├── transform_kpis.py         PySpark — joins + KPI computation
│   └── load_dynamodb.py          Python Shell — boto3 batch_writer
├── step_functions/
│   └── state_machine.asl.json    Amazon States Language definition
├── scripts/
│   ├── deploy.sh                 sync glue_jobs/ to S3 + terraform apply
│   ├── upload_sample_data.sh     push local CSVs to s3://.../raw/
│   └── run_local_transform.py    local PySpark to sanity-check KPI logic
└── docs/
    ├── architecture.md
    ├── dynamodb_schema.md
    └── sample_queries.md
```

---

## 5. The 9-step plan (current status)

1. [x] **Scaffold project folder structure** — done in this commit
2. [ ] **Design DynamoDB schema for KPIs** — NEXT
3. [ ] Write Terraform for S3, DynamoDB, IAM
4. [ ] Write Glue validation job (Python Shell)
5. [ ] Write Glue transformation job (PySpark)
6. [ ] Write Glue DynamoDB load job
7. [ ] Write Step Functions state machine + EventBridge trigger
8. [ ] Write archival step + deploy scripts + docs
9. [ ] Local verification of PySpark KPI logic against the sample CSVs

**Pick up at Step 2.** Before writing any Terraform, decide partition/sort key
shapes for the DynamoDB tables, driven by these access patterns the brief
implies:

- "Daily genre KPIs on date X" → query by `(genre, date)`
- "Top 3 songs in genre G on date X" → query by `(genre, date)`, sort by play_count
- "Top 5 genres on date X" → query by `date`, sort by listen_count desc

Likely shape (proposal — confirm with user):
- **Table `daily_genre_kpis`**: PK `genre`, SK `date` → one item per (genre,date) with all 4 scalar KPIs
- **Table `top_songs_per_genre`**: PK `genre#date`, SK `rank` (1–3) → one item per song
- **Table `top_genres_per_day`**: PK `date`, SK `rank` (1–5) → one item per genre

---

## 6. Constraints / things to remember

- **The brief uses the word "streaming" loosely.** This is event-driven batch, not Spark Streaming. Don't reach for Kinesis / Structured Streaming.
- **Stream files arrive one at a time.** The pipeline should idempotently handle a single new file landing in `s3://.../raw/streams/`. Don't write logic that assumes all three files are present at once.
- **Listening time per play = `songs.duration_ms`.** The stream events have no end timestamp.
- **Validation must fail loudly.** Step Functions branches on validation result — a bad file should be moved to `s3://.../quarantine/` and an error logged, not silently skipped.
- **DynamoDB writes should be idempotent.** Re-running a day's data should overwrite, not append. Use `PutItem` (not `UpdateItem` with ADD).
- **Don't add tests, CI, remote tfstate, or multi-env until the spine works end-to-end.** Agreed with the user.

---

## 7. How to work with the user

- Mubarak prefers step-by-step delivery — one logical chunk at a time, with a check-in before moving on.
- Writes code, but wants Claude to produce it first so he can review.
- Asks "why" questions — explain trade-offs, don't just dump code.
- Prefers prose over heavy bullet formatting in conversational responses.
- Will switch between Cowork mode (this chat) and Claude Code in the IDE.
  Keep CLAUDE.md updated after each step so handoff is clean.

---

## 8. Useful commands (for later, once Terraform is written)

```bash
# from pipeline/
cd terraform && terraform init && terraform plan
cd terraform && terraform apply

# upload glue scripts + sample data
./scripts/deploy.sh
./scripts/upload_sample_data.sh

# local sanity check (no AWS needed)
python scripts/run_local_transform.py
```
