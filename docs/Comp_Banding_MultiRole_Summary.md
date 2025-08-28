## Multi-Role Compensation Bands: What We Did, Learned, and Final SQL (2016-01-01 to 2022-01-31)

### Context
- We built percentile-based compensation bands for three roles: Creative Director (CD), Strategy Director (SD), and Program Director (PD).
- Source datasets:
  - `namely_comp_data_history_w_notes` (compensation events)
  - `namely_title_history_data_aq` (title history)

### How the data is merged (title-to-comp matching)
- Base rows come from `namely_comp_data_history_w_notes`, with `comp_effective_date = COALESCE(Salary Start Date, Start Date)`.
- For each comp row (per `Employee Number` + `comp_effective_date`), we select the most appropriate title from `namely_title_history_data_aq` using:
  1) On/before within 15 days (latest) → if none
  2) After within 15 days (earliest) → if none
  3) Fallback to latest prior title (no 15-day constraint) → if none
  4) Fallback to the comp row's original `Job Title`.
- All comp→title joins are left joins to preserve comp rows.

### Role-specific filters (final)
- Creative Director:
  - `Department = 'Design'`
  - Exclude titles containing "Freelance" (checked against the normalized title `COALESCE(mtit.Title, fbtit.Title, c.Job Title)`).
- Strategy Director:
  - `Department = 'Strategy'`
  - Exclude titles containing "Freelance"
  - Salary floor applied for SD: `>= 100000`
- Program Director:
  - `Department = 'Program Management'`
  - Exclude titles containing "Freelance"

### Step logic (final)
- Step 1: minimum salary from the filtered set.
- Step 2: median-ish (rank-based) from the same filtered set, with guardrails to ensure it differs from the minimum:
  - For SD and PD: derived via "next distinct salary above the minimum" helper (second-min) and then rounded down to a clean band.
  - For CD: derived via the same second-min approach and rounded down to a clean band.
- Step 3: ~90th percentile (rank-based) from the same filtered set.

### Rounding (final decision)
- We round Step 2 for all three roles down to the nearest 5,000 (i.e., `FLOOR(value/5000)*5000`). This produces cleaner bands and avoids Step 2 ≈ Step 3 when the dataset is small or clustered at the top. This rounding is mirrored in the single-role Creative Director SQL as well.

### Key issues we found and resolved
- Filter mismatch: Ranking subqueries initially did not fully match the counting/filtering logic (e.g., missing `Department` filter or SD salary floor). This caused unexpected Step values (like a global min sneaking in). We aligned all filters.
- Excluding Freelancers: We added `... NOT LIKE '%FREELANCE%'` checks to CD, SD, and PD across both count and ranking blocks.
- Department scoping: SD → `Strategy`, PD → `Program Management`, CD → `Design`. Ensured applied consistently everywhere.
- Step 2 too close to Step 3: With small N (e.g., 5 records) and top-heavy distributions, the 50th and 90th percentile can converge. We implemented the second-min logic and then rounded Step 2 to 5k bands.
- Syntax bug: A duplicated `WHERE` in the PD ranking block caused a MySQL syntax error; removed the duplicate.

### Final multi-role SQL
```sql
/* ----------------------------------------------------------------------------
   Multi-role compensation band calculation (2016-01-01 to 2022-01-31)
   Roles: Creative Director, Strategy Director, Program Director

   Methodology (percentile-based):
   - Step 1: minimum salary ("lowest range")
   - Step 2: ~50th percentile salary (discrete index via CEIL(0.50 * N))
   - Step 3: ~90th percentile salary (discrete index via CEIL(0.90 * N))

   Implementation notes (MySQL 5.7-compatible):
   - Percentiles approximated by selecting the salary at CEIL(p * N) after sorting
     ascending by salary, using user-variable row numbering.
   - Title matching mirrors prior approach: prefer on/before within 15 days,
     else after within 15 days; fallback to latest prior title if needed.
   - Filters: Employee Type = 'Staff Full Time', Type in {'yearly','salary','salaried','annual'},
     Salary not null and > 0, comp_effective_date within range.
---------------------------------------------------------------------------- */

(
SELECT
  'Creative Director' AS `Role`,
  'Design' AS `Department`,
  sr.step_order AS `Step Order`,
  sr.step_label AS `Step`,
  ROUND(
    CASE
      WHEN sr.step_order = 2 THEN FLOOR((
        SELECT IFNULL(
          (
            SELECT MIN(dx.salary_usd)
            FROM (
              SELECT DISTINCT CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
              FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) c2
              LEFT JOIN (
                SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
                FROM (
                  SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
                  FROM `namely_comp_data_history_w_notes`
                ) p
                LEFT JOIN (
                  SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
                  FROM (
                    SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
                    FROM `namely_comp_data_history_w_notes`
                  ) p2
                  JOIN (
                    SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
                    FROM `namely_title_history_data_aq`
                    WHERE `Title` IS NOT NULL
                  ) th2 ON th2.`Employee Number` = p2.`Employee Number`
                  WHERE th2.title_change_date <= p2.comp_effective_date
                    AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
                  GROUP BY p2.`Employee Number`, p2.comp_effective_date
                ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
                LEFT JOIN (
                  SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
                  FROM (
                    SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
                    FROM `namely_comp_data_history_w_notes`
                  ) p3
                  JOIN (
                    SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
                    FROM `namely_title_history_data_aq`
                    WHERE `Title` IS NOT NULL
                  ) th3 ON th3.`Employee Number` = p3.`Employee Number`
                  WHERE th3.title_change_date >= p3.comp_effective_date
                    AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
                  GROUP BY p3.`Employee Number`, p3.comp_effective_date
                ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
              ) chosen ON chosen.`Employee Number` = c2.`Employee Number` AND chosen.comp_effective_date = c2.comp_effective_date
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) mtit ON mtit.`Employee Number` = c2.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
              LEFT JOIN (
                SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
                FROM (
                  SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
                  FROM `namely_comp_data_history_w_notes`
                ) p
                JOIN (
                  SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
                  FROM `namely_title_history_data_aq`
                  WHERE `Title` IS NOT NULL
                ) th ON th.`Employee Number` = p.`Employee Number`
                WHERE th.title_change_date <= p.comp_effective_date
                GROUP BY p.`Employee Number`, p.comp_effective_date
              ) fb ON fb.`Employee Number` = c2.`Employee Number` AND fb.comp_effective_date = c2.comp_effective_date
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) fbtit ON fbtit.`Employee Number` = c2.`Employee Number` AND fbtit.title_change_date = fb.fb_date
              WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c2.`Job Title`))) = 'CREATIVE DIRECTOR'
                AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c2.`Job Title`))) NOT LIKE '%FREELANCE%'
                AND TRIM(c2.`Department`) = 'Design'
                AND UPPER(TRIM(c2.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(c2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND c2.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND c2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            ) dx
            WHERE dx.salary_usd > (
              SELECT MIN(mn.salary_usd)
              FROM (
                SELECT CAST(REPLACE(REPLACE(c3.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
                FROM (
                  SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                  FROM `namely_comp_data_history_w_notes` t1
                ) c3
                LEFT JOIN (
                  SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
                  FROM (
                    SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
                    FROM `namely_comp_data_history_w_notes`
                  ) p
                  LEFT JOIN (
                    SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
                    FROM (
                      SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
                      FROM `namely_comp_data_history_w_notes`
                    ) p2
                    JOIN (
                      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
                      FROM `namely_title_history_data_aq`
                      WHERE `Title` IS NOT NULL
                    ) th2 ON th2.`Employee Number` = p2.`Employee Number`
                    WHERE th2.title_change_date <= p2.comp_effective_date
                      AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
                    GROUP BY p2.`Employee Number`, p2.comp_effective_date
                  ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
                  LEFT JOIN (
                    SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
                    FROM (
                      SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
                      FROM `namely_comp_data_history_w_notes`
                    ) p3
                    JOIN (
                      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
                      FROM `namely_title_history_data_aq`
                      WHERE `Title` IS NOT NULL
                    ) th3 ON th3.`Employee Number` = p3.`Employee Number`
                    WHERE th3.title_change_date >= p3.comp_effective_date
                      AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
                    GROUP BY p3.`Employee Number`, p3.comp_effective_date
                  ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
                ) chosen ON chosen.`Employee Number` = c3.`Employee Number` AND chosen.comp_effective_date = c3.comp_effective_date
                LEFT JOIN (
                  SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                  FROM `namely_title_history_data_aq`
                  WHERE `Title` IS NOT NULL
                ) mtit ON mtit.`Employee Number` = c3.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
                LEFT JOIN (
                  SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
                  FROM (
                    SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
                    FROM `namely_comp_data_history_w_notes`
                  ) p
                  JOIN (
                    SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
                    FROM `namely_title_history_data_aq`
                    WHERE `Title` IS NOT NULL
                  ) th ON th.`Employee Number` = p.`Employee Number`
                  WHERE th.title_change_date <= p.comp_effective_date
                  GROUP BY p.`Employee Number`, p.comp_effective_date
                ) fb ON fb.`Employee Number` = c3.`Employee Number` AND fb.comp_effective_date = c3.comp_effective_date
                LEFT JOIN (
                  SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                  FROM `namely_title_history_data_aq`
                  WHERE `Title` IS NOT NULL
                ) fbtit ON fbtit.`Employee Number` = c3.`Employee Number` AND fbtit.title_change_date = fb.fb_date
                WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c3.`Job Title`))) = 'CREATIVE DIRECTOR'
                  AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c3.`Job Title`))) NOT LIKE '%FREELANCE%'
                  AND TRIM(c3.`Department`) = 'Design'
                  AND UPPER(TRIM(c3.`Employee Type`)) = 'STAFF FULL TIME'
                  AND UPPER(TRIM(c3.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                  AND c3.`Salary` IS NOT NULL
                  AND CAST(REPLACE(REPLACE(c3.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                  AND c3.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
              ) mn
            )
          ),
          (
            SELECT MIN(mn2.salary_usd)
            FROM (
              SELECT CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
              FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) c4
              LEFT JOIN (
                SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
                FROM (
                  SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
                  FROM `namely_comp_data_history_w_notes`
                ) p
                LEFT JOIN (
                  SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
                  FROM (
                    SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
                    FROM `namely_comp_data_history_w_notes`
                  ) p2
                  JOIN (
                    SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
                    FROM `namely_title_history_data_aq`
                    WHERE `Title` IS NOT NULL
                  ) th2 ON th2.`Employee Number` = p2.`Employee Number`
                  WHERE th2.title_change_date <= p2.comp_effective_date
                    AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
                  GROUP BY p2.`Employee Number`, p2.comp_effective_date
                ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
                LEFT JOIN (
                  SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
                  FROM (
                    SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
                    FROM `namely_comp_data_history_w_notes`
                  ) p3
                  JOIN (
                    SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
                    FROM `namely_title_history_data_aq`
                    WHERE `Title` IS NOT NULL
                  ) th3 ON th3.`Employee Number` = p3.`Employee Number`
                  WHERE th3.title_change_date >= p3.comp_effective_date
                    AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
                  GROUP BY p3.`Employee Number`, p3.comp_effective_date
                ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
              ) chosen ON chosen.`Employee Number` = c4.`Employee Number` AND chosen.comp_effective_date = c4.comp_effective_date
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) mtit ON mtit.`Employee Number` = c4.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
              LEFT JOIN (
                SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
                FROM (
                  SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
                  FROM `namely_comp_data_history_w_notes`
                ) p
                JOIN (
                  SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
                  FROM `namely_title_history_data_aq`
                  WHERE `Title` IS NOT NULL
                ) th ON th.`Employee Number` = p.`Employee Number`
                WHERE th.title_change_date <= p.comp_effective_date
                GROUP BY p.`Employee Number`, p.comp_effective_date
              ) fb ON fb.`Employee Number` = c4.`Employee Number` AND fb.comp_effective_date = c4.comp_effective_date
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) fbtit ON fbtit.`Employee Number` = c4.`Employee Number` AND fbtit.title_change_date = fb.fb_date
              WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c4.`Job Title`))) = 'CREATIVE DIRECTOR'
                AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c4.`Job Title`))) NOT LIKE '%FREELANCE%'
                AND TRIM(c4.`Department`) = 'Design'
                AND UPPER(TRIM(c4.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(c4.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND c4.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND c4.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            ) mn2
          )
        ) / 5000) * 5000
      )
      ELSE r.salary_usd
    END
  , 2) AS `Salary USD`,
  cnt.total_rows AS `Num Records`
FROM (
  SELECT 1 AS step_order, 'Step 1: lowest range' AS step_label, 0.00 AS pct
  UNION ALL
  SELECT 2 AS step_order, 'Step 2: ~50th percentile' AS step_label, 0.50 AS pct
  UNION ALL
  SELECT 3 AS step_order, 'Step 3: ~90th percentile' AS step_label, 0.90 AS pct
) AS sr
CROSS JOIN (
  SELECT COUNT(*) AS total_rows
  FROM (
    SELECT 1
    FROM (
      SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
      FROM `namely_comp_data_history_w_notes` t1
    ) AS c
    LEFT JOIN (
      SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
      FROM (
        SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
        FROM `namely_comp_data_history_w_notes`
      ) AS p
      LEFT JOIN (
        SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) p2
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) th2 ON th2.`Employee Number` = p2.`Employee Number`
        WHERE th2.title_change_date <= p2.comp_effective_date
          AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
        GROUP BY p2.`Employee Number`, p2.comp_effective_date
      ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
      LEFT JOIN (
        SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) p3
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) th3 ON th3.`Employee Number` = p3.`Employee Number`
        WHERE th3.title_change_date >= p3.comp_effective_date
          AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
        GROUP BY p3.`Employee Number`, p3.comp_effective_date
      ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
    ) AS chosen ON chosen.`Employee Number` = c.`Employee Number` AND chosen.comp_effective_date = c.comp_effective_date
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS mtit ON mtit.`Employee Number` = c.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
    LEFT JOIN (
      SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
      FROM (
        SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
        FROM `namely_comp_data_history_w_notes`
      ) AS p
      JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS th ON th.`Employee Number` = p.`Employee Number`
      WHERE th.title_change_date <= p.comp_effective_date
      GROUP BY p.`Employee Number`, p.comp_effective_date
    ) AS fb ON fb.`Employee Number` = c.`Employee Number` AND fb.comp_effective_date = c.comp_effective_date
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number` AND fbtit.title_change_date = fb.fb_date
    WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'CREATIVE DIRECTOR'
      AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
      AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
      AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
      AND c.`Salary` IS NOT NULL
      AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
      AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
  ) AS base_for_count
) AS cnt
LEFT JOIN (
  SELECT ranked.rn, ranked.salary_usd
  FROM (
    SELECT base.salary_usd, @rn_cd := @rn_cd + 1 AS rn
    FROM (
      SELECT CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
             c.comp_effective_date AS comp_effective_date,
             c.`Employee Number` AS employee_number
      FROM (
        SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
        FROM `namely_comp_data_history_w_notes` t1
      ) AS c
      LEFT JOIN (
        SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) AS p
        LEFT JOIN (
          SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
          FROM (
            SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
            FROM `namely_comp_data_history_w_notes`
          ) p2
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) th2 ON th2.`Employee Number` = p2.`Employee Number`
          WHERE th2.title_change_date <= p2.comp_effective_date
            AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
          GROUP BY p2.`Employee Number`, p2.comp_effective_date
        ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
        LEFT JOIN (
          SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
          FROM (
            SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
            FROM `namely_comp_data_history_w_notes`
          ) p3
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) th3 ON th3.`Employee Number` = p3.`Employee Number`
          WHERE th3.title_change_date >= p3.comp_effective_date
            AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
          GROUP BY p3.`Employee Number`, p3.comp_effective_date
        ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
      ) AS chosen ON chosen.`Employee Number` = c.`Employee Number` AND chosen.comp_effective_date = c.comp_effective_date
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS mtit ON mtit.`Employee Number` = c.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
      LEFT JOIN (
        SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) AS p
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) AS th ON th.`Employee Number` = p.`Employee Number`
        WHERE th.title_change_date <= p.comp_effective_date
        GROUP BY p.`Employee Number`, p.comp_effective_date
      ) AS fb ON fb.`Employee Number` = c.`Employee Number` AND fb.comp_effective_date = c.comp_effective_date
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number` AND fbtit.title_change_date = fb.fb_date
      WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'CREATIVE DIRECTOR'
        AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
    ) AS base
    CROSS JOIN (SELECT @rn_cd := 0) AS vars
    ORDER BY base.salary_usd ASC, base.comp_effective_date ASC, base.employee_number ASC
  ) AS ranked
) AS r
ON r.rn = CASE
  WHEN sr.step_order = 1 THEN 1
  WHEN sr.step_order = 2 THEN GREATEST(1, CEIL(cnt.total_rows * 0.50))
  WHEN sr.step_order = 3 THEN GREATEST(1, CEIL(cnt.total_rows * 0.90))
END
)
UNION ALL
(
SELECT
  'Strategy Director' AS `Role`,
  'Strategy' AS `Department`,
  sr.step_order AS `Step Order`,
  sr.step_label AS `Step`,
  ROUND(CASE WHEN sr.step_order = 2 THEN FLOOR(COALESCE(s2.second_min_usd, r.salary_usd) / 5000) * 5000 ELSE r.salary_usd END, 2) AS `Salary USD`,
  cnt.total_rows AS `Num Records`
FROM (
  SELECT 1 AS step_order, 'Step 1: lowest range' AS step_label, 0.00 AS pct
  UNION ALL
  SELECT 2 AS step_order, 'Step 2: ~50th percentile' AS step_label, 0.50 AS pct
  UNION ALL
  SELECT 3 AS step_order, 'Step 3: ~90th percentile' AS step_label, 0.90 AS pct
) AS sr
CROSS JOIN (
  SELECT COUNT(*) AS total_rows
  FROM (
    SELECT 1
    FROM (
      SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
      FROM `namely_comp_data_history_w_notes` t1
    ) AS c
    LEFT JOIN (
      SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
      FROM (
        SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
        FROM `namely_comp_data_history_w_notes`
      ) AS p
      LEFT JOIN (
        SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) p2
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) th2 ON th2.`Employee Number` = p2.`Employee Number`
        WHERE th2.title_change_date <= p2.comp_effective_date
          AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
        GROUP BY p2.`Employee Number`, p2.comp_effective_date
      ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
      LEFT JOIN (
        SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) p3
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) th3 ON th3.`Employee Number` = p3.`Employee Number`
        WHERE th3.title_change_date >= p3.comp_effective_date
          AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
        GROUP BY p3.`Employee Number`, p3.comp_effective_date
      ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
    ) AS chosen ON chosen.`Employee Number` = c.`Employee Number` AND chosen.comp_effective_date = c.comp_effective_date
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS mtit ON mtit.`Employee Number` = c.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
    LEFT JOIN (
      SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
      FROM (
        SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
        FROM `namely_comp_data_history_w_notes`
      ) AS p
      JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS th ON th.`Employee Number` = p.`Employee Number`
      WHERE th.title_change_date <= p.comp_effective_date
      GROUP BY p.`Employee Number`, p.comp_effective_date
    ) AS fb ON fb.`Employee Number` = c.`Employee Number` AND fb.comp_effective_date = c.comp_effective_date
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number` AND fbtit.title_change_date = fb.fb_date
    WHERE TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)) LIKE 'Strategy Director%'
      AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
      AND TRIM(c.`Department`) = 'Strategy'
      AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
      AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
      AND c.`Salary` IS NOT NULL
      AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) >= 100000
      AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
  ) AS base_for_count
) AS cnt
CROSS JOIN (
  SELECT MIN(rb.salary_usd) AS second_min_usd
  FROM (
    SELECT DISTINCT CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
    FROM (
      SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
      FROM `namely_comp_data_history_w_notes` t1
    ) AS c
    LEFT JOIN (
      SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
      FROM (
        SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
        FROM `namely_comp_data_history_w_notes`
      ) AS p
      LEFT JOIN (
        SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) p2
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) th2 ON th2.`Employee Number` = p2.`Employee Number`
        WHERE th2.title_change_date <= p2.comp_effective_date
          AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
        GROUP BY p2.`Employee Number`, p2.comp_effective_date
      ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
      LEFT JOIN (
        SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) p3
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) th3 ON th3.`Employee Number` = p3.`Employee Number`
        WHERE th3.title_change_date >= p3.comp_effective_date
          AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
        GROUP BY p3.`Employee Number`, p3.comp_effective_date
      ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
    ) AS chosen ON chosen.`Employee Number` = c.`Employee Number` AND chosen.comp_effective_date = c.comp_effective_date
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS mtit ON mtit.`Employee Number` = c.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
    LEFT JOIN (
      SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
      FROM (
        SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
        FROM `namely_comp_data_history_w_notes`
      ) AS p
      JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS th ON th.`Employee Number` = p.`Employee Number`
      WHERE th.title_change_date <= p.comp_effective_date
      GROUP BY p.`Employee Number`, p.comp_effective_date
    ) AS fb ON fb.`Employee Number` = c.`Employee Number` AND fb.comp_effective_date = c.comp_effective_date
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number` AND fbtit.title_change_date = fb.fb_date
    WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'STRATEGY DIRECTOR'
      AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
      AND TRIM(c.`Department`) = 'Strategy'
      AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
      AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
      AND c.`Salary` IS NOT NULL
      AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) >= 100000
      AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
  ) AS rb
  WHERE rb.salary_usd > (
    SELECT MIN(rb2.salary_usd)
    FROM (
      SELECT DISTINCT CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
      FROM (
        SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
        FROM `namely_comp_data_history_w_notes` t1
      ) AS c2
      LEFT JOIN (
        SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) AS p
        LEFT JOIN (
          SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
          FROM (
            SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
            FROM `namely_comp_data_history_w_notes`
          ) p2
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) th2 ON th2.`Employee Number` = p2.`Employee Number`
          WHERE th2.title_change_date <= p2.comp_effective_date
            AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
          GROUP BY p2.`Employee Number`, p2.comp_effective_date
        ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
        LEFT JOIN (
          SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
          FROM (
            SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
            FROM `namely_comp_data_history_w_notes`
          ) p3
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) th3 ON th3.`Employee Number` = p3.`Employee Number`
          WHERE th3.title_change_date >= p3.comp_effective_date
            AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
          GROUP BY p3.`Employee Number`, p3.comp_effective_date
        ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
      ) AS chosen ON chosen.`Employee Number` = c2.`Employee Number` AND chosen.comp_effective_date = c2.comp_effective_date
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS mtit ON mtit.`Employee Number` = c2.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
      LEFT JOIN (
        SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) AS p
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) AS th ON th.`Employee Number` = p.`Employee Number`
        WHERE th.title_change_date <= p.comp_effective_date
        GROUP BY p.`Employee Number`, p.comp_effective_date
      ) AS fb ON fb.`Employee Number` = c2.`Employee Number` AND fb.comp_effective_date = c2.comp_effective_date
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS fbtit ON fbtit.`Employee Number` = c2.`Employee Number` AND fbtit.title_change_date = fb.fb_date
      WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c2.`Job Title`))) = 'STRATEGY DIRECTOR'
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c2.`Job Title`))) NOT LIKE '%FREELANCE%'
        AND TRIM(c2.`Department`) = 'Strategy'
        AND UPPER(TRIM(c2.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c2.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) >= 100000
        AND c2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
    ) AS rb2
  )
) AS s2
LEFT JOIN (
  SELECT ranked.rn, ranked.salary_usd
  FROM (
    SELECT base.salary_usd, @rn_sd := @rn_sd + 1 AS rn
    FROM (
      SELECT CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
             c.comp_effective_date AS comp_effective_date,
             c.`Employee Number` AS employee_number
      FROM (
        SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
        FROM `namely_comp_data_history_w_notes` t1
      ) AS c
      LEFT JOIN (
        SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) AS p
        LEFT JOIN (
          SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
          FROM (
            SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
            FROM `namely_comp_data_history_w_notes`
          ) p2
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) th2 ON th2.`Employee Number` = p2.`Employee Number`
          WHERE th2.title_change_date <= p2.comp_effective_date
            AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
          GROUP BY p2.`Employee Number`, p2.comp_effective_date
        ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
        LEFT JOIN (
          SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
          FROM (
            SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
            FROM `namely_comp_data_history_w_notes`
          ) p3
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) th3 ON th3.`Employee Number` = p3.`Employee Number`
          WHERE th3.title_change_date >= p3.comp_effective_date
            AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
          GROUP BY p3.`Employee Number`, p3.comp_effective_date
        ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
      ) AS chosen ON chosen.`Employee Number` = c.`Employee Number` AND chosen.comp_effective_date = c.comp_effective_date
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS mtit ON mtit.`Employee Number` = c.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
      LEFT JOIN (
        SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) AS p
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) AS th ON th.`Employee Number` = p.`Employee Number`
        WHERE th.title_change_date <= p.comp_effective_date
        GROUP BY p.`Employee Number`, p.comp_effective_date
      ) AS fb ON fb.`Employee Number` = c.`Employee Number` AND fb.comp_effective_date = c.comp_effective_date
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number` AND fbtit.title_change_date = fb.fb_date
      WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'STRATEGY DIRECTOR'
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
        AND TRIM(c.`Department`) = 'Strategy'
        AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) >= 100000
        AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
    ) AS base
    CROSS JOIN (SELECT @rn_sd := 0) AS vars
    ORDER BY base.salary_usd ASC, base.comp_effective_date ASC, base.employee_number ASC
  ) AS ranked
) AS r
ON r.rn = CASE
  WHEN sr.step_order = 1 THEN 1
  WHEN sr.step_order = 2 THEN GREATEST(1, CEIL(cnt.total_rows * 0.50))
  WHEN sr.step_order = 3 THEN GREATEST(1, CEIL(cnt.total_rows * 0.90))
END
)
UNION ALL
(
SELECT
  'Program Director' AS `Role`,
  'Program Management' AS `Department`,
  sr.step_order AS `Step Order`,
  sr.step_label AS `Step`,
  ROUND(CASE WHEN sr.step_order = 2 THEN FLOOR(COALESCE(s2_pd.second_min_usd, r.salary_usd) / 5000) * 5000 ELSE r.salary_usd END, 2) AS `Salary USD`,
  cnt.total_rows AS `Num Records`
FROM (
  SELECT 1 AS step_order, 'Step 1: lowest range' AS step_label, 0.00 AS pct
  UNION ALL
  SELECT 2 AS step_order, 'Step 2: ~50th percentile' AS step_label, 0.50 AS pct
  UNION ALL
  SELECT 3 AS step_order, 'Step 3: ~90th percentile' AS step_label, 0.90 AS pct
) AS sr
CROSS JOIN (
  SELECT COUNT(*) AS total_rows
  FROM (
    SELECT 1
    FROM (
      SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
      FROM `namely_comp_data_history_w_notes` t1
    ) AS c
    LEFT JOIN (
      SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
      FROM (
        SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
        FROM `namely_comp_data_history_w_notes`
      ) AS p
      LEFT JOIN (
        SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) p2
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) th2 ON th2.`Employee Number` = p2.`Employee Number`
        WHERE th2.title_change_date <= p2.comp_effective_date
          AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
        GROUP BY p2.`Employee Number`, p2.comp_effective_date
      ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
      LEFT JOIN (
        SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) p3
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) th3 ON th3.`Employee Number` = p3.`Employee Number`
        WHERE th3.title_change_date >= p3.comp_effective_date
          AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
        GROUP BY p3.`Employee Number`, p3.comp_effective_date
      ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
    ) AS chosen ON chosen.`Employee Number` = c.`Employee Number` AND chosen.comp_effective_date = c.comp_effective_date
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS mtit ON mtit.`Employee Number` = c.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
    LEFT JOIN (
      SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
      FROM (
        SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
        FROM `namely_comp_data_history_w_notes`
      ) AS p
      JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS th ON th.`Employee Number` = p.`Employee Number`
      WHERE th.title_change_date <= p.comp_effective_date
      GROUP BY p.`Employee Number`, p.comp_effective_date
    ) AS fb ON fb.`Employee Number` = c.`Employee Number` AND fb.comp_effective_date = c.comp_effective_date
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number` AND fbtit.title_change_date = fb.fb_date
    WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PROGRAM DIRECTOR'
      AND TRIM(c.`Department`) = 'Program Management'
      AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
      AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
      AND c.`Salary` IS NOT NULL
      AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
      AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
  ) AS base_for_count
) AS cnt
CROSS JOIN (
  SELECT MIN(rb.salary_usd) AS second_min_usd
  FROM (
    SELECT DISTINCT CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
    FROM (
      SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
      FROM `namely_comp_data_history_w_notes` t1
    ) AS c
    LEFT JOIN (
      SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
      FROM (
        SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
        FROM `namely_comp_data_history_w_notes`
      ) AS p
      LEFT JOIN (
        SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) p2
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) th2 ON th2.`Employee Number` = p2.`Employee Number`
        WHERE th2.title_change_date <= p2.comp_effective_date
          AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
        GROUP BY p2.`Employee Number`, p2.comp_effective_date
      ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
      LEFT JOIN (
        SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) p3
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) th3 ON th3.`Employee Number` = p3.`Employee Number`
        WHERE th3.title_change_date >= p3.comp_effective_date
          AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
        GROUP BY p3.`Employee Number`, p3.comp_effective_date
      ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
    ) As chosen ON chosen.`Employee Number` = c.`Employee Number` AND chosen.comp_effective_date = c.comp_effective_date
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS mtit ON mtit.`Employee Number` = c.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
    LEFT JOIN (
      SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
      FROM (
        SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
        FROM `namely_comp_data_history_w_notes`
      ) AS p
      JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS th ON th.`Employee Number` = p.`Employee Number`
      WHERE th.title_change_date <= p.comp_effective_date
      GROUP BY p.`Employee Number`, p.comp_effective_date
    ) AS fb ON fb.`Employee Number` = c.`Employee Number` AND fb.comp_effective_date = c.comp_effective_date
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number` AND fbtit.title_change_date = fb.fb_date
    WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PROGRAM DIRECTOR'
      AND TRIM(c.`Department`) = 'Program Management'
      AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
      AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
      AND c.`Salary` IS NOT NULL
      AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
      AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
  ) AS rb
  WHERE rb.salary_usd > (
    SELECT MIN(rb2.salary_usd)
    FROM (
      SELECT DISTINCT CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
      FROM (
        SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
        FROM `namely_comp_data_history_w_notes` t1
      ) AS c2
      LEFT JOIN (
        SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) AS p
        LEFT JOIN (
          SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
          FROM (
            SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
            FROM `namely_comp_data_history_w_notes`
          ) p2
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) th2 ON th2.`Employee Number` = p2.`Employee Number`
          WHERE th2.title_change_date <= p2.comp_effective_date
            AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
          GROUP BY p2.`Employee Number`, p2.comp_effective_date
        ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
        LEFT JOIN (
          SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
          FROM (
            SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
            FROM `namely_comp_data_history_w_notes`
          ) p3
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) th3 ON th3.`Employee Number` = p3.`Employee Number`
          WHERE th3.title_change_date >= p3.comp_effective_date
            AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
          GROUP BY p3.`Employee Number`, p3.comp_effective_date
        ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
      ) AS chosen ON chosen.`Employee Number` = c2.`Employee Number` AND chosen.comp_effective_date = c2.comp_effective_date
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS mtit ON mtit.`Employee Number` = c2.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
      LEFT JOIN (
        SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) AS p
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) AS th ON th.`Employee Number` = p.`Employee Number`
        WHERE th.title_change_date <= p.comp_effective_date
        GROUP BY p.`Employee Number`, p.comp_effective_date
      ) AS fb ON fb.`Employee Number` = c2.`Employee Number` AND fb.comp_effective_date = c2.comp_effective_date
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS fbtit ON fbtit.`Employee Number` = c2.`Employee Number` AND fbtit.title_change_date = fb.fb_date
      WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c2.`Job Title`))) = 'PROGRAM DIRECTOR'
        AND TRIM(c2.`Department`) = 'Program Management'
        AND UPPER(TRIM(c2.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c2.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
    ) AS rb2
  )
) AS s2_pd
LEFT JOIN (
  SELECT ranked.rn, ranked.salary_usd
  FROM (
    SELECT base.salary_usd, @rn_pd := @rn_pd + 1 AS rn
    FROM (
      SELECT CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
             c.comp_effective_date AS comp_effective_date,
             c.`Employee Number` AS employee_number
      FROM (
        SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
        FROM `namely_comp_data_history_w_notes` t1
      ) AS c
      LEFT JOIN (
        SELECT p.`Employee Number`, p.comp_effective_date, COALESCE(ob.match_date, af.match_date) AS chosen_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) AS p
        LEFT JOIN (
          SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
          FROM (
            SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
            FROM `namely_comp_data_history_w_notes`
          ) p2
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) th2 ON th2.`Employee Number` = p2.`Employee Number`
          WHERE th2.title_change_date <= p2.comp_effective_date
            AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
          GROUP BY p2.`Employee Number`, p2.comp_effective_date
        ) ob ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
        LEFT JOIN (
          SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
          FROM (
            SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date, `Employee Number`
            FROM `namely_comp_data_history_w_notes`
          ) p3
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) th3 ON th3.`Employee Number` = p3.`Employee Number`
          WHERE th3.title_change_date >= p3.comp_effective_date
            AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
          GROUP BY p3.`Employee Number`, p3.comp_effective_date
        ) af ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
      ) AS chosen ON chosen.`Employee Number` = c.`Employee Number` AND chosen.comp_effective_date = c.comp_effective_date
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS mtit ON mtit.`Employee Number` = c.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
      LEFT JOIN (
        SELECT p.`Employee Number`, p.comp_effective_date, MAX(th.title_change_date) AS fb_date
        FROM (
          SELECT DISTINCT COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective date, `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) AS p
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) AS th ON th.`Employee Number` = p.`Employee Number`
        WHERE th.title_change_date <= p.comp_effective_date
        GROUP BY p.`Employee Number`, p.comp_effective_date
      ) AS fb ON fb.`Employee Number` = c.`Employee Number` AND fb.comp_effective_date = c.comp_effective_date
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number` AND fbtit.title_change_date = fb.fb_date
      WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PROGRAM DIRECTOR'
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
        AND TRIM(c.`Department`) = 'Program Management'
        AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
    ) AS base
    CROSS JOIN (SELECT @rn_pd := 0) AS vars
    ORDER BY base.salary_usd ASC, base.comp_effective_date ASC, base.employee_number ASC
  ) AS ranked
) AS r
ON r.rn = CASE
  WHEN sr.step_order = 1 THEN 1
  WHEN sr.step_order = 2 THEN GREATEST(1, CEIL(cnt.total_rows * 0.50))
  WHEN sr.step_order = 3 THEN GREATEST(1, CEIL(cnt.total_rows * 0.90))
END
)
ORDER BY `Role`, `Step Order`;
```

### Additional notes for future maintainers
- If a role’s dataset is small (e.g., <10 rows) or top-heavy, consider Step 2 rounding to keep bands visually distinct.
- If you add more roles, copy an existing block and ensure:
  - Title normalization is used consistently in filters
  - Department filters match expectations
  - Any salary floors are applied consistently across count/rank/second-min blocks
  - Freelance exclusion is applied in all relevant subqueries
- We also updated the single-role Creative Director SQL to exclude "Freelance" and to compute Step 2 from the next distinct salary above the minimum to avoid Step 1/2 equality.

### Lessons learned
- Keep filters identical between the counting (N) and the ranking/selection subqueries, or you’ll compute percentiles from the wrong set.
- For small-N distributions, pure percentile ranks may converge; a second-min guard plus band rounding is a pragmatic fix.
- Always normalize title text from the chosen date before filtering, and retain fallbacks to handle messy histories.


