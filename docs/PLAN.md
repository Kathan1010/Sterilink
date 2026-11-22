# Sterilink – Build Plan & Decisions

Reference documents: Project proposal, ERD + ER mapping (`ERD.pdf`), DFD levels 0–2.
**Rule:** the ERD/DFD are the spec; the additions below are the only deviations.

---

## 1. Confirmed decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Schema scope | ERD's 9 tables + small additions (listed in §3) |
| 2 | Backend | Python 3.12 + FastAPI (psycopg 3 for PostgreSQL, pymongo for MongoDB) |
| 3 | Frontend | React (Vite) single-page app |
| 4 | Databases | Locally installed PostgreSQL 17 + MongoDB (already running as Windows services) |
| 5 | External facilities | Added: new table, batch can go to an autoclave **or** a facility |
| 6 | Autoclave ↔ process | One process per autoclave (as in ERD) |
| 7 | Batch ↔ operation | One operation per batch (as in ERD) |
| 8 | Equipment tracking | By count (`total_quantity`), availability enforced by trigger |
| 9 | Equipment "busy" window | From batch start → operation end (`scheduled_start + procedure duration`) |
| 10 | Ready buffer | Batch must finish ≥ 30 min (configurable) before the operation |
| 11 | Auth | Login with bcrypt-hashed passwords + JWT; roles ENT_SCHEDULER, STERILISATION_STAFF, ADMIN |
| 12 | AI scope (v1) | EDF rule-based scheduler + LLM NL→SQL assistant. CP-SAT is a stretch goal |
| 13 | Replanning policy | For each affected batch evaluate: other autoclave / wait for next free slot / external facility → pick **earliest completion**, tie → in-house. Delay alert only if still late |
| 14 | LLM provider | Decide later – build a pluggable `LLMProvider` interface |
| 15 | Collaboration | Git + private GitHub repo, feature branches |
| 16 | Timeline | 1–2 weeks → core flow + failure demo first, polish last |

---

## 2. Proposed defaults (confirm or change)

| # | Topic | Proposal |
|---|-------|----------|
| P1 | Autoclave capacity unit | Number of equipment sets per cycle (each `quantity` of 1 = 1 slot) |
| P2 | "Wait" option | Add `autoclaves.available_from` – set when a failure is reported (expected repair time) |
| P3 | External facility capacity | Unlimited; time = transport out + turnaround + transport back |
| P4 | Notifications | In-app only (stored in MongoDB, shown in UI with acknowledge button); no email/SMS |
| P5 | Time zone | All timestamps `timestamptz`, displayed in IST |
| P6 | Failure simulation | "Report failure" button for staff/admin + an admin "demo scenario" button |
| P7 | Synthetic data | Python seed script: ~8 ENT procedures, ~20 equipment types, 4 autoclaves, 2 external facilities, 1 week of operations |
| P8 | Team split | Member A: database (schema, triggers, views, seed) · Member B: backend + scheduler · Member C: frontend |

---

## 3. PostgreSQL schema (ERD + additions marked ➕)

```
users                   (user_id PK, name, username ➕ UNIQUE, password_hash, role CHECK)
procedures              (procedure_id PK, procedure_name UNIQUE, duration_min CHECK > 0)
sterilisation_processes (process_id PK, process_name, temperature_c, duration_min CHECK > 0)
equipments              (equipment_id PK, equipment_name, category CHECK IN ('INSTRUMENT','LINEN'),
                         process_id FK, total_quantity CHECK >= 0)
procedure_requirements  (procedure_id FK, equipment_id FK, quantity CHECK > 0)   PK(procedure_id, equipment_id)
autoclaves              (autoclave_id PK, autoclave_name, process_id FK, capacity CHECK > 0,
                         status CHECK IN ('AVAILABLE','RUNNING','FAILED','MAINTENANCE'),
                         available_from ➕ timestamptz NULL)
external_facilities ➕   (facility_id PK, facility_name, transport_min, turnaround_min)
scheduled_operations    (operation_id PK, procedure_id FK, user_id FK, scheduled_start,
                         status CHECK IN ('SCHEDULED','PLANNED','READY','AT_RISK','DELAYED','COMPLETED','CANCELLED'))
sterilisation_batches   (batch_id PK, operation_id FK, autoclave_id FK NULL, facility_id ➕ FK NULL,
                         start_time, expected_end ➕, status CHECK IN
                         ('PLANNED','RUNNING','COMPLETED','FAILED','AFFECTED','CANCELLED'))
batch_contents          (batch_id FK, equipment_id FK, quantity CHECK > 0)       PK(batch_id, equipment_id)
```

### Integrity enforced in the database
- **CHECK**: positive durations/capacities/quantities; `expected_end > start_time`;
  exactly one of `autoclave_id` / `facility_id` is set.
- **EXCLUDE USING gist** (needs `btree_gist`): no two active batches on the same autoclave
  with overlapping `tstzrange(start_time, expected_end)`.
- **Triggers**
  1. Compute `expected_end` (autoclave: start + process duration; facility: start + 2×transport + turnaround).
  2. Capacity: sum of `batch_contents.quantity` ≤ autoclave capacity.
  3. Process match: equipment's process = autoclave's process.
  4. Equipment availability: quantity in overlapping busy windows ≤ `total_quantity`.
  5. Autoclave → `FAILED`: mark its PLANNED/RUNNING batches `AFFECTED`, their operations `AT_RISK`.
- **Transactions + `SELECT … FOR UPDATE`** on autoclave rows during batch assignment.
- **Views**: `v_operations_at_risk`, `v_autoclave_schedule`, `v_equipment_usage`, `v_operation_readiness`.
- **Restricted role** `sterilink_readonly` (SELECT on views/tables only) for the LLM assistant.

---

## 4. MongoDB – `event_log` collection (M1)

One append-only collection; common fields + type-specific `payload`:

```json
{ "event_type": "CYCLE_STARTED | CYCLE_COMPLETED | CYCLE_FAILED | AUTOCLAVE_STATUS_CHANGED |
                 OPERATION_SCHEDULED | PLAN_SENT | REPLAN_DECISION | DELAY_ALERT | NOTIFICATION_ACK",
  "ts": "<datetime>", "actor_user_id": 3,
  "operation_id": 12, "batch_id": 40, "autoclave_id": 2,
  "payload": { ... } }
```
Indexes: `ts`, `operation_id`, `batch_id`, `event_type`.
Example `REPLAN_DECISION` payload: old/new assignment, old/new expected_end, options evaluated, option chosen.

---

## 5. DFD → module mapping

| DFD process | Backend module / endpoint |
|-------------|---------------------------|
| 1.1 Register Operation | `POST /operations` |
| 1.2–2.3 Generate & send plan | `services/planner.py` (EDF) → `POST /operations/{id}/plan` |
| 3.1 Cycle & autoclave updates | `POST /batches/{id}/start|complete|fail`, `PATCH /autoclaves/{id}/status` |
| 4.1–4.3 Replan & notify | `services/replanner.py`, triggered on failure |
| Event log / timeline | `GET /events?operation_id=` |
| AI assistant | `POST /assistant/query` |

---

## 6. Folder structure

```
Sterilink/
├── docs/                 PLAN.md, ERD, DFD
├── database/
│   ├── schema.sql        tables, constraints
│   ├── triggers.sql
│   ├── views.sql
│   └── roles.sql
├── backend/
│   ├── app/
│   │   ├── main.py, config.py, db.py, mongo.py, auth.py
│   │   ├── routers/      operations, batches, autoclaves, events, assistant
│   │   └── services/     planner.py, replanner.py, events.py, llm.py
│   ├── scripts/seed.py   synthetic data
│   └── tests/
└── frontend/             React + Vite
```

---

## 7. Phases (≈ 2 weeks)

| Days | Phase | Done when |
|------|-------|-----------|
| 1–2 | Repo, DB schema, constraints, triggers, views, seed data | `schema.sql` loads; constraint tests reject overlaps/over-capacity |
| 3–4 | FastAPI skeleton, auth, master-data + operation endpoints | Login works; can register an operation |
| 5–6 | EDF planner, plan generation, event logging | Registering an operation produces valid batches |
| 7–8 | Cycle updates, failure trigger, replanner, delay alerts | Failing an autoclave replans and alerts only when late |
| 9–10 | React UI: scheduler view, staff board, autoclave timeline, event timeline | Full flow clickable |
| 11–12 | LLM assistant, demo scenario script | NL question → read-only SQL → answer |
| 13–14 | Testing, report, buffer; CP-SAT if time permits | Demo rehearsed |
