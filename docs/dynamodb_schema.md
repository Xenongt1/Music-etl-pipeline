# DynamoDB Schema

Three tables, each designed around a specific read access pattern.

---

## daily_genre_kpis

One item per `(genre, date)`. Holds the four scalar KPIs.

| Attribute | Key role | Type | Example |
|---|---|---|---|
| `genre` | Partition key | S | `"pop"` |
| `date` | Sort key | S | `"2024-01-15"` |
| `listen_count` | — | N | `4821` |
| `unique_listeners` | — | N | `1203` |
| `total_listening_time_ms` | — | N | `18340000` |
| `avg_listening_time_per_user_ms` | — | N | `15244` |

**Access pattern:** `GetItem(genre, date)` → O(1) read for a specific genre on a specific day.

---

## top_songs_per_genre

Three items per `(genre, date)` — one per rank position.

| Attribute | Key role | Type | Example |
|---|---|---|---|
| `genre_date` | Partition key | S | `"pop#2024-01-15"` |
| `rank` | Sort key | N | `1` |
| `track_id` | — | S | `"4BJqT0PrAfrxzMOxytFOIz"` |
| `track_name` | — | S | `"Shape of You"` |
| `artists` | — | S | `"Ed Sheeran"` |
| `play_count` | — | N | `312` |

**Access pattern:** `Query(genre_date = "pop#2024-01-15")` → returns ranks 1, 2, 3 in order.

---

## top_genres_per_day

Five items per date — one per rank position.

| Attribute | Key role | Type | Example |
|---|---|---|---|
| `date` | Partition key | S | `"2024-01-15"` |
| `rank` | Sort key | N | `1` |
| `genre` | — | S | `"pop"` |
| `listen_count` | — | N | `18432` |

**Access pattern:** `Query(date = "2024-01-15")` → returns ranks 1–5 in order.

---

## Notes

- All three tables use `PAY_PER_REQUEST` billing — no capacity planning needed for a batch pipeline with bursty write patterns.
- Writes are idempotent: the load job uses `PutItem` (full replace). Re-running for the same date overwrites cleanly.
- `rank` is stored as a Number (`N`) so DynamoDB sorts it numerically — `1 → 2 → 3`, not `"1" → "10" → "2"`.
