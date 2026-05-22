# Music Streaming ETL Pipeline

Near-real-time ETL pipeline that ingests music streaming event files from S3,
validates and transforms them with AWS Glue, computes daily KPIs per genre,
and loads results into DynamoDB. Orchestrated by AWS Step Functions and
triggered by S3 PutObject events via EventBridge.

> See [`CLAUDE.md`](./CLAUDE.md) for full project context, decisions, and the
> in-progress build plan.

## Architecture (high level)

```
  CSV lands in           EventBridge          Step Functions state machine
  s3://.../raw/streams/  ───────────────▶     ┌──────────────────────────┐
                                              │  validate (Python Shell) │
                                              │       │                  │
                                              │       ▼                  │
                                              │  transform (PySpark)     │
                                              │       │                  │
                                              │       ▼                  │
                                              │  load_dynamodb           │
                                              │       │                  │
                                              │       ▼                  │
                                              │  archive (S3 copy+del)   │
                                              └──────────────────────────┘
                                                        │
                                                        ▼
                                              DynamoDB KPI tables
```

## Folder layout

| Path | Purpose |
|---|---|
| `terraform/` | All AWS resources (S3, DynamoDB, IAM, Glue, Step Functions, EventBridge) |
| `glue_jobs/` | Python source for Glue jobs (uploaded to S3 by `deploy.sh`) |
| `step_functions/` | State machine definition (ASL JSON) |
| `scripts/` | Local helper scripts: deploy, upload sample data, local PySpark sanity check |
| `docs/` | Architecture diagram, DynamoDB schema rationale, sample query patterns |

## Quick start (once code is written)

```bash
# 1. configure AWS
aws configure

# 2. provision infrastructure
cd terraform
terraform init
terraform apply

# 3. upload Glue scripts + sample data
cd ..
./scripts/deploy.sh
./scripts/upload_sample_data.sh

# 4. watch the Step Function execution in the AWS console,
#    or query DynamoDB after it finishes
```

## Status

In active build — see the 9-step plan in `CLAUDE.md`. Currently between
Step 1 (scaffold ✅) and Step 2 (DynamoDB schema design).
