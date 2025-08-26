## Domo MySQL DataFlow: Consulting Comp + Title Override + Philosophy Mapping

This note documents the final approach, design choices, and key learnings so another developer can carry this forward in Domo (MySQL 5.7).

### Inputs
- `namely_comp_data_history_w_notes` (Comp history)
- `namely_title_history_data_aq` (Title history with change dates)
- `dataflow_schema.employee_org_units_dept_div_loc` (Org Units: Department, Division, Office Location per email with effective windows)
- `dataflow_schema.consulting_comp_philosophy` (Salary philosophy by Department/Title/Level/Step with effective windows)

### Business requirements implemented
- Keep Consulting population; Staff Full Time only; overlap with 2016-01-01+.
- Compute comp effective date: `comp_effective_date = COALESCE(Salary Start Date, Start Date)`.
- Override comp `Job Title` from Title History using ±15-day window around comp effective date, preferring on/before; fallback to latest title change prior to comp date if no window match.
- Join Org Units (Dept/Division/Office Location) by email using effective-dated windows selecting the latest start_date covering the comp date, per type independently.
- Salary philosophy mapping to Level/Step/Target with priority:
  1) Title + Department match
  2) Title-only match
  3) Department-based (post-policy window)
  4) Department-based (pre-policy window)

### Remote salary policy
- Effective 2022-07-01 only, `Office Location = Remote` salaries were reduced by 10%.
- We gross-up the observed comp salary by dividing by 0.9 when comparing to philosophy for matches on/after 2022-07-01, to avoid incorrectly lowering the inferred Level/Step due to the reduction.
- Pre-policy periods (< 2022-07-01) do not apply any remote adjustment.

### Key technical decisions
1) MySQL 5.7 compatibility: No CTEs or window functions. We rewrote windowed logic using derived tables and aggregates.
2) Duplicate row prevention: We replaced multi-row `LEFT JOIN`s to the philosophy table with scalar correlated subqueries and `COALESCE` in the `SELECT`. This preserves mapping priority and guarantees at most one row per comp record.
3) Title matching robustness: Title matches use either `FIND_IN_SET` on comma-separated lists or a loose `LOCATE`-based normalization (remove punctuation and compare uppercased tokens) when the list representation varies.
4) Org Unit selection: For each OU type, we first compute the latest `start_date` that covers the comp date, then join back to extract the single row (avoids duplication across overlapping OU assignments).
5) Fallback logic sequencing: Title within ±15 days → latest prior → original comp title as last resort.

### Final query location
- See `SQL/comp_title_override_mysql57.sql` for a compact, ready-to-paste version that outputs a Consulting-only comp history with title override and debug fields.
- See `Consulting Salary History for Modeling/Consultants_Salary_Data_projection.SQL` for the full end-to-end variant that also aligns Org Units and philosophy mapping as of the latest edits.

### Output fields (high level)
- Job title (overridden), Title Change Date (Used), Comp Effective Date
- Org Units (Office Location/Department/Division) with start/end dates
- Other comp attributes (Salary, Type, Notes, meta names, etc.)
- Mapped `Level`, `Step`, `Target Annual Salary USD` from philosophy using priority rules

### Data quality diagnostics
- Misalignment report: use `SQL/misalignment_report_mysql57.sql` to list comp rows where no title matched within the ±15-day window and no prior fallback existed; shows nearest title dates before/after and a reason.
- QA snippets for DataFlow output (replace `output` with your transform output name):
  - Duplicates per employee/date
    ```sql
    SELECT `Employee Number`, `Comp Effective Date`, COUNT(*) c
    FROM output
    GROUP BY 1,2
    HAVING c > 1
    ORDER BY c DESC, 1,2;
    ```
  - Missing Level/Step/Target
    ```sql
    SELECT COUNT(*) total,
           SUM(`Level` IS NULL) no_level,
           SUM(`Step` IS NULL)  no_step,
           SUM(`Target Annual Salary USD` IS NULL) no_target
    FROM output;
    ```
  - Remote policy check (post-2022-07-01)
    ```sql
    SELECT `Employee Number`,`Office Location`,`Comp Effective Date`,
           `Salary`,`Target Annual Salary USD`,
           ROUND(`Salary`/`Target Annual Salary USD`,3) AS salary_to_target
    FROM output
    WHERE UPPER(`Office Location`)='REMOTE'
      AND `Comp Effective Date` >= '2022-07-01'
    ORDER BY 1,2,3;
    ```

### Known edge cases and notes
- If an employee has absolutely no title history, the original comp `Job Title` remains and `Title Change Date (Used)` is NULL.
- Philosophy mappings fall back in the priority order; if a higher-priority branch has no viable match in its date window, the next branch is evaluated.
- Before 2022-07-01, nearest-step-by-salary logic is executed without remote adjustment; on/after 2022-07-01, remote gross-up is applied where `Office Location = Remote`.
- The OU dataset can contain overlapping rows; we guard by choosing the latest `start_date` covering the comp date.

### What we changed along the way (timeline highlights)
- Initial simple projection for Consulting since 2016.
- Added title override with ±15-day tolerance and fallback-before.
- Debugged duplication caused by joining multiple philosophy rows; switched to scalar subqueries with `COALESCE`.
- Introduced Org Unit effective-dated joins per type (Department/Division/Office).
- Implemented Remote 10% policy (effective 2022-07-01) as a matching-time gross-up so Level/Step selection is unaffected by the reduction.
- Fixed a syntax error caused by leaving a second `SELECT` statement in the file; ensured one-statement output for Domo.

### How to run in Domo
1) Create a MySQL DataFlow and add inputs for the comp, title history, OU assignment table, and philosophy.
2) Add a SQL transform and paste `SQL/comp_title_override_mysql57.sql` (or the longer end-to-end version you need).
3) Configure an Output Dataset and Run.
4) Optionally add another SQL transform using `SQL/misalignment_report_mysql57.sql` and create a second Output Dataset for QA.

### Future improvements
- Replace `FIND_IN_SET`/`LOCATE` with a normalized title dictionary/table (synonyms to canonical titles).
- Parameterize date thresholds (e.g., policy effective date) via variables or a small config table.
- Consider migrating to a warehouse that supports window functions/CTEs to simplify priority selection logic.


