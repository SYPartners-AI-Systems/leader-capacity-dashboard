#!/usr/bin/env python3
"""
Export the misalignment report SQL to a dated CSV in the "CSV review/" directory.

This script reads the query from SQL/misalignment_report_mysql57.sql, executes it
against a MySQL database using credentials from environment variables, and writes
the results to a timestamped CSV file.

Environment variables:
  - DB_HOST: MySQL host (required)
  - DB_PORT: MySQL port (default: 3306)
  - DB_USER: MySQL username (required)
  - DB_PASSWORD: MySQL password (required)
  - DB_NAME: MySQL database name (required)

Usage examples:
  python scripts/export_misalignment_report.py
  python scripts/export_misalignment_report.py --outdir "CSV review" --sql SQL/misalignment_report_mysql57.sql
"""

import argparse
import os
import sys
from datetime import datetime
from typing import Optional

import pandas as pd
import mysql.connector


def resolve_project_root() -> str:
    current_file = os.path.abspath(__file__)
    project_root = os.path.dirname(os.path.dirname(current_file))
    return project_root


def read_env(name: str, default: Optional[str] = None) -> Optional[str]:
    value = os.environ.get(name, default)
    return value


def load_sql_file(sql_path: str) -> str:
    with open(sql_path, "r", encoding="utf-8") as f:
        sql_text = f.read()
    # Trim trailing semicolons and whitespace; some drivers are picky
    return sql_text.rstrip().rstrip(";")


def connect_mysql(host: str, port: int, user: str, password: str, database: str) -> mysql.connector.MySQLConnection:
    return mysql.connector.connect(
        host=host,
        port=port,
        user=user,
        password=password,
        database=database,
        connect_timeout=15,
        use_pure=True,
    )


def export_to_csv(df: pd.DataFrame, outdir: str) -> str:
    os.makedirs(outdir, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    outfile = os.path.join(outdir, f"misalignment_report_{timestamp}.csv")
    df.to_csv(outfile, index=False)
    return outfile


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(description="Export misalignment report to dated CSV")
    default_outdir = os.path.join(resolve_project_root(), "CSV review")
    default_sql = os.path.join(resolve_project_root(), "SQL", "misalignment_report_mysql57.sql")
    parser.add_argument("--outdir", default=default_outdir, help="Output directory for CSV files")
    parser.add_argument("--sql", default=default_sql, help="Path to the SQL file to execute")
    args = parser.parse_args(argv)

    # Database configuration from environment
    host = read_env("DB_HOST")
    user = read_env("DB_USER")
    password = read_env("DB_PASSWORD")
    database = read_env("DB_NAME")
    port_str = read_env("DB_PORT", "3306")

    missing = [name for name, val in {
        "DB_HOST": host,
        "DB_USER": user,
        "DB_PASSWORD": password,
        "DB_NAME": database,
    }.items() if not val]

    if missing:
        print(f"Error: Missing required environment variables: {', '.join(missing)}", file=sys.stderr)
        print("Set them and re-run. Example:", file=sys.stderr)
        print("  export DB_HOST=localhost DB_PORT=3306 DB_USER=user DB_PASSWORD=pass DB_NAME=dbname", file=sys.stderr)
        return 2

    try:
        port = int(port_str)
    except ValueError:
        print(f"Error: DB_PORT must be an integer, got '{port_str}'", file=sys.stderr)
        return 2

    # Load SQL
    sql_path = args.sql
    if not os.path.isabs(sql_path):
        sql_path = os.path.join(resolve_project_root(), sql_path)
    if not os.path.exists(sql_path):
        print(f"Error: SQL file not found: {sql_path}", file=sys.stderr)
        return 2
    query = load_sql_file(sql_path)

    # Execute and export
    try:
        conn = connect_mysql(host=host, port=port, user=user, password=password, database=database)
    except mysql.connector.Error as err:
        print(f"Error: Failed to connect to MySQL: {err}", file=sys.stderr)
        return 1

    try:
        df = pd.read_sql(query, conn)
    except Exception as err:
        print(f"Error: Query execution failed: {err}", file=sys.stderr)
        return 1
    finally:
        try:
            conn.close()
        except Exception:
            pass

    try:
        outfile = export_to_csv(df, args.outdir)
    except Exception as err:
        print(f"Error: Failed to write CSV: {err}", file=sys.stderr)
        return 1

    print(f"Wrote {len(df):,} rows to {outfile}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


