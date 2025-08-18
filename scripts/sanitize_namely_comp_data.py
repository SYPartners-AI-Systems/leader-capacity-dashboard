#!/usr/bin/env python3
"""
Sanitize Namely compensation history workbook by removing PII/sensitive columns.

Usage examples:
  python scripts/sanitize_namely_comp_data.py \
    --input "Consulting Salary History for Modeling/Namely Comp Data (History w_ Notes).xlsx"

  python scripts/sanitize_namely_comp_data.py \
    --input ".../Namely Comp Data (History w_ Notes).xlsx" \
    --output ".../Namely_Comp_Data_sanitized.xlsx" \
    --extra-exclude "gender,ethnicity" \
    --keep "employee id"

What it does:
  - Loads all sheets from the input Excel workbook
  - Drops columns whose names match default sensitive keywords (case-insensitive)
  - Optional: add more exclusions via --extra-exclude or protect columns via --keep
  - Writes sanitized workbook and a CSV report of removed columns per sheet
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Set, Tuple


DEFAULT_SENSITIVE_KEYWORDS: Tuple[str, ...] = (
    # Names and identifiers
    "name", "first name", "last name", "middle name", "preferred name", "legal name",
    "nickname", "full name", "display name",
    "employee id", "employee number", "namely id", "user id", "uuid",
    # Contact
    "email", "e-mail", "phone", "mobile", "cell", "home phone",
    # Address
    "address", "street", "apt", "suite", "city", "state", "province", "county",
    "postal", "zipcode", "zip", "country",
    # Personal identifiers
    "birth", "dob", "date of birth", "ssn", "social security", "national id",
    "national identifier", "nin", "sin", "passport", "visa",
    # Financial / tax
    "bank", "account", "acct", "routing", "iban", "swift", "tax", "withholding",
    # Emergency / dependents
    "emergency", "dependent",
    # Manager PII
    "manager name", "manager email", "manager phone",
    # Free text / attachments
    "note", "notes", "comment", "comments", "attachment", "attachments", "description",
)


@dataclass
class SanitizeConfig:
    input_path: Path
    output_path: Path
    report_path: Path
    extra_exclude_keywords: Tuple[str, ...]
    keep_keywords: Tuple[str, ...]
    include_divisions: Tuple[str, ...]
    exclude_divisions: Tuple[str, ...]
    min_start_date: str
    dry_run: bool


def parse_args() -> SanitizeConfig:
    parser = argparse.ArgumentParser(description="Sanitize Namely compensation workbook by removing PII columns")
    parser.add_argument(
        "--input",
        required=False,
        default="Consulting Salary History for Modeling/Namely Comp Data (History w_ Notes).xlsx",
        help="Path to source Excel workbook",
    )
    parser.add_argument(
        "--output",
        required=False,
        default="Consulting Salary History for Modeling/Namely_Comp_Data_sanitized.xlsx",
        help="Path to write sanitized Excel workbook",
    )
    parser.add_argument(
        "--report",
        required=False,
        default="Consulting Salary History for Modeling/Namely_Comp_Data_sanitized_report.csv",
        help="Path to write CSV report of removed columns per sheet",
    )
    parser.add_argument(
        "--extra-exclude",
        required=False,
        default="",
        help="Comma-separated additional keywords to exclude (case-insensitive substring match)",
    )
    parser.add_argument(
        "--keep",
        required=False,
        default="",
        help="Comma-separated keywords to always keep (override exclusions)",
    )
    parser.add_argument(
        "--include-division",
        required=False,
        default="",
        help="Comma-separated Division values to keep (case-insensitive exact match). If provided, overrides --exclude-division",
    )
    parser.add_argument(
        "--exclude-division",
        required=False,
        default="MLT,Internal Partners",
        help="Comma-separated Division values to exclude (case-insensitive exact match)",
    )
    parser.add_argument(
        "--min-start-date",
        required=False,
        default="2017-01-01",
        help="Minimum Start Date (inclusive) to keep, ISO format YYYY-MM-DD",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only print what would be removed, do not write files",
    )

    args = parser.parse_args()

    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()
    report_path = Path(args.report).expanduser().resolve()

    extra = tuple(k.strip() for k in args.extra_exclude.split(',') if k.strip())
    keep = tuple(k.strip() for k in args.keep.split(',') if k.strip())
    include_div = tuple(v.strip() for v in args.include_division.split(',') if v.strip())
    exclude_div = tuple(v.strip() for v in args.exclude_division.split(',') if v.strip())

    return SanitizeConfig(
        input_path=input_path,
        output_path=output_path,
        report_path=report_path,
        extra_exclude_keywords=extra,
        keep_keywords=keep,
        include_divisions=include_div,
        exclude_divisions=exclude_div,
        min_start_date=str(args.min_start_date),
        dry_run=bool(args.dry_run),
    )


def normalize(text: str) -> str:
    return text.strip().lower()


def compute_columns_to_drop(
    columns: Iterable[str],
    sensitive_keywords: Iterable[str],
    keep_keywords: Iterable[str],
) -> Set[str]:
    normalized_columns: List[Tuple[str, str]] = [(c, normalize(str(c))) for c in columns]
    sens = [normalize(k) for k in sensitive_keywords]
    keep = [normalize(k) for k in keep_keywords]

    to_drop: Set[str] = set()
    for original, col in normalized_columns:
        if any(k in col for k in keep):
            continue
        if any(k in col for k in sens):
            to_drop.add(original)
    return to_drop


def ensure_dependencies() -> None:
    try:
        import pandas  # noqa: F401
    except Exception as exc:  # pragma: no cover - runtime guidance
        sys.stderr.write(
            "Error: pandas is not installed.\n"
            "Install dependencies first:\n"
            "  pip install -r requirements.txt\n\n"
        )
        raise


def sanitize_workbook(cfg: SanitizeConfig) -> Tuple[
    Dict[str, List[str]],
    Dict[str, List[str]],
    Dict[str, int],
    Dict[str, int],
]:
    import pandas as pd
    from pandas.api.types import is_datetime64_any_dtype as is_datetime

    xls = pd.ExcelFile(cfg.input_path)

    sensitive_keywords = DEFAULT_SENSITIVE_KEYWORDS + cfg.extra_exclude_keywords
    keep_keywords = cfg.keep_keywords

    removed_by_sheet: Dict[str, List[str]] = {}
    kept_by_sheet: Dict[str, List[str]] = {}
    sanitized_frames: Dict[str, "pd.DataFrame"] = {}
    original_row_counts: Dict[str, int] = {}
    kept_row_counts: Dict[str, int] = {}

    for sheet in xls.sheet_names:
        df = pd.read_excel(xls, sheet_name=sheet)
        original_row_counts[sheet] = len(df)

        # Row filtering based on Division and Start Date
        if "Division" in df.columns:
            if cfg.include_divisions:
                include_set = {v.lower() for v in cfg.include_divisions}
                df = df[df["Division"].astype(str).str.lower().isin(include_set)]
            elif cfg.exclude_divisions:
                exclude_set = {v.lower() for v in cfg.exclude_divisions}
                df = df[~df["Division"].astype(str).str.lower().isin(exclude_set)]

        if "Start Date" in df.columns:
            # Ensure datetime
            if not is_datetime(df["Start Date"]):
                df["Start Date"] = pd.to_datetime(df["Start Date"], errors="coerce")
            try:
                min_date = pd.to_datetime(cfg.min_start_date)
                df = df[(df["Start Date"].notna()) & (df["Start Date"] >= min_date)]
            except Exception:
                # If parsing fails, skip date filtering
                pass
        drop_cols = sorted(list(compute_columns_to_drop(df.columns, sensitive_keywords, keep_keywords)))
        kept_cols = [c for c in df.columns if c not in drop_cols]
        removed_by_sheet[sheet] = drop_cols
        kept_by_sheet[sheet] = list(map(str, kept_cols))
        filtered_df = df[kept_cols]
        kept_row_counts[sheet] = len(filtered_df)
        sanitized_frames[sheet] = filtered_df

    if not cfg.dry_run:
        # Write sanitized workbook
        with pd.ExcelWriter(cfg.output_path, engine="openpyxl") as writer:
            for sheet, sdf in sanitized_frames.items():
                sdf.to_excel(writer, sheet_name=sheet, index=False)

        # Write removal report
        import csv
        with cfg.report_path.open("w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["sheet", "removed_columns", "original_rows", "kept_rows"])
            for sheet, removed in removed_by_sheet.items():
                writer.writerow([
                    sheet,
                    "; ".join(map(str, removed)),
                    original_row_counts.get(sheet, 0),
                    kept_row_counts.get(sheet, 0),
                ])

    return removed_by_sheet, kept_by_sheet, original_row_counts, kept_row_counts


def main() -> None:
    cfg = parse_args()
    if not cfg.input_path.exists():
        sys.stderr.write(f"Input file not found: {cfg.input_path}\n")
        sys.exit(2)

    try:
        ensure_dependencies()
    except Exception:
        sys.exit(3)

    removed_by_sheet, kept_by_sheet, original_row_counts, kept_row_counts = sanitize_workbook(cfg)

    # Console summary
    print("Sensitive keyword defaults:")
    print(", ".join(DEFAULT_SENSITIVE_KEYWORDS))
    if cfg.extra_exclude_keywords:
        print("Extra exclusions:", ", ".join(cfg.extra_exclude_keywords))
    if cfg.keep_keywords:
        print("Keeps (override):", ", ".join(cfg.keep_keywords))

    print()
    for sheet in removed_by_sheet:
        removed = removed_by_sheet[sheet]
        kept = kept_by_sheet[sheet]
        print(f"Sheet: {sheet}")
        print(f"  Removed columns ({len(removed)}): {', '.join(map(str, removed)) if removed else '(none)'}")
        print(f"  Kept columns    ({len(kept)}): {', '.join(map(str, kept)) if kept else '(none)'}")
        print(f"  Rows: {original_row_counts.get(sheet, 0)} -> {kept_row_counts.get(sheet, 0)}")
        print()

    if cfg.dry_run:
        print("Dry run complete. No files written.")
    else:
        print(f"Sanitized workbook written to: {cfg.output_path}")
        print(f"Removal report written to:    {cfg.report_path}")


if __name__ == "__main__":
    main()

