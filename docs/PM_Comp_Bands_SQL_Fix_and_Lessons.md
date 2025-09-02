## Program Management Compensation Bands SQL: Fixes, Reasoning, and Lessons

### What we did
- Repaired persistent MySQL 5.7 syntax errors in the Program Management compensation band matrix SQL used in Domo.
- Simplified and stabilized the Staff 62.5th percentile (p62) computation using a MySQL 5.7-safe approach (user variables + index join).
- Corrected JOIN aliasing and unmatched parentheses that caused errors near `ON 1=1` and `) ORDER BY`.
- Verified output: Step 1/2 for each level and Senior floor behavior matched expectations.
- Committed the working SQL to the repo.

### Why errors kept happening
- MySQL 5.7 has no window functions and is sensitive to:
  - WHERE/LIMIT placement inside subqueries joined by ON clauses
  - Derived tables requiring explicit aliases
  - Parenthesis balance before ORDER BY
- The failures clustered in a complex LEFT JOIN that computed Staff p62; LIMIT and WHERE placement after ON caused parse errors. A stray closing parenthesis before ORDER BY created the final “) ORDER BY …” error.

### Key fixes
- Move limiting logic inside subqueries (not after ON) or wrap the join results in an extra subquery and apply LIMIT to that layer.
- Ensure every derived table has an alias, and the ON clause refers to the outer subquery alias, not the inner one.
- Remove mismatched/extra parentheses so the main SELECT closes before ORDER BY.
- Replace the fragile p62 logic with a compact MySQL 5.7-safe percentile pattern.

### Final SQL (Program Management)
```sql
-- See file: Consulting Salary History for Modeling/Consultants_Salary_Data_projection_ProgramMgmtCompBandMatrix.SQL
-- This is the final, working version. It computes Step 1 (min), Step 2 (~62.5th percentile),
-- and applies guardrails including a Senior floor tied to Staff p62.

/* ----------------------------------------------------------------------------
   Program Management / Project Management Compensation Band Matrix
   Window: 2016-01-01 to 2022-01-31
   ... [header retained from file for context] ...
---------------------------------------------------------------------------- */

SELECT
  'Program Management' AS `Comp Group`,
  'Program Management,Project Management' AS `Department`,
  CASE WHEN cg.role_key = 'ASSOC_PC' THEN 'Program Coordinator,Project Coordinator'
       WHEN cg.role_key = 'STAFF_PM' THEN 'Program Manager,Project Manager'
       WHEN cg.role_key = 'SENIOR_SPM' THEN 'Senior Program Manager,Sr Program Manager,Senior Project Manager,Sr Project Manager'
  END AS `Roles/Titles`,
  CASE WHEN cg.role_key = 'ASSOC_PC' THEN 'Associate'
       WHEN cg.role_key = 'STAFF_PM' THEN 'Staff'
       WHEN cg.role_key = 'SENIOR_SPM' THEN 'Senior'
  END AS `Level`,
  CONCAT('Step ', s.step_order) AS `Step`,
  ROUND(
    CASE
      WHEN s.step_order = 1 AND cg.role_key <> 'SENIOR_SPM' THEN mn.min_usd
      WHEN s.step_order = 1 AND cg.role_key = 'SENIOR_SPM' THEN GREATEST(
        mn.min_usd,
        COALESCE(
          FLOOR(GREATEST(stp62.staff_p62_usd, COALESCE(stmin.staff_min_usd, 0) + 10000) / 5000) * 5000 + 1,
          COALESCE(stmin.staff_min_usd, 0) + 10001
        )
      )
      WHEN s.step_order = 2 THEN FLOOR(
        GREATEST(
          p62.salary_usd,
          (CASE WHEN cg.role_key = 'SENIOR_SPM' THEN GREATEST(
            mn.min_usd,
            COALESCE(
              FLOOR(GREATEST(stp62.staff_p62_usd, COALESCE(stmin.staff_min_usd, 0) + 10000) / 5000) * 5000 + 1,
              COALESCE(stmin.staff_min_usd, 0) + 10001
            )
          ) ELSE mn.min_usd END) + 10000
        ) / 5000
      ) * 5000
    END, 2
  ) AS `Annual Salary USD`,
  cnt.total_rows AS `Num Records`,
  DATE('2016-01-01') AS `Comp Band Start Date`,
  DATE('2022-01-31') AS `Comp Band End Date`
FROM (
  SELECT 'ASSOC_PC' AS role_key UNION ALL
  SELECT 'STAFF_PM' UNION ALL
  SELECT 'SENIOR_SPM'
) AS cg
JOIN (
  SELECT 1 AS step_order UNION ALL SELECT 2
) AS s
-- counts, minimums, p62 per role (omitted here for brevity)
LEFT JOIN (
  /* Staff 62.5th percentile (for Staff Step 2 guard used by Senior floor) */
  SELECT r.salary_usd AS staff_p62_usd
  FROM (
    SELECT ordered.salary_usd,
           @rn_spm := @rn_spm + 1 AS rn
    FROM (
      SELECT DISTINCT CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
      FROM `namely_comp_data_history_w_notes` c
      WHERE UPPER(TRIM(c.`Department`)) IN ('PROGRAM MANAGEMENT','PROJECT MANAGEMENT')
        AND UPPER(TRIM(c.`Job Title`)) LIKE '%PROGRAM MANAGER%'
        AND c.`Employee Type` = 'Staff Full Time'
        AND LOWER(TRIM(c.`Type`)) IN ('yearly','salary','salaried','annual')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
      ORDER BY salary_usd ASC
    ) AS ordered, (SELECT @rn_spm := 0) vars
  ) r
  JOIN (
    SELECT GREATEST(1, CEIL(COUNT(*) * 0.625)) AS idx_62
    FROM (
      SELECT DISTINCT CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
      FROM `namely_comp_data_history_w_notes` c
      WHERE UPPER(TRIM(c.`Department`)) IN ('PROGRAM MANAGEMENT','PROJECT MANAGEMENT')
        AND UPPER(TRIM(c.`Job Title`)) LIKE '%PROGRAM MANAGER%'
        AND c.`Employee Type` = 'Staff Full Time'
        AND LOWER(TRIM(c.`Type`)) IN ('yearly','salary','salaried','annual')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
    ) cnt
  ) idx ON idx.idx_62 = r.rn
  LIMIT 1
) AS stp62 ON 1=1
-- Staff minimum guardrail (see file for full context)
ORDER BY FIELD(`Level`, 'Associate','Staff','Senior','Director'), `Step`;
```

### Reasoning behind the Staff p62 pattern (MySQL 5.7-safe)
- Rank salaries with a user variable over an ordered derived table.
- Compute target index as CEIL(0.625 * N) in a separate subquery.
- JOIN on the index to pick the percentile row; optionally LIMIT 1 for safety.
- This avoids window functions (not in 5.7) and avoids invalid LIMIT/WHERE placement after ON.

### How to apply this to other departments
1. Copy the Staff p62 block and replace filters:
   - Replace department filter with the target department(s).
   - Replace title filter(s) to match the Staff-equivalent roles.
2. Keep the same 5.7-safe pattern:
   - ordered salaries + `@row := @row + 1` as rn
   - a count-based `idx_62` subquery
   - join `idx_62 = rn`
3. Common pitfalls to avoid:
   - Don’t place `WHERE ...` or `LIMIT` right after a `JOIN ... ON ...`; if you need to limit post-join, wrap the join in an outer SELECT and apply LIMIT there.
   - Every derived table must have its own alias.
   - Ensure all parentheses match before your final `ORDER BY`.
4. Guardrails and rounding:
   - Ensure Step 2 ≥ Step 1 + 10000.
   - Round as needed (e.g., to nearest 5000 via floor-divide/multiply pattern).
   - For Senior floors, use the Staff p62 result plus the guard as in PM.

### Lessons learned
- MySQL 5.7 is strict about derived table aliasing and clause order; window-like logic must be implemented with user variables.
- When you see errors near `ON ... WHERE ...` or `ON ... LIMIT`, it’s likely clause placement; move constraints into subqueries or wrap with another SELECT.
- Keep percentile and counting logic local, deterministic, and separately testable.
- Use a known-good simplified constant to unblock, validate downstream logic, then swap in the final logic.

### File locations
- Final SQL: `Consulting Salary History for Modeling/Consultants_Salary_Data_projection_ProgramMgmtCompBandMatrix.SQL`
- This guide: `docs/PM_Comp_Bands_SQL_Fix_and_Lessons.md`
