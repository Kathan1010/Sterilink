"""Synthetic data for Sterilink demo/dev. Safe to re-run: wipes all rows first."""
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import psycopg
from psycopg.rows import dict_row

from app.auth import hash_password
from app.config import settings

TRUNCATE_SQL = """
TRUNCATE batch_contents, sterilisation_batches, scheduled_operations,
  procedure_requirements, autoclaves, equipments, sterilisation_processes,
  procedures, users RESTART IDENTITY CASCADE;
"""

USERS = [
    ("scheduler1", "Dr. Rao", "sched123", "ENT_SCHEDULER"),
    ("staff1", "Nurse Kumar", "staff123", "STERILISATION_STAFF"),
    ("admin1", "Admin User", "admin123", "ADMIN"),
]

PROCESSES = [
    ("STEAM_134", 134.0, 30),       # instruments
    ("STEAM_LINEN", 121.0, 45),     # linen
]

EQUIPMENTS = [
    # name, category, process_name, total_quantity
    ("ENT Basic Instrument Set", "INSTRUMENT", "STEAM_134", 4),
    ("Tonsillectomy Set", "INSTRUMENT", "STEAM_134", 3),
    ("Microscope Attachments", "INSTRUMENT", "STEAM_134", 2),
    ("OT Linen Pack", "LINEN", "STEAM_LINEN", 6),
    ("Surgeon Gown Set", "LINEN", "STEAM_LINEN", 5),
]

PROCEDURES = [
    # name, duration_min, [(equipment_name, qty), ...]
    ("Tonsillectomy", 60, [
        ("ENT Basic Instrument Set", 1),
        ("Tonsillectomy Set", 1),
        ("OT Linen Pack", 1),
    ]),
    ("Septoplasty", 90, [
        ("ENT Basic Instrument Set", 1),
        ("Microscope Attachments", 1),
        ("OT Linen Pack", 1),
        ("Surgeon Gown Set", 1),
    ]),
    ("Myringotomy", 30, [
        ("ENT Basic Instrument Set", 1),
        ("OT Linen Pack", 1),
    ]),
]

AUTOCLAVES = [
    # name, process_name, capacity
    ("Autoclave-1", "STEAM_134", 5),
    ("Autoclave-2", "STEAM_134", 5),
    ("Autoclave-3", "STEAM_LINEN", 8),
]


def main():
    conn = psycopg.connect(settings.database_url, row_factory=dict_row, autocommit=False)
    with conn:
        conn.execute(TRUNCATE_SQL)

        user_ids = {}
        for username, name, password, role in USERS:
            row = conn.execute(
                """
                INSERT INTO users (username, name, password_hash, role)
                VALUES (%s, %s, %s, %s) RETURNING user_id
                """,
                (username, name, hash_password(password), role),
            ).fetchone()
            user_ids[username] = row["user_id"]

        process_ids = {}
        for name, temp, duration in PROCESSES:
            row = conn.execute(
                """
                INSERT INTO sterilisation_processes (process_name, temperature_c, duration_min)
                VALUES (%s, %s, %s) RETURNING process_id
                """,
                (name, temp, duration),
            ).fetchone()
            process_ids[name] = row["process_id"]

        equipment_ids = {}
        for name, category, process_name, qty in EQUIPMENTS:
            row = conn.execute(
                """
                INSERT INTO equipments (equipment_name, category, process_id, total_quantity)
                VALUES (%s, %s, %s, %s) RETURNING equipment_id
                """,
                (name, category, process_ids[process_name], qty),
            ).fetchone()
            equipment_ids[name] = row["equipment_id"]

        procedure_ids = {}
        for name, duration, requirements in PROCEDURES:
            row = conn.execute(
                """
                INSERT INTO procedures (procedure_name, duration_min)
                VALUES (%s, %s) RETURNING procedure_id
                """,
                (name, duration),
            ).fetchone()
            procedure_id = row["procedure_id"]
            procedure_ids[name] = procedure_id
            for equipment_name, qty in requirements:
                conn.execute(
                    """
                    INSERT INTO procedure_requirements (procedure_id, equipment_id, quantity)
                    VALUES (%s, %s, %s)
                    """,
                    (procedure_id, equipment_ids[equipment_name], qty),
                )

        for name, process_name, capacity in AUTOCLAVES:
            conn.execute(
                """
                INSERT INTO autoclaves (autoclave_name, process_id, capacity, status)
                VALUES (%s, %s, %s, 'AVAILABLE')
                """,
                (name, process_ids[process_name], capacity),
            )

        # A few operations scheduled later today/tomorrow so planning has room to work with.
        base = datetime.now(timezone.utc) + timedelta(hours=4)
        demo_operations = [
            ("Tonsillectomy", base),
            ("Septoplasty", base + timedelta(hours=2)),
            ("Myringotomy", base + timedelta(hours=1, minutes=30)),
        ]
        for procedure_name, scheduled_start in demo_operations:
            conn.execute(
                """
                INSERT INTO scheduled_operations (procedure_id, user_id, scheduled_start)
                VALUES (%s, %s, %s)
                """,
                (procedure_ids[procedure_name], user_ids["scheduler1"], scheduled_start),
            )

    print("Seed complete.")
    print("Login credentials:")
    for username, name, password, role in USERS:
        print(f"  {username} / {password}  ({role})")


if __name__ == "__main__":
    main()
