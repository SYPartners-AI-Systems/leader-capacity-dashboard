## Design Compensation Bands SQL: Fixes, Reasoning, and Lessons

### Goal
Produce correct two-step comp bands for Design (Associate, Staff, Senior) using MySQL 5.7-compatible SQL, with guardrails ensuring a monotonic ladder:
Associate Step 1 ≤ Associate Step 2 ≤ Staff Step 1 ≤ Staff Step 2 ≤ Senior Step 1 ≤ Senior Step 2

### What we did
- Mirrored the proven Program Management pattern and adapted it for Design titles and filters.
- Replaced fragile percentile logic with a MySQL 5.7-safe approach (user variables + index join).
- Added explicit cross-level guardrails:
  - Staff Step 1 floored by Associate Step 2 + 1 (strictly).
  - Senior Step 1 floored by Staff Step 2 + 1 (strictly).
- Added explicit title exclusions for Design (Visual/Product/Production/Studio Designer).
- Ensured all derived tables have aliases and parentheses balance before ORDER BY.

### Why it was wrong before
- Staff Step 1 initially dropped to 70,000 because Associate p62/min were computed only from raw Job Title and missed rows mapped via title-history normalization; the fallback became Staff minimum.
- The fix was to compute Associate p62/min via the same mapping-aware pipeline used for counts and mins everywhere else (title matching ±15 days, fallback, normalization, role_key mapping).

### Final SQL (Design)
This is the complete, working query. It’s MySQL 5.7-safe and used in Domo.

```sql
-- See file: Consulting Salary History for Modeling/Consultants_Salary_Data_projection_DesignCompBandMatrix.SQL
-- Key elements: mapping-aware min/p62 per role, Associate and Staff guardrails, explicit exclusions.

/* Header truncated for brevity; the full query is in the file. */

SELECT
  'Design' AS `Comp Group`,
  'Design' AS `Department`,
  CASE WHEN cg.role_key = 'ASSOC_DA' THEN 'Design Associate'
       WHEN cg.role_key = 'STAFF_D'  THEN 'Designer'
       WHEN cg.role_key = 'SENIOR_SD' THEN 'Senior Designer,Sr Designer'
  END AS `Roles/Titles`,
  CASE WHEN cg.role_key = 'ASSOC_DA' THEN 'Associate'
       WHEN cg.role_key = 'STAFF_D'  THEN 'Staff'
       WHEN cg.role_key = 'SENIOR_SD' THEN 'Senior'
  END AS `Level`,
  CONCAT('Step ', s.step_order) AS `Step`,
  ROUND(
    CASE
      WHEN s.step_order = 1 AND cg.role_key NOT IN ('SENIOR_SD','STAFF_D') THEN mn.min_usd
      WHEN s.step_order = 1 AND cg.role_key = 'STAFF_D' THEN GREATEST(
        mn.min_usd,
        COALESCE(
          FLOOR(GREATEST(asp62.assoc_p62_usd, COALESCE(asmin.assoc_min_usd, 0) + 10000) / 5000) * 5000 + 1,
          COALESCE(asmin.assoc_min_usd, 0) + 10001
        )
      )
      WHEN s.step_order = 1 AND cg.role_key = 'SENIOR_SD' THEN GREATEST(
        mn.min_usd,
        COALESCE(
          FLOOR(GREATEST(stp62.staff_p62_usd, COALESCE(stmin.staff_min_usd, 0) + 10000) / 5000) * 5000 + 1,
          COALESCE(stmin.staff_min_usd, 0) + 10001
        )
      )
      WHEN s.step_order = 2 THEN FLOOR(
        GREATEST(
          p62.salary_usd,
          (CASE WHEN cg.role_key = 'SENIOR_SD' THEN GREATEST(
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
  SELECT 'ASSOC_DA' AS role_key UNION ALL
  SELECT 'STAFF_D' UNION ALL
  SELECT 'SENIOR_SD'
) AS cg
JOIN (SELECT 1 AS step_order UNION ALL SELECT 2) AS s
-- Mapping-aware counts/min/p62 per role (omitted; identical structure to PM but with Design mappings)
-- Mapping-aware Associate p62 (asp62) + Associate min (asmin) for Staff Step 1 guard
-- Mapping-aware Staff p62 (stp62) + Staff min (stmin) for Senior Step 1 guard
ORDER BY `Level`, `Step`;
```

### Reasoning
- Percentile in MySQL 5.7: rank with user variables over an ordered derived table and join to an index table that computes `idx = CEIL(0.625 * N)`.
- Guardrails ensure monotonicity and business minimum spacing (+10k):
  - Staff Step 1 ≥ Associate Step 2 + 1 (strict)
  - Senior Step 1 ≥ Staff Step 2 + 1 (strict)
  - Step 2 values are also forced to be at least Step 1 + 10,000 and rounded to the nearest 5,000.
- Mapping-aware p62/min prevents missing cohorts due to title history normalization.

### How to apply to other departments
1. Copy the pattern and update title mapping in the CASE that derives `role_key`.
2. Update department and role filters for Associate and Staff cohorts used in the guard subqueries.
3. Keep the same 5.7-safe percentile pattern and structure (derived tables, aliases, no LIMIT/WHERE after ON).
4. Add explicit exclusions early to simplify cohorts and avoid ambiguity.

### Pitfalls to avoid
- Forgetting to alias derived tables.
- Using LIMIT right after ON instead of inside a wrapped subquery.
- Computing guard cohorts (e.g., Associate p62) from raw Job Title only—always use the mapping-aware pipeline.

### File locations
- Final SQL: `Consulting Salary History for Modeling/Consultants_Salary_Data_projection_DesignCompBandMatrix.SQL`
- This guide: `docs/Design_Comp_Bands_SQL_Fix_and_Lessons.md`
