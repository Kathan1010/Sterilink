# Sterilink

Sterilink is a sterilisation scheduling and tracking system for hospital ENT (Ear, Nose and Throat) surgical departments. It links scheduled operations to the sterilisation of the instruments and linen they require, plans autoclave batches so that every operation has sterile equipment ready on time, and replans automatically when an autoclave fails.

The system combines a PostgreSQL relational core with strict, database-enforced integrity rules, a MongoDB event log for auditability, a FastAPI backend that hosts the planning and replanning logic, a React single-page application for schedulers and sterilisation staff, and an optional natural-language assistant that answers operational questions through read-only SQL.

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Key Features](#key-features)
3. [Project Status](#project-status)
4. [Architecture](#architecture)
5. [Technology Stack](#technology-stack)
6. [Data Model](#data-model)
7. [Database Integrity Rules](#database-integrity-rules)
8. [Scheduling and Replanning](#scheduling-and-replanning)
9. [Event Log](#event-log)
10. [API Overview](#api-overview)
11. [Repository Structure](#repository-structure)
12. [Getting Started](#getting-started)
13. [Configuration](#configuration)
14. [User Roles](#user-roles)
15. [Roadmap](#roadmap)
16. [Contributing](#contributing)
17. [Design References](#design-references)

---

## Problem Statement

Every surgical procedure depends on a specific set of sterilised instruments and linen. In most hospitals, the link between the operating theatre schedule and the Central Sterile Services Department (CSSD) is managed manually, which leads to three recurring problems:

- **Late equipment.** Instrument sets are not ready when an operation is due to start, causing theatre delays.
- **Resource conflicts.** The same limited stock of instruments is committed to overlapping operations, or autoclaves are overloaded or loaded with items that need a different sterilisation process.
- **Poor failure handling.** When an autoclave breaks down mid-cycle, there is no systematic way to identify which operations are affected or to find the fastest alternative.

Sterilink addresses these problems by treating the operation schedule, equipment stock, autoclave capacity and sterilisation processes as a single, consistent model, and by automating batch planning and failure recovery.

---

## Key Features

- **Operation registration.** ENT schedulers register operations against a catalogue of procedures, each with a defined duration and equipment requirement list.
- **Automatic batch planning.** An Earliest-Deadline-First (EDF) planner assigns the required equipment to autoclave batches so that each batch completes before its operation, with a configurable ready buffer (30 minutes by default).
- **Database-enforced correctness.** Autoclave double-booking, over-capacity batches, process mismatches and equipment over-commitment are rejected by PostgreSQL constraints and triggers, regardless of which client performs the write.
- **Failure detection and replanning.** When an autoclave is reported as failed, its active batches are marked as affected, the dependent operations are flagged as at risk, and the replanner evaluates alternatives (another autoclave, waiting for repair, or an external sterilisation facility) and selects the earliest completion.
- **Delay alerts.** Alerts are raised only when no alternative can meet the operation's deadline, keeping notifications actionable.
- **Complete audit trail.** Every cycle start, completion, failure, plan dispatch and replanning decision is recorded in an append-only MongoDB event log.
- **Role-based access.** Authentication uses bcrypt-hashed passwords and JWT, with separate roles for schedulers, sterilisation staff and administrators.
- **Natural-language assistant.** A pluggable LLM provider translates questions such as "Which operations tomorrow are at risk?" into read-only SQL executed under a restricted database role.

---

## Project Status

Sterilink is under active development. The current state of each component is summarised below.

| Component | Status |
|-----------|--------|
| Build plan and design decisions (`docs/PLAN.md`) | Complete |
| PostgreSQL core schema (`database/schema.sql`) | Complete for the first slice |
| Validation triggers (`database/triggers.sql`) | Complete for the first slice (4 of 5 triggers) |
| Validation demo script (`database/test_invalid_inserts.sql`) | Complete — 6 rejection cases, one per constraint/trigger |
| Synthetic seed data (`backend/scripts/seed.py`) | Complete |
| FastAPI backend: auth, operations endpoints, EDF planner | Complete for the first slice |
| External facilities and failure-propagation trigger | Planned |
| Database views and read-only role | Planned |
| Replanner | Planned |
| MongoDB event log integration | Planned |
| React frontend: login, register operation, operations and batches view | Complete for the first slice |
| Read-only database role (`database/roles.sql`) | Complete |
| LLM assistant | Planned |

The first slice covers the core flow end to end: a scheduler logs in, registers an operation, and the backend plans its sterilisation batches on compatible autoclaves, enforced by the database at every step. Failure handling, external facilities and replanning are delivered in subsequent slices.

---

## Architecture

```
+---------------------------+          +-------------------------------+
|   React (Vite) SPA        |  HTTPS   |   FastAPI backend             |
|                           | <------> |                               |
|  - Scheduler view         |   JWT    |  routers/                     |
|  - Sterilisation board    |          |    operations, batches,       |
|  - Autoclave timeline     |          |    autoclaves, events,        |
|  - Event timeline         |          |    assistant                  |
|  - Assistant panel        |          |  services/                    |
+---------------------------+          |    planner    (EDF)           |
                                       |    replanner                  |
                                       |    events                     |
                                       |    llm        (pluggable)     |
                                       +---------------+---------------+
                                                       |
                         +-----------------------------+-----------------------------+
                         |                                                           |
          +--------------v--------------+                             +--------------v--------------+
          |  PostgreSQL 17              |                             |  MongoDB                    |
          |                             |                             |                             |
          |  - Master and operational   |                             |  event_log collection       |
          |    tables                   |                             |  (append-only audit trail,  |
          |  - CHECK / EXCLUDE          |                             |   notifications)            |
          |    constraints              |                             |                             |
          |  - Validation triggers      |                             +-----------------------------+
          |  - Reporting views          |
          |  - sterilink_readonly role  |
          +-----------------------------+
```

**Design principle:** business invariants that must never be violated live in the database, not only in application code. The backend is responsible for planning decisions; PostgreSQL is responsible for guaranteeing that any plan written to it is physically feasible.

---

## Technology Stack

| Layer | Technology |
|-------|------------|
| Relational database | PostgreSQL 17 with the `btree_gist` extension |
| Event store | MongoDB |
| Backend | Python 3.12, FastAPI, psycopg 3, pymongo |
| Authentication | bcrypt password hashing, JSON Web Tokens |
| Frontend | React with Vite |
| Scheduling | Rule-based Earliest-Deadline-First planner (OR-Tools CP-SAT as a stretch goal) |
| AI assistant | Provider-agnostic `LLMProvider` interface, natural language to read-only SQL |
| Version control | Git and GitHub, feature-branch workflow |

---

## Data Model

The relational schema follows the project's Entity-Relationship Diagram. Tables are grouped into master data, which changes rarely, and operational data, which changes throughout the day.

### Master data

| Table | Purpose | Key columns |
|-------|---------|-------------|
| `users` | System users and their roles | `username` (unique), `password_hash`, `role` |
| `procedures` | Catalogue of ENT procedures | `procedure_name` (unique), `duration_min` |
| `sterilisation_processes` | Sterilisation methods and their cycle parameters | `process_name`, `temperature_c`, `duration_min` |
| `equipments` | Instrument and linen types held in stock | `category` (`INSTRUMENT` or `LINEN`), `process_id`, `total_quantity` |
| `procedure_requirements` | Equipment and quantities each procedure needs | Composite key `(procedure_id, equipment_id)`, `quantity` |
| `autoclaves` | Sterilisation machines | `process_id`, `capacity`, `status`, `available_from` |

### Operational data

| Table | Purpose | Key columns |
|-------|---------|-------------|
| `scheduled_operations` | Operations registered by schedulers | `procedure_id`, `user_id`, `scheduled_start`, `status` |
| `sterilisation_batches` | Autoclave cycles planned for an operation | `operation_id`, `autoclave_id`, `start_time`, `expected_end`, `status` |
| `batch_contents` | Equipment loaded into each batch | Composite key `(batch_id, equipment_id)`, `quantity` |

### Status lifecycles

| Entity | Allowed statuses |
|--------|------------------|
| Autoclave | `AVAILABLE`, `RUNNING`, `FAILED`, `MAINTENANCE` |
| Operation | `SCHEDULED`, `PLANNED`, `READY`, `AT_RISK`, `DELAYED`, `COMPLETED`, `CANCELLED` |
| Batch | `PLANNED`, `RUNNING`, `COMPLETED`, `FAILED`, `AFFECTED`, `CANCELLED` |

### Planned additions

- `external_facilities` table (`facility_name`, `transport_min`, `turnaround_min`) for outsourcing sterilisation when in-house capacity is unavailable.
- `sterilisation_batches.facility_id`, with a constraint that exactly one of `autoclave_id` or `facility_id` is set.

---

## Database Integrity Rules

The database enforces the following rules independently of the application layer.

### Declarative constraints

- All durations, capacities, temperatures and quantities must be positive; stock quantities must be non-negative.
- A batch's `expected_end` must be later than its `start_time`.
- Role, category and status columns are restricted to their allowed values.
- **No autoclave double-booking.** An `EXCLUDE USING gist` constraint prevents two `PLANNED` or `RUNNING` batches on the same autoclave from having overlapping time ranges.

### Triggers

| # | Trigger | Table | Behaviour |
|---|---------|-------|-----------|
| 1 | `trg_compute_batch_end` | `sterilisation_batches` | Sets `expected_end` to `start_time` plus the duration of the autoclave's sterilisation process. Clients never supply this value directly. |
| 2 | `trg_check_process_match` | `batch_contents` | Rejects equipment whose required sterilisation process differs from the process run by the batch's autoclave. |
| 3 | `trg_check_batch_capacity` | `batch_contents` | Rejects a batch whose total loaded quantity exceeds the autoclave's capacity. |
| 4 | `trg_check_equipment_availability` | `batch_contents` | Rejects a load if the equipment is already committed to overlapping busy windows beyond its `total_quantity`. |
| 5 | Failure propagation (planned) | `autoclaves` | When an autoclave becomes `FAILED`, marks its `PLANNED` and `RUNNING` batches as `AFFECTED` and their operations as `AT_RISK`. |

**Equipment busy window.** An item of equipment is considered unavailable from the start of its sterilisation batch until the end of the operation that uses it (`scheduled_start + procedure duration`). This models the full period during which the item is in the sterilisation and surgical loop.

Triggers 3 and 4 are implemented as constraint triggers that run after the row is written, so the check sees the complete batch contents.

### Concurrency

Batch assignment runs inside a transaction that locks the relevant autoclave rows with `SELECT ... FOR UPDATE`, preventing two concurrent planners from committing conflicting batches.

---

## Scheduling and Replanning

### Initial planning

1. An operation is registered with a procedure and a scheduled start time.
2. The planner derives the required equipment from `procedure_requirements`.
3. Equipment is grouped by sterilisation process and assigned to compatible autoclaves.
4. Operations are processed in Earliest-Deadline-First order, where the deadline is `scheduled_start` minus the ready buffer.
5. The resulting batches are written in a single transaction; the database rejects any infeasible plan.

### Replanning after a failure

When an autoclave fails, each affected batch is re-evaluated against three options:

| Option | Completion time |
|--------|-----------------|
| Another compatible autoclave | Next free slot on that autoclave plus process duration |
| Wait for the failed autoclave | `available_from` (expected repair time) plus process duration |
| External facility | Transport out plus turnaround plus transport back |

The option with the **earliest completion** is selected; ties are resolved in favour of in-house sterilisation. A delay alert is raised only if the chosen option still completes after the operation's deadline. Every decision, including the options considered, is recorded in the event log.

---

## Event Log

MongoDB holds a single append-only collection, `event_log`, which serves as the audit trail and the source for in-app notifications.

```json
{
  "event_type": "REPLAN_DECISION",
  "ts": "2026-11-22T09:15:00+05:30",
  "actor_user_id": 3,
  "operation_id": 12,
  "batch_id": 40,
  "autoclave_id": 2,
  "payload": {
    "old_assignment": { "autoclave_id": 2 },
    "new_assignment": { "autoclave_id": 4 },
    "old_expected_end": "2026-11-22T10:00:00+05:30",
    "new_expected_end": "2026-11-22T10:20:00+05:30",
    "options_evaluated": [],
    "option_chosen": "OTHER_AUTOCLAVE"
  }
}
```

**Event types:** `CYCLE_STARTED`, `CYCLE_COMPLETED`, `CYCLE_FAILED`, `AUTOCLAVE_STATUS_CHANGED`, `OPERATION_SCHEDULED`, `PLAN_SENT`, `REPLAN_DECISION`, `DELAY_ALERT`, `NOTIFICATION_ACK`.

**Indexes:** `ts`, `operation_id`, `batch_id`, `event_type`.

---

## API Overview

The REST endpoints map directly to the processes in the project's Data Flow Diagrams. Implemented endpoints are marked below; the rest are planned for later slices.

| Method and path | Description | DFD process | Status |
|-----------------|-------------|-------------|--------|
| `POST /auth/login` | Log in, returns a JWT | — | Implemented |
| `POST /operations` | Register an operation and immediately plan its sterilisation batches | 1.1 Register Operation + 1.2 to 2.3 Generate Plan | Implemented |
| `GET /operations` | List all operations | — | Implemented |
| `GET /operations/{id}` | Get one operation with its planned batches | — | Implemented |
| `GET /procedures` | List procedures (for the registration form) | — | Implemented |
| `POST /batches/{id}/start` | Mark a batch cycle as started | 3.1 Cycle Updates | Planned |
| `POST /batches/{id}/complete` | Mark a batch cycle as completed | 3.1 Cycle Updates | Planned |
| `POST /batches/{id}/fail` | Report a failed cycle | 3.1 Cycle Updates | Planned |
| `PATCH /autoclaves/{id}/status` | Change autoclave status, triggering replanning on failure | 3.1, 4.1 to 4.3 Replan and Notify | Planned |
| `GET /events?operation_id={id}` | Retrieve the event timeline for an operation | Event Log | Planned |
| `POST /assistant/query` | Ask a natural-language question | AI Assistant | Planned |

Note: `POST /operations` currently combines registration and planning into a single call, rather than the two-step `POST /operations` + `POST /operations/{id}/plan` split shown in the DFD — simpler for the first slice; may be split later if the UI needs to show the raw registration before planning completes.

---

## Repository Structure

```
Sterilink/
|-- docs/
|   `-- PLAN.md               Build plan, design decisions and phase schedule
|-- database/
|   |-- schema.sql            Tables, keys, CHECK and EXCLUDE constraints, indexes
|   |-- triggers.sql          Validation and derivation triggers
|   |-- views.sql             Reporting views (planned)
|   `-- roles.sql             Restricted read-only role
|-- backend/
|   |-- .env.example          Environment variable template
|   |-- requirements.txt
|   |-- app/                  FastAPI application
|   |   |-- main.py, config.py, db.py, auth.py, schemas.py
|   |   |-- routers/          auth.py, operations.py
|   |   `-- services/         planner.py (EDF), replanner.py (planned)
|   |-- scripts/seed.py       Synthetic data generator
|   `-- tests/                (planned)
`-- frontend/                 React and Vite client (login, register operation, operations view)
```

---

## Getting Started

### Prerequisites

- PostgreSQL 17 or later
- MongoDB 6 or later
- Python 3.12
- Node.js 20 or later (for the frontend, once available)
- Git

### 1. Clone the repository

```bash
git clone https://github.com/Kathan1010/Sterilink.git
cd Sterilink
```

### 2. Create the PostgreSQL database

```bash
createdb -U postgres sterilink
psql -U postgres -d sterilink -f database/schema.sql
psql -U postgres -d sterilink -f database/triggers.sql
```

The schema enables the `btree_gist` extension, which ships with standard PostgreSQL distributions. The connecting user must have permission to create extensions.

### 3. Verify the installation

```bash
psql -U postgres -d sterilink -c "\dt"
psql -U postgres -d sterilink -c "SELECT tgname FROM pg_trigger WHERE NOT tgisinternal;"
```

The first command should list nine tables and the second should list the four validation triggers.

### 4. Configure the backend environment

```bash
cp backend/.env.example backend/.env
```

Edit `backend/.env` with your local credentials. See [Configuration](#configuration).

### 5. Start MongoDB

Ensure a MongoDB instance is running and reachable at the address configured in `MONGO_URL`. On Windows, MongoDB is typically installed as a service and starts automatically. Not yet required for the first slice (no event log integration yet), but the backend config expects the variable to be set.

### 6. Set up the Python backend

```bash
cd backend
python -m venv venv
venv\Scripts\activate          # Windows
# source venv/bin/activate     # macOS/Linux
pip install -r requirements.txt
```

### 7. Load synthetic data

```bash
python scripts/seed.py
```

This wipes and repopulates the database with sample procedures, equipment, autoclaves and three demo users (printed to the console on success).

### 8. Run the API

```bash
uvicorn app.main:app --reload --port 8000
```

Visit `http://127.0.0.1:8000/docs` for interactive API documentation. Log in via `POST /auth/login` with one of the seeded users, then call `POST /operations` with a `procedure_id` and a future `scheduled_start` to see the planner assign sterilisation batches.

### 9. Run the frontend

In a second terminal, with the API still running:

```bash
cd frontend
npm install
npm run dev
```

Open `http://localhost:5173` and log in with one of the seeded users (`scheduler1` / `sched123`, `staff1` / `staff123`, `admin1` / `admin123`).

### 10. Optional: read-only role and validation tests

```bash
psql -U postgres -d sterilink -f database/roles.sql
```

`database/test_invalid_inserts.sql` deliberately tries six invalid writes. Run it against a separate empty database (for example `sterilink_test`, loaded with `schema.sql` and `triggers.sql`), not the seeded one: it inserts its own rows and expects each invalid write to be rejected.

---

## Configuration

The backend reads its configuration from `backend/.env`.

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://postgres:password@127.0.0.1:5432/sterilink` |
| `MONGO_URL` | MongoDB connection string | `mongodb://127.0.0.1:27017` |
| `MONGO_DB` | MongoDB database name for the event log | `sterilink_events` |
| `JWT_SECRET` | Secret used to sign authentication tokens | A long, randomly generated string |

The `.env` file is excluded from version control. Never commit real credentials, and always replace the placeholder `JWT_SECRET` before sharing or deploying an instance.

All timestamps are stored as `timestamptz` and displayed in Indian Standard Time (IST).

---

## User Roles

| Role | Responsibilities |
|------|------------------|
| `ENT_SCHEDULER` | Registers and manages operations, reviews plans and readiness, receives delay alerts |
| `STERILISATION_STAFF` | Starts and completes cycles, reports cycle or autoclave failures, acknowledges notifications |
| `ADMIN` | Manages master data and users, changes autoclave status, runs demonstration scenarios |

---

## Roadmap

| Phase | Scope | Completion criteria |
|-------|-------|---------------------|
| 1 | Repository, schema, constraints, triggers, views, seed data | Schema loads; constraint tests reject overlaps and over-capacity batches |
| 2 | FastAPI skeleton, authentication, master-data and operation endpoints | Login works; operations can be registered |
| 3 | EDF planner, plan generation, event logging | Registering an operation produces valid batches |
| 4 | Cycle updates, failure trigger, replanner, delay alerts | Failing an autoclave replans and alerts only when an operation will be late |
| 5 | React interface: scheduler view, staff board, autoclave timeline, event timeline | Full workflow usable end to end |
| 6 | LLM assistant and demonstration scenario | Natural-language question produces read-only SQL and an answer |
| 7 | Testing, documentation, optional CP-SAT optimiser | Demonstration rehearsed |

---

## Contributing

1. Create a feature branch from `main`, for example `feature/replanner` or `db/views`.
2. Keep database changes in the `database/` directory and ensure the scripts load cleanly into an empty database in order.
3. Treat the ERD and DFDs as the specification. Any deviation must be recorded in `docs/PLAN.md`.
4. Open a pull request with a clear description of the change and how it was tested.

---

## Design References

- `docs/PLAN.md` contains the confirmed design decisions, proposed defaults, schema specification, DFD-to-module mapping and phase plan.
- The Entity-Relationship Diagram, ER mapping and Data Flow Diagrams (levels 0 to 2) form the authoritative specification for the data model and system processes.
