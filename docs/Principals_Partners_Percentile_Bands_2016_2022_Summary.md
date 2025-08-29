## Principals & Partners: Percentile-Based Compensation Bands (2016-01-01 to 2022-01-31)

### What we built
- **Goal**: Produce percentile-based compensation bands for roles within `Department = Principals` and `Department = Partners` during 2016-01-01 through 2022-01-31.
- **Output**: For each Department–Role, compute Min, P10, P25, P50, P75, P90. Also derive Steps aligned with prior methodology:
  - **Step 1**: Min (lowest observed salary)
  - **Step 2**: ~50th percentile with a “second-min” guard if the median equals the minimum
  - **Step 3**: ~90th percentile
  - All salaries rounded to the nearest $5,000.

### Inputs
- `namely_comp_data_history_w_notes` (compensation events)
- `namely_title_history_data_aq` (title history with effective dates)

### Title → comp matching (priority)
For each compensation row (per `Employee Number` + `comp_effective_date = COALESCE(Salary Start Date, Start Date)`), resolve the most relevant title using:
1) On/before within 15 days (latest)
2) After within 15 days (earliest)
3) Latest prior title (no 15-day limit)
4) Fallback to comp row's original `Job Title`

All joins are left joins so comp rows are preserved.

### Business rules and filters
- Window: `comp_effective_date BETWEEN '2016-01-01' AND '2022-01-31'`.
- Department in `Principals`, `Partners`.
- Exclude titles containing "Freelance" (check against normalized title `COALESCE(mtit.Title, fbtit.Title, c.Job Title)`).
- Employee Type = `Staff Full Time`.
- Salary type in `YEARLY`, `SALARY`, `SALARIED`, `ANNUAL`.
- Salary > 0 and non-null.
- Organizational note: effective 2021-01-01, titles shifted (Principal → Partner; Managing Principal → Managing Partner) without compensation changes. Promotions into Principal after this date used different comp bands. This query is strictly descriptive (observed salaries).

### Role mapping
- Partners
  - Partner/SVP: `Partner`, `Partner, User Experience`, `Partner & Head of Strategy Team`
  - Senior Partner: `Senior Partner`
- Principals
  - Principal/VP: `Principal`, `Principal & Head of Design Team`, `Principal, Design`, `Principal, Head of Strategy/VP, People Strategy and Consulting Enablement`, `Principal, Program Management`, `Principal, Strategy`, `VP, Business Operations & Head of Program Management Team`
  - Associate Principal: `Associate Principal`

### Methodology
- Compute group counts per Department–Role.
- Rank salaries within each group using MySQL user variables (MySQL 5.7-compatible; no CTEs/windows).
- Select value at `CEIL(p * N)` for each requested percentile `p`.
- Derive steps:
  - Step 1: group minimum
  - Step 2: median; if equal to Step 1, use the next distinct salary above the minimum (second-min) as a guard
  - Step 3: ~90th percentile
- Round displayed values to nearest $5,000.

### What the Percentile column means
- **Min**: Absolute minimum observed salary in the filtered group.
- **P10/P25/P50/P75/P90**: Salary at the 10th/25th/50th/75th/90th percentile within the Department–Role distribution. Example: P50 is the median; P90 exceeds ~90% of observations.
- **Step** is populated for Min/P50/P90 aligned to Step 1/2/3; other percentile rows have `NULL` Step.

### Final SQL
```sql
/* ----------------------------------------------------------------------------
   Principals & Partners: Percentile-based Compensation Bands
   Window: 2016-01-01 through 2022-01-31 (inclusive)

   Inputs:
     - namely_comp_data_history_w_notes        (comp history)
     - namely_title_history_data_aq            (title history with change dates)

   Title matching (priority):
     1) On/before within 15 days (latest)
     2) After within 15 days (earliest)
     3) Fallback to latest prior title (no 15-day limit)
     4) Fallback to comp row's original Job Title

   Filters:
     - comp_effective_date in [2016-01-01, 2022-01-31]
     - Department IN ('Principals','Partners')
     - Exclude titles containing 'Freelance'
     - Annual/salaried types only; Salary > 0
     - Staff Full Time only

   Roles included:
     - Department = Partners
       • Partner/SVP group: 'PARTNER', 'PARTNER, USER EXPERIENCE', 'PARTNER & HEAD OF STRATEGY TEAM'
       • Senior Partner    : 'SENIOR PARTNER'
     - Department = Principals
       • Principal/VP group: 'PRINCIPAL','PRINCIPAL & HEAD OF DESIGN TEAM','PRINCIPAL, DESIGN',
                              'PRINCIPAL, HEAD OF STRATEGY/VP, PEOPLE STRATEGY AND CONSULTING ENABLEMENT',
                              'PRINCIPAL, PROGRAM MANAGEMENT','PRINCIPAL, STRATEGY',
                              'VP, BUSINESS OPERATIONS & HEAD OF PROGRAM MANAGEMENT TEAM'
       • Associate Principal: 'ASSOCIATE PRINCIPAL'

   Percentiles computed (per Department x Role Group): P10, P25, P50, P75, P90

   MySQL 5.7-compatible: no CTEs, user variables for ranking per group
---------------------------------------------------------------------------- */

/* ---------- Base comp rows with comp_effective_date ---------- */
SELECT
  outp.`Department`,
  outp.`Role`,
  outp.`Percentile`,
  outp.`Step`,
  ROUND(outp.`Salary USD`, 2)      AS `Salary USD`,
  outp.`Num Records`               AS `Num Records`
FROM (
  /* Build percentile outputs by joining group counts with ranked rows */
  SELECT
    cnt.`Department` AS `Department`,
    cnt.`Role`       AS `Role`,
    pct_tbl.pct_label AS `Percentile`,
    /* Step mapping per prior methodology */
    CASE
      WHEN pct_tbl.pct_label = 'Min' THEN 'Step 1'
      WHEN pct_tbl.pct_label = 'P50' THEN 'Step 2'
      WHEN pct_tbl.pct_label = 'P90' THEN 'Step 3'
      ELSE NULL
    END AS `Step`,
    /* Salary selection with rounding to nearest $5k */
    CASE
      WHEN pct_tbl.pct_label = 'Min' THEN steps.step1_usd
      WHEN pct_tbl.pct_label = 'P50' THEN steps.step2_usd
      WHEN pct_tbl.pct_label = 'P90' THEN steps.step3_usd
      ELSE ROUND(rnk.salary_usd / 5000) * 5000
    END AS `Salary USD`,
    cnt.n             AS `Num Records`
  FROM (
    /* Counts per Department x Role (filtered base) */
    SELECT dept AS Department, role_group AS Role, COUNT(*) AS n
    FROM (
      SELECT
        TRIM(c.`Department`) AS dept,
        CASE
          WHEN UPPER(TRIM(c.`Department`)) = 'PARTNERS' THEN (
            CASE
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'SENIOR PARTNER' THEN 'Senior Partner'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                'PARTNER',
                'PARTNER, USER EXPERIENCE',
                'PARTNER & HEAD OF STRATEGY TEAM'
              ) THEN 'Partner/SVP'
              ELSE NULL
            END
          )
          WHEN UPPER(TRIM(c.`Department`)) = 'PRINCIPALS' THEN (
            CASE
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'ASSOCIATE PRINCIPAL' THEN 'Associate Principal'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                'PRINCIPAL',
                'PRINCIPAL & HEAD OF DESIGN TEAM',
                'PRINCIPAL, DESIGN',
                'PRINCIPAL, HEAD OF STRATEGY/VP, PEOPLE STRATEGY AND CONSULTING ENABLEMENT',
                'PRINCIPAL, PROGRAM MANAGEMENT',
                'PRINCIPAL, STRATEGY',
                'VP, BUSINESS OPERATIONS & HEAD OF PROGRAM MANAGEMENT TEAM'
              ) THEN 'Principal/VP'
              ELSE NULL
            END
          )
          ELSE NULL
        END AS role_group
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
      WHERE UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
        AND UPPER(TRIM(c.`Department`)) IN ('PRINCIPALS','PARTNERS')
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
    ) AS filt
    WHERE filt.role_group IS NOT NULL
    GROUP BY dept, role_group
  ) AS cnt
  /* Percentile labels */
  CROSS JOIN (
    SELECT 0.00 AS pct, 'Min' AS pct_label, 0 AS ord
    UNION ALL SELECT 0.10 AS pct, 'P10' AS pct_label, 1 AS ord
    UNION ALL SELECT 0.25 AS pct, 'P25' AS pct_label, 2 AS ord
    UNION ALL SELECT 0.50 AS pct, 'P50' AS pct_label, 3 AS ord
    UNION ALL SELECT 0.75 AS pct, 'P75' AS pct_label, 4 AS ord
    UNION ALL SELECT 0.90 AS pct, 'P90' AS pct_label, 5 AS ord
  ) AS pct_tbl
  /* Ranked salaries within each Department x Role group */
  JOIN (
    SELECT ranked.Department, ranked.Role, ranked.rn, ranked.salary_usd
    FROM (
      SELECT
        ord.Department,
        ord.Role,
        ord.salary_usd,
        @rn := IF(@grp = ord.grpkey, @rn + 1, 1) AS rn,
        @grp := ord.grpkey AS _g
      FROM (
        SELECT
          b.dept AS Department,
          b.role_group AS Role,
          b.salary_usd,
          CONCAT(b.dept, '|', b.role_group) AS grpkey,
          b.comp_effective_date,
          b.`Employee Number`
        FROM (
          SELECT
            TRIM(c.`Department`) AS dept,
            CASE
              WHEN UPPER(TRIM(c.`Department`)) = 'PARTNERS' THEN (
                CASE
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'SENIOR PARTNER' THEN 'Senior Partner'
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                    'PARTNER',
                    'PARTNER, USER EXPERIENCE',
                    'PARTNER & HEAD OF STRATEGY TEAM'
                  ) THEN 'Partner/SVP'
                  ELSE NULL
                END
              )
              WHEN UPPER(TRIM(c.`Department`)) = 'PRINCIPALS' THEN (
                CASE
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'ASSOCIATE PRINCIPAL' THEN 'Associate Principal'
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                    'PRINCIPAL',
                    'PRINCIPAL & HEAD OF DESIGN TEAM',
                    'PRINCIPAL, DESIGN',
                    'PRINCIPAL, HEAD OF STRATEGY/VP, PEOPLE STRATEGY AND CONSULTING ENABLEMENT',
                    'PRINCIPAL, PROGRAM MANAGEMENT',
                    'PRINCIPAL, STRATEGY',
                    'VP, BUSINESS OPERATIONS & HEAD OF PROGRAM MANAGEMENT TEAM'
                  ) THEN 'Principal/VP'
                  ELSE NULL
                END
              )
              ELSE NULL
            END AS role_group,
            CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
            c.comp_effective_date,
            c.`Employee Number`
          FROM (
            SELECT
              t1.*,
              COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
            FROM `namely_comp_data_history_w_notes` t1
          ) AS c
          LEFT JOIN (
            SELECT
              p.`Employee Number`, p.comp_effective_date,
              COALESCE(ob.match_date, af.match_date) AS chosen_date
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
          WHERE UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
            AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
            AND c.`Salary` IS NOT NULL
            AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
            AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            AND UPPER(TRIM(c.`Department`)) IN ('PRINCIPALS','PARTNERS')
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
        ) AS b
        WHERE b.role_group IS NOT NULL
        ORDER BY b.dept, b.role_group, b.salary_usd ASC, b.comp_effective_date ASC, b.`Employee Number` ASC
      ) AS ord
      CROSS JOIN (SELECT @rn := 0, @grp := '') AS vars
    ) AS ranked
  ) AS rnk
    ON rnk.Department = cnt.Department AND rnk.Role = cnt.Role
   AND rnk.rn = GREATEST(1, CEIL(cnt.n * pct_tbl.pct))
  /* Step values per Department x Role with guard for Step 2 */
  LEFT JOIN (
    SELECT
      s1.Department,
      s1.Role,
      ROUND(s1.min_usd / 5000) * 5000 AS step1_usd,
      ROUND(
        COALESCE(
          CASE
            WHEN med.med_usd > s1.min_usd THEN med.med_usd
            WHEN sm.second_min_usd IS NOT NULL THEN sm.second_min_usd
            ELSE s1.min_usd
          END,
          s1.min_usd
        ) / 5000
      ) * 5000 AS step2_usd,
      ROUND(p90.p90_usd / 5000) * 5000 AS step3_usd
    FROM (
      /* Min per group */
      SELECT Department, Role, MIN(salary_usd) AS min_usd
      FROM (
        SELECT
          TRIM(c.`Department`) AS Department,
          CASE
            WHEN UPPER(TRIM(c.`Department`)) = 'PARTNERS' THEN (
              CASE
                WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'SENIOR PARTNER' THEN 'Senior Partner'
                WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                  'PARTNER',
                  'PARTNER, USER EXPERIENCE',
                  'PARTNER & HEAD OF STRATEGY TEAM'
                ) THEN 'Partner/SVP'
                ELSE NULL
              END
            )
            WHEN UPPER(TRIM(c.`Department`)) = 'PRINCIPALS' THEN (
              CASE
                WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'ASSOCIATE PRINCIPAL' THEN 'Associate Principal'
                WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                  'PRINCIPAL',
                  'PRINCIPAL & HEAD OF DESIGN TEAM',
                  'PRINCIPAL, DESIGN',
                  'PRINCIPAL, HEAD OF STRATEGY/VP, PEOPLE STRATEGY AND CONSULTING ENABLEMENT',
                  'PRINCIPAL, PROGRAM MANAGEMENT',
                  'PRINCIPAL, STRATEGY',
                  'VP, BUSINESS OPERATIONS & HEAD OF PROGRAM MANAGEMENT TEAM'
                ) THEN 'Principal/VP'
                ELSE NULL
              END
            )
            ELSE NULL
          END AS Role,
          CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
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
        WHERE UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
          AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
          AND c.`Salary` IS NOT NULL
          AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
          AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
          AND UPPER(TRIM(c.`Department`)) IN ('PRINCIPALS','PARTNERS')
          AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
      ) AS gb
      WHERE gb.Role IS NOT NULL
      GROUP BY Department, Role
    ) AS s1
    /* Second-min per group */
    LEFT JOIN (
      SELECT g.Department, g.Role, MIN(g.salary_usd) AS second_min_usd
      FROM (
        SELECT
          TRIM(c.`Department`) AS Department,
          CASE
            WHEN UPPER(TRIM(c.`Department`)) = 'PARTNERS' THEN (
              CASE
                WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'SENIOR PARTNER' THEN 'Senior Partner'
                WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                  'PARTNER',
                  'PARTNER, USER EXPERIENCE',
                  'PARTNER & HEAD OF STRATEGY TEAM'
                ) THEN 'Partner/SVP'
                ELSE NULL
              END
            )
            WHEN UPPER(TRIM(c.`Department`)) = 'PRINCIPALS' THEN (
              CASE
                WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'ASSOCIATE PRINCIPAL' THEN 'Associate Principal'
                WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                  'PRINCIPAL',
                  'PRINCIPAL & HEAD OF DESIGN TEAM',
                  'PRINCIPAL, DESIGN',
                  'PRINCIPAL, HEAD OF STRATEGY/VP, PEOPLE STRATEGY AND CONSULTING ENABLEMENT',
                  'PRINCIPAL, PROGRAM MANAGEMENT',
                  'PRINCIPAL, STRATEGY',
                  'VP, BUSINESS OPERATIONS & HEAD OF PROGRAM MANAGEMENT TEAM'
                ) THEN 'Principal/VP'
                ELSE NULL
              END
            )
            ELSE NULL
          END AS Role,
          CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
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
        WHERE UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
          AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
          AND c.`Salary` IS NOT NULL
          AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
          AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
          AND UPPER(TRIM(c.`Department`)) IN ('PRINCIPALS','PARTNERS')
          AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
      ) AS g
      JOIN (
        SELECT Department, Role, MIN(salary_usd) AS min_usd
        FROM (
          SELECT
            TRIM(c.`Department`) AS Department,
            CASE
              WHEN UPPER(TRIM(c.`Department`)) = 'PARTNERS' THEN (
                CASE
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'SENIOR PARTNER' THEN 'Senior Partner'
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                    'PARTNER',
                    'PARTNER, USER EXPERIENCE',
                    'PARTNER & HEAD OF STRATEGY TEAM'
                  ) THEN 'Partner/SVP'
                  ELSE NULL
                END
              )
              WHEN UPPER(TRIM(c.`Department`)) = 'PRINCIPALS' THEN (
                CASE
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'ASSOCIATE PRINCIPAL' THEN 'Associate Principal'
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                    'PRINCIPAL',
                    'PRINCIPAL & HEAD OF DESIGN TEAM',
                    'PRINCIPAL, DESIGN',
                    'PRINCIPAL, HEAD OF STRATEGY/VP, PEOPLE STRATEGY AND CONSULTING ENABLEMENT',
                    'PRINCIPAL, PROGRAM MANAGEMENT',
                    'PRINCIPAL, STRATEGY',
                    'VP, BUSINESS OPERATIONS & HEAD OF PROGRAM MANAGEMENT TEAM'
                  ) THEN 'Principal/VP'
                  ELSE NULL
                END
              )
              ELSE NULL
            END AS Role,
            CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
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
          WHERE UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
            AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
            AND c.`Salary` IS NOT NULL
            AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
            AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            AND UPPER(TRIM(c.`Department`)) IN ('PRINCIPALS','PARTNERS')
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
        ) AS gb2
        WHERE gb2.Role IS NOT NULL
        GROUP BY Department, Role
      ) AS mm
        ON mm.Department = g.Department AND mm.Role = g.Role
      WHERE g.salary_usd > mm.min_usd
      GROUP BY g.Department, g.Role
    ) AS sm ON sm.Department = s1.Department AND sm.Role = s1.Role
    /* Median and P90 picks via ranking */
    LEFT JOIN (
      SELECT ranked.Department, ranked.Role, ranked.salary_usd AS med_usd
      FROM (
        SELECT
          ord.Department,
          ord.Role,
          ord.salary_usd,
          @rn_m := IF(@grp_m = ord.grpkey, @rn_m + 1, 1) AS rn,
          @grp_m := ord.grpkey AS _g
        FROM (
          SELECT
            b.dept AS Department,
            b.role_group AS Role,
            b.salary_usd,
            CONCAT(b.dept, '|', b.role_group) AS grpkey,
            b.comp_effective_date,
            b.`Employee Number`
          FROM (
            SELECT
              TRIM(c.`Department`) AS dept,
              CASE
                WHEN UPPER(TRIM(c.`Department`)) = 'PARTNERS' THEN (
                  CASE
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'SENIOR PARTNER' THEN 'Senior Partner'
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                      'PARTNER',
                      'PARTNER, USER EXPERIENCE',
                      'PARTNER & HEAD OF STRATEGY TEAM'
                    ) THEN 'Partner/SVP'
                    ELSE NULL
                  END
                )
                WHEN UPPER(TRIM(c.`Department`)) = 'PRINCIPALS' THEN (
                  CASE
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'ASSOCIATE PRINCIPAL' THEN 'Associate Principal'
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                      'PRINCIPAL',
                      'PRINCIPAL & HEAD OF DESIGN TEAM',
                      'PRINCIPAL, DESIGN',
                      'PRINCIPAL, HEAD OF STRATEGY/VP, PEOPLE STRATEGY AND CONSULTING ENABLEMENT',
                      'PRINCIPAL, PROGRAM MANAGEMENT',
                      'PRINCIPAL, STRATEGY',
                      'VP, BUSINESS OPERATIONS & HEAD OF PROGRAM MANAGEMENT TEAM'
                    ) THEN 'Principal/VP'
                    ELSE NULL
                  END
                )
                ELSE NULL
              END AS role_group,
              CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
              c.comp_effective_date,
              c.`Employee Number`
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
            WHERE UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
              AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
              AND c.`Salary` IS NOT NULL
              AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
              AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
              AND UPPER(TRIM(c.`Department`)) IN ('PRINCIPALS','PARTNERS')
              AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
          ) AS b
          WHERE b.role_group IS NOT NULL
          ORDER BY b.dept, b.role_group, b.salary_usd ASC, b.comp_effective_date ASC, b.`Employee Number` ASC
        ) AS ord
        CROSS JOIN (SELECT @rn_m := 0, @grp_m := '') AS vars
      ) AS ranked
      JOIN (
        SELECT Department, Role, COUNT(*) AS n
        FROM (
          SELECT
            TRIM(c.`Department`) AS Department,
            CASE
              WHEN UPPER(TRIM(c.`Department`)) = 'PARTNERS' THEN (
                CASE
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'SENIOR PARTNER' THEN 'Senior Partner'
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                    'PARTNER',
                    'PARTNER, USER EXPERIENCE',
                    'PARTNER & HEAD OF STRATEGY TEAM'
                  ) THEN 'Partner/SVP'
                  ELSE NULL
                END
              )
              WHEN UPPER(TRIM(c.`Department`)) = 'PRINCIPALS' THEN (
                CASE
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'ASSOCIATE PRINCIPAL' THEN 'Associate Principal'
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                    'PRINCIPAL',
                    'PRINCIPAL & HEAD OF DESIGN TEAM',
                    'PRINCIPAL, DESIGN',
                    'PRINCIPAL, HEAD OF STRATEGY/VP, PEOPLE STRATEGY AND CONSULTING ENABLEMENT',
                    'PRINCIPAL, PROGRAM MANAGEMENT',
                    'PRINCIPAL, STRATEGY',
                    'VP, BUSINESS OPERATIONS & HEAD OF PROGRAM MANAGEMENT TEAM'
                  ) THEN 'Principal/VP'
                  ELSE NULL
                END
              )
              ELSE NULL
            END AS Role,
            1 AS one
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
          WHERE UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
            AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
            AND c.`Salary` IS NOT NULL
            AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
            AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            AND UPPER(TRIM(c.`Department`)) IN ('PRINCIPALS','PARTNERS')
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
        ) AS cc
        WHERE cc.Role IS NOT NULL
        GROUP BY Department, Role
      ) AS cnt2
        ON cnt2.Department = ranked.Department AND cnt2.Role = ranked.Role
      WHERE ranked.rn = GREATEST(1, CEIL(cnt2.n * 0.50))
    ) AS med ON med.Department = s1.Department AND med.Role = s1.Role
    LEFT JOIN (
      SELECT ranked.Department, ranked.Role, ranked.salary_usd AS p90_usd
      FROM (
        SELECT
          ord.Department,
          ord.Role,
          ord.salary_usd,
          @rn_p := IF(@grp_p = ord.grpkey, @rn_p + 1, 1) AS rn,
          @grp_p := ord.grpkey AS _g
        FROM (
          SELECT
            b.dept AS Department,
            b.role_group AS Role,
            b.salary_usd,
            CONCAT(b.dept, '|', b.role_group) AS grpkey,
            b.comp_effective_date,
            b.`Employee Number`
          FROM (
            SELECT
              TRIM(c.`Department`) AS dept,
              CASE
                WHEN UPPER(TRIM(c.`Department`)) = 'PARTNERS' THEN (
                  CASE
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'SENIOR PARTNER' THEN 'Senior Partner'
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                      'PARTNER',
                      'PARTNER, USER EXPERIENCE',
                      'PARTNER & HEAD OF STRATEGY TEAM'
                    ) THEN 'Partner/SVP'
                    ELSE NULL
                  END
                )
                WHEN UPPER(TRIM(c.`Department`)) = 'PRINCIPALS' THEN (
                  CASE
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'ASSOCIATE PRINCIPAL' THEN 'Associate Principal'
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                      'PRINCIPAL',
                      'PRINCIPAL & HEAD OF DESIGN TEAM',
                      'PRINCIPAL, DESIGN',
                      'PRINCIPAL, HEAD OF STRATEGY/VP, PEOPLE STRATEGY AND CONSULTING ENABLEMENT',
                      'PRINCIPAL, PROGRAM MANAGEMENT',
                      'PRINCIPAL, STRATEGY',
                      'VP, BUSINESS OPERATIONS & HEAD OF PROGRAM MANAGEMENT TEAM'
                    ) THEN 'Principal/VP'
                    ELSE NULL
                  END
                )
                ELSE NULL
              END AS role_group,
              CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
              c.comp_effective_date,
              c.`Employee Number`
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
            WHERE UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
              AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
              AND c.`Salary` IS NOT NULL
              AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
              AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
              AND UPPER(TRIM(c.`Department`)) IN ('PRINCIPALS','PARTNERS')
              AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
          ) AS b
          WHERE b.role_group IS NOT NULL
          ORDER BY b.dept, b.role_group, b.salary_usd ASC, b.comp_effective_date ASC, b.`Employee Number` ASC
        ) AS ord
        CROSS JOIN (SELECT @rn_p := 0, @grp_p := '') AS vars
      ) AS ranked
      JOIN (
        SELECT Department, Role, COUNT(*) AS n
        FROM (
          SELECT
            TRIM(c.`Department`) AS Department,
            CASE
              WHEN UPPER(TRIM(c.`Department`)) = 'PARTNERS' THEN (
                CASE
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'SENIOR PARTNER' THEN 'Senior Partner'
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                    'PARTNER',
                    'PARTNER, USER EXPERIENCE',
                    'PARTNER & HEAD OF STRATEGY TEAM'
                  ) THEN 'Partner/SVP'
                  ELSE NULL
                END
              )
              WHEN UPPER(TRIM(c.`Department`)) = 'PRINCIPALS' THEN (
                CASE
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'ASSOCIATE PRINCIPAL' THEN 'Associate Principal'
                  WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
                    'PRINCIPAL',
                    'PRINCIPAL & HEAD OF DESIGN TEAM',
                    'PRINCIPAL, DESIGN',
                    'PRINCIPAL, HEAD OF STRATEGY/VP, PEOPLE STRATEGY AND CONSULTING ENABLEMENT',
                    'PRINCIPAL, PROGRAM MANAGEMENT',
                    'PRINCIPAL, STRATEGY',
                    'VP, BUSINESS OPERATIONS & HEAD OF PROGRAM MANAGEMENT TEAM'
                  ) THEN 'Principal/VP'
                  ELSE NULL
                END
              )
              ELSE NULL
            END AS Role,
            1 AS one
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
          WHERE UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
            AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
            AND c.`Salary` IS NOT NULL
            AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
            AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            AND UPPER(TRIM(c.`Department`)) IN ('PRINCIPALS','PARTNERS')
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
        ) AS cc2
        WHERE cc2.Role IS NOT NULL
        GROUP BY Department, Role
      ) AS cnt3
        ON cnt3.Department = ranked.Department AND cnt3.Role = ranked.Role
      WHERE ranked.rn = GREATEST(1, CEIL(cnt3.n * 0.90))
    ) AS p90 ON p90.Department = s1.Department AND p90.Role = s1.Role
  ) AS steps ON steps.Department = cnt.Department AND steps.Role = cnt.Role
  ORDER BY cnt.`Department`, cnt.`Role`, pct_tbl.ord
) AS outp;
```

### How to run
1. In Domo MySQL 5.7 DataFlow, add inputs for both tables above.
2. Paste the SQL into a transform and run.
3. Output columns: `Department`, `Role`, `Percentile`, `Step`, `Salary USD` (rounded), `Num Records`.

### What we learned
- Align all filters across counting and ranking subqueries; misalignment distorts percentile picks.
- MySQL 5.7 needs user-variable ranking; ordering must be deterministic (tie-break with date and employee id).
- Median can equal the minimum in small/top-heavy distributions, so a “second-min” guard keeps Step 2 distinct.
- Keep title normalization consistent across all filters and role mapping.

### Future improvements
- Replace repeated base logic with a view or upstream transform to reduce duplication.
- Parameterize date windows, departments, and role lists.
- Move to a warehouse with native window functions for simpler percentile selection and step derivation.


