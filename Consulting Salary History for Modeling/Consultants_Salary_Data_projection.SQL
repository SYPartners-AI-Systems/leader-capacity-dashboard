-- Replace these with your actual table names in Domo (or your warehouse)
-- comp_source_table_name: rows from Namely Comp Data (History w_ Notes)
-- title_source_table_name: rows from Namely Title History Data (AQ)

WITH comp AS (
  SELECT
    c.*, 
    COALESCE(c."Salary Start Date", c."Start Date") AS "comp_effective_date",
    ROW_NUMBER() OVER (
      ORDER BY c."Employee Number", COALESCE(c."Salary Start Date", c."Start Date"), c."Salary End Date", c."Salary"
    ) AS comp_row_id
  FROM comp_source_table_name c
  WHERE UPPER(c."Division") = 'CONSULTING'
    AND c."Start Date" >= CAST('2016-01-01' AS DATE)
),
title AS (
  SELECT
    t."Employee Number",
    t."Title",
    t."Title Change Date"
  FROM title_source_table_name t
),
matches AS (
  -- Title changes within ±15 days of the comp effective date
  SELECT
    c.comp_row_id,
    t."Title",
    t."Title Change Date",
    ABS(DATEDIFF(day, t."Title Change Date", c."comp_effective_date")) AS diff_days,
    CASE WHEN t."Title Change Date" <= c."comp_effective_date" THEN 0 ELSE 1 END AS is_after
  FROM comp c
  JOIN title t
    ON t."Employee Number" = c."Employee Number"
  WHERE t."Title Change Date" IS NOT NULL
    AND ABS(DATEDIFF(day, t."Title Change Date", c."comp_effective_date")) <= 15
),
best_match AS (
  -- Choose the nearest change; prefer on/before the comp effective date
  SELECT *
  FROM (
    SELECT
      m.*,
      ROW_NUMBER() OVER (
        PARTITION BY m.comp_row_id
        ORDER BY m.is_after ASC, m.diff_days ASC, m."Title Change Date" DESC
      ) AS rn
    FROM matches m
  ) x
  WHERE rn = 1
),
fallback_before AS (
  -- If no match within 15 days, use the most recent title change before the comp date
  SELECT *
  FROM (
    SELECT
      c.comp_row_id,
      t."Title",
      t."Title Change Date",
      ROW_NUMBER() OVER (
        PARTITION BY c.comp_row_id
        ORDER BY t."Title Change Date" DESC
      ) AS rn
    FROM comp c
    JOIN title t
      ON t."Employee Number" = c."Employee Number"
    WHERE t."Title Change Date" <= c."comp_effective_date"
  ) y
  WHERE rn = 1
)
SELECT
  c."Salary Currency",
  c."Office Location",
  COALESCE(bm."Title", fb."Title", c."Job Title") AS "Job Title",
  c."Division",
  c."Salary Notes",
  c."Start Date",
  c."Employee Number",
  c."Level",
  c."Salary End Date",
  c."Step",
  c."Salary Start Date",
  c."Department",
  c."User Status",
  c."Last Name",
  c."Salary",
  c."Type",
  c."Employee Type",
  c."First Name"
FROM comp c
LEFT JOIN best_match bm ON bm.comp_row_id = c.comp_row_id
LEFT JOIN fallback_before fb ON fb.comp_row_id = c.comp_row_id;
