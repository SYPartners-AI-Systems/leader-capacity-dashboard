## Studio/Production Compensation Bands — Build Summary and Final SQL (2016-01-01 → 2022-01-31)

### What we did
- Built percentile-based compensation bands for the Studio/Production functions using historical comp/title data from 2016-01-01 through 2022-01-31.
- Implemented a robust title-to-comp merge (nearest-in-time title selection with 15-day bounds, then fallbacks) to align titles at each compensation effective date.
- Produced role-level bands for four role groups and output them in a single, analyst-friendly matrix:
  - Associate: Production Design Associate (2 steps)
  - Staff: Studio Designer, Production Designer, Studio Manager (2 steps)
  - Senior: Senior Studio Designer, Senior Production Designer, Senior Studio Manager (2 steps)
  - Director: Studio Design Director, Production Design Director, and variants containing Director + Studio/Production (3 steps)
- Excluded non-relevant titles and “Freelance” occurrences; ensured department filter strictly targets Studio/Production and excludes Tech.

### Data sources
- `namely_comp_data_history_w_notes`: Compensation events (with `Salary`, `Type`, `Employee Type`, dates).
- `namely_title_history_data_aq`: Title history (with `Title`, `Title Change Date`).

### Date and effective date logic
- Window: 2016-01-01 → 2022-01-31.
- Compensation effective date: `comp_effective_date = COALESCE(DATE(Salary Start Date), DATE(Start Date))`.

### Title-to-comp matching (how we align titles to comp rows)
For each comp row (by `Employee Number` + `comp_effective_date`), we pick the most appropriate title from title history:
1) On/before within 15 days (latest)
2) After within 15 days (earliest)
3) Fallback to latest prior title (no 15-day constraint)
4) If none, fallback to the comp row’s original `Job Title`

All joins are left joins to preserve comp rows.

### Department and row filters
- `Department IN ('Studio','Production')` and exclude `Tech` explicitly.
- `Employee Type = 'Staff Full Time'`.
- `Type IN ('yearly','salary','salaried','annual')`.
- Non-null salary and > 0.
- `comp_effective_date` within the date window.
- Exclude any title containing "Freelance".
- Explicitly exclude these titles:
  - Audio Producer, UX Designer, Senior Audio Producer, Senior UX Designer,
  - Senior User Experience Researcher, Creative Systems Technology Director,
  - Creative Technology Director, User Experience Director,
  - Knowledge Systems Administrator, Senior Experience Designer

### Role grouping and step logic
- Interchangeable titles → canonical role groups used for the matrix:
  - Associate: `PRODUCTION DESIGN ASSOCIATE` → 2 steps
  - Staff: `STUDIO DESIGNER`,`PRODUCTION DESIGNER`,`STUDIO MANAGER` → 2 steps
  - Senior: `SENIOR STUDIO DESIGNER`,`SENIOR PRODUCTION DESIGNER`,`SENIOR STUDIO MANAGER` → 2 steps
  - Director: Any title containing `DIRECTOR` and also containing either `STUDIO` or `PRODUCTION` → 3 steps

- Steps by level:
  - 2-step roles (Associate/Staff/Senior):
    - Step 1 = minimum salary in the filtered role dataset
    - Step 2 = ~62.5th percentile with guardrail and rounding:
      - Index: `CEIL(0.625 * N)` on salaries sorted ascending by amount, then date, then employee
      - Guardrail: `Step2 >= Step1 + 10000`
      - Rounding: round down to nearest `$5,000` via `FLOOR(value / 5000) * 5000`
  - 3-step roles (Director):
    - Step 1 = minimum
    - Step 2 = ~50th percentile, rounded down to `$5,000`
    - Step 3 = ~90th percentile

### Files added
- `Consulting Salary History for Modeling/Consultants_Salary_Data_projection_StudioCompBandMatrix.SQL` (final matrix output)
- `Consulting Salary History for Modeling/Consultants_Salary_Data_projection_StudioAllRoles.SQL` (all roles with per-role bands)
- `Consulting Salary History for Modeling/Consultants_Salary_Data_projection_StudioDesigner.SQL` (Staff, 2 steps)
- `Consulting Salary History for Modeling/Consultants_Salary_Data_projection_SeniorStudioDesigner.SQL` (Senior, 2 steps)
- `Consulting Salary History for Modeling/Consultants_Salary_Data_projection_StudioDesigner_with_Associate.SQL` (A/B including Associate variant)

### How to run
In MySQL:
```sql
SOURCE /Users/psweeney/leader-capacity-dashboard/Consulting\ Salary\ History\ for\ Modeling/Consultants_Salary_Data_projection_StudioCompBandMatrix.SQL;
```

### Lessons learned and reasoning notes
- Title alignment materially impacts percentiles; strict 15-day window around comp dates stabilizes mapping while avoiding noisy distant titles.
- Guardrail on Step 2 prevents near-equality with the minimum in small or top-heavy datasets; rounding to `$5k` helps create clean, spaced bands.
- Director titles appeared with multiple phrasings; broadening to `DIRECTOR` + `(STUDIO|PRODUCTION)` improved recall without leaking unrelated director roles.
- Exclusion lists are crucial—UX-, Audio-, and certain Director/Technology-oriented roles would otherwise skew percentiles for Studio/Production design roles.

### Final SQL (matrix output)
The following is the exact SQL used for the matrix output for 2016-01-01 → 2022-01-31.

```sql
/* ----------------------------------------------------------------------------
   Studio/Production Compensation Band Matrix (2016-01-01 to 2022-01-31)

   Comp Group: 'Specialist Consulting'
   Department (output label): 'Production,Studio,Studio Design'

   Role groups and Levels (synonyms treated as the same role):
     - Production Design Associate  → Level: Associate
         Titles: 'PRODUCTION DESIGN ASSOCIATE'
         Steps: 2 (Step1=min, Step2=~62.5th with $10k guardrail; $5k rounding)
     - Studio Designer              → Level: Staff
         Titles: 'STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER'
         Steps: 2 (Step1=min, Step2=~62.5th with $10k guardrail; $5k rounding)
     - Senior Studio Designer       → Level: Senior
         Titles: 'SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER'
         Steps: 2 (Step1=min, Step2=~62.5th with $10k guardrail; $5k rounding)
     - Studio Design Director       → Level: Director
         Titles: Director variants containing 'DIRECTOR' plus 'STUDIO' or 'PRODUCTION'
         Steps: 3 (Step1=min, Step2=~50th rounded to $5k, Step3=~90th)

   Title-to-comp matching (preserves comp rows):
     1) On/before within 15 days (latest)
     2) After within 15 days (earliest)
     3) Fallback latest prior title (no 15-day constraint)
     4) Fallback to comp row 'Job Title'

   Filters:
     - Departments: Studio or Production (explicitly exclude 'Tech')
     - Employee Type = 'Staff Full Time'
     - Type in {'yearly','salary','salaried','annual'}
     - Salary not null and > 0
     - comp_effective_date between 2016-01-01 and 2022-01-31
     - Exclude titles containing 'Freelance'
     - Exclude explicit titles:
         Audio Producer, UX Designer, Senior Audio Producer, Senior UX Designer,
         Senior User Experience Researcher, Creative Systems Technology Director,
         Creative Technology Director, User Experience Director,
         Knowledge Systems Administrator, Senior Experience Designer

   Implementation notes (MySQL 5.7-compatible):
     - Percentiles via discrete index CEIL(p * N) over salaries sorted ASC
     - Guardrail for 2-step roles: Step2 >= Step1 + 10000, rounded down to $5,000
---------------------------------------------------------------------------- */

SELECT
  'Specialist Consulting' AS `Comp Group`,
  'Production,Studio,Studio Design' AS `Department`,
  m.`Roles/Titles`,
  m.`Level`,
  m.`Step`,
  m.`Annual Salary USD`,
  DATE('2016-01-01') AS `Comp Band Start Date`,
  DATE('2022-01-31') AS `Comp Band End Date`
FROM (
  SELECT
    CASE WHEN cg.role_key = 'ASSOCIATE_PDA' THEN 'Production Design Associate'
         WHEN cg.role_key = 'STAFF_SD'      THEN 'Studio Designer,Production Designer,Studio Manager'
         WHEN cg.role_key = 'SENIOR_SSD'    THEN 'Senior Studio Designer,Senior Production Designer,Senior Studio Manager'
         WHEN cg.role_key = 'DIR_SDD'       THEN 'Studio Design Director,Production Design Director'
    END AS `Roles/Titles`,
    CASE WHEN cg.role_key = 'ASSOCIATE_PDA' THEN 'Associate'
         WHEN cg.role_key = 'STAFF_SD'      THEN 'Staff'
         WHEN cg.role_key = 'SENIOR_SSD'    THEN 'Senior'
         WHEN cg.role_key = 'DIR_SDD'       THEN 'Director'
    END AS `Level`,
    CONCAT('Step ', s.step_order) AS `Step`,
    ROUND(
      CASE
        WHEN cg.role_key IN ('ASSOCIATE_PDA','STAFF_SD','SENIOR_SSD') AND s.step_order = 1 THEN mn.min_usd
        WHEN cg.role_key IN ('ASSOCIATE_PDA','STAFF_SD','SENIOR_SSD') AND s.step_order = 2 THEN FLOOR(GREATEST(p62.salary_usd, mn.min_usd + 10000) / 5000) * 5000
        WHEN cg.role_key = 'DIR_SDD' AND s.step_order = 1 THEN mn.min_usd
        WHEN cg.role_key = 'DIR_SDD' AND s.step_order = 2 THEN FLOOR(COALESCE(p50.salary_usd, mn.min_usd) / 5000) * 5000
        WHEN cg.role_key = 'DIR_SDD' AND s.step_order = 3 THEN COALESCE(p90.salary_usd, mn.min_usd)
      END, 2
    ) AS `Annual Salary USD`
  FROM (
    SELECT 'ASSOCIATE_PDA' AS role_key UNION ALL
    SELECT 'STAFF_SD' UNION ALL
    SELECT 'SENIOR_SSD' UNION ALL
    SELECT 'DIR_SDD'
  ) AS cg
  JOIN (
    SELECT 1 AS step_order UNION ALL SELECT 2 UNION ALL SELECT 3
  ) AS s ON s.step_order <= CASE WHEN cg.role_key = 'DIR_SDD' THEN 3 ELSE 2 END
  JOIN (
    -- counts per group
    SELECT role_key, COUNT(*) AS total_rows
    FROM (
      SELECT
        CASE
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN ASSOCIATE' THEN 'ASSOCIATE_PDA'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER') THEN 'STAFF_SD'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER') THEN 'SENIOR_SSD'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%DIRECTOR%' AND (
               UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%STUDIO%'
            OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PRODUCTION%'
          ) THEN 'DIR_SDD'
          ELSE NULL
        END AS role_key
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
      WHERE TRIM(c.`Department`) IN ('Studio','Production')
        AND UPPER(TRIM(c.`Department`)) <> 'TECH'
        AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT IN (
          'AUDIO PRODUCER','UX DESIGNER','SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER',
          'SENIOR USER EXPERIENCE RESEARCHER','CREATIVE SYSTEMS TECHNOLOGY DIRECTOR',
          'CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR',
          'KNOWLEDGE SYSTEMS ADMINISTRATOR','SENIOR EXPERIENCE DESIGNER'
        )
    ) AS b
    WHERE b.role_key IS NOT NULL
    GROUP BY role_key
  ) AS cnt ON cnt.role_key = cg.role_key
  JOIN (
    -- min per group
    SELECT role_key, MIN(salary_usd) AS min_usd
    FROM (
      SELECT
        CASE
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN ASSOCIATE' THEN 'ASSOCIATE_PDA'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER') THEN 'STAFF_SD'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER') THEN 'SENIOR_SSD'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%DIRECTOR%' AND (
               UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%STUDIO%'
            OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PRODUCTION%'
          ) THEN 'DIR_SDD'
          ELSE NULL
        END AS role_key,
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
      WHERE TRIM(c.`Department`) IN ('Studio','Production')
        AND UPPER(TRIM(c.`Department`)) <> 'TECH'
        AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT IN (
          'AUDIO PRODUCER','UX DESIGNER','SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER',
          'SENIOR USER EXPERIENCE RESEARCHER','CREATIVE SYSTEMS TECHNOLOGY DIRECTOR',
          'CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR',
          'KNOWLEDGE SYSTEMS ADMINISTRATOR','SENIOR EXPERIENCE DESIGNER'
        )
        AND (
          UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN ASSOCIATE'
          OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER')
          OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER')
          OR (
            UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%DIRECTOR%'
            AND (
              UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%STUDIO%'
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PRODUCTION%'
            )
          )
        )
    ) AS bmin
    WHERE bmin.role_key IS NOT NULL
    GROUP BY role_key
  ) AS mn ON mn.role_key = cg.role_key
  LEFT JOIN (
    -- Ranked salaries per group for 62.5th
    SELECT r.role_key, r.salary_usd, r.rn
    FROM (
      SELECT ordered.role_key, ordered.salary_usd,
             @rn62 := IF(@prev62 = ordered.role_key, @rn62 + 1, 1) AS rn,
             @prev62 := ordered.role_key AS _prev
      FROM (
        SELECT base.role_key, base.salary_usd
        FROM (
          SELECT
            CASE
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN ASSOCIATE' THEN 'ASSOCIATE_PDA'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER') THEN 'STAFF_SD'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER') THEN 'SENIOR_SSD'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%DIRECTOR%' AND (
                   UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%STUDIO%'
                OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PRODUCTION%'
              ) THEN 'DIR_SDD'
              ELSE NULL
            END AS role_key,
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
          WHERE TRIM(c.`Department`) IN ('Studio','Production')
            AND UPPER(TRIM(c.`Department`)) <> 'TECH'
            AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
            AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
            AND c.`Salary` IS NOT NULL
            AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
            AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT IN (
              'AUDIO PRODUCER','UX DESIGNER','SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER',
              'SENIOR USER EXPERIENCE RESEARCHER','CREATIVE SYSTEMS TECHNOLOGY DIRECTOR',
              'CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR',
              'KNOWLEDGE SYSTEMS ADMINISTRATOR','SENIOR EXPERIENCE DESIGNER'
            )
            AND (
              UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN ASSOCIATE'
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER')
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER')
              OR (
                UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%DIRECTOR%'
                AND (
                  UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%STUDIO%'
                  OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PRODUCTION%'
                )
              )
            )
        ) AS base
        ORDER BY base.role_key ASC, base.salary_usd ASC
      ) AS ordered
      CROSS JOIN (SELECT @rn62 := 0, @prev62 := '') AS vars
    ) AS r
  ) AS p62 ON p62.role_key = cg.role_key AND p62.rn = GREATEST(1, CEIL(cnt.total_rows * 0.625))
  LEFT JOIN (
    -- Ranked salaries per group for 50th (directors)
    SELECT r.role_key, r.salary_usd, r.rn
    FROM (
      SELECT ordered.role_key, ordered.salary_usd,
             @rn50 := IF(@prev50 = ordered.role_key, @rn50 + 1, 1) AS rn,
             @prev50 := ordered.role_key AS _prev
      FROM (
        SELECT base.role_key, base.salary_usd
        FROM (
          SELECT
            CASE
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN ASSOCIATE' THEN 'ASSOCIATE_PDA'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER') THEN 'STAFF_SD'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER') THEN 'SENIOR_SSD'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%DIRECTOR%' AND (
                   UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%STUDIO%'
                OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PRODUCTION%'
              ) THEN 'DIR_SDD'
              ELSE NULL
            END AS role_key,
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
          WHERE TRIM(c.`Department`) IN ('Studio','Production')
            AND UPPER(TRIM(c.`Department`)) <> 'TECH'
            AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
            AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
            AND c.`Salary` IS NOT NULL
            AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
            AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT IN (
              'AUDIO PRODUCER','UX DESIGNER','SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER',
              'SENIOR USER EXPERIENCE RESEARCHER','CREATIVE SYSTEMS TECHNOLOGY DIRECTOR',
              'CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR',
              'KNOWLEDGE SYSTEMS ADMINISTRATOR','SENIOR EXPERIENCE DESIGNER'
            )
            AND (
              UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN ASSOCIATE'
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER')
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER')
              OR (
                UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%DIRECTOR%'
                AND (
                  UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%STUDIO%'
                  OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PRODUCTION%'
                )
              )
            )
        ) AS base
        ORDER BY base.role_key ASC, base.salary_usd ASC
      ) AS ordered
      CROSS JOIN (SELECT @rn50 := 0, @prev50 := '') AS vars
    ) AS r
  ) AS p50 ON p50.role_key = cg.role_key AND p50.rn = GREATEST(1, CEIL(cnt.total_rows * 0.50))
  LEFT JOIN (
    -- Ranked salaries per group for 90th (directors)
    SELECT r.role_key, r.salary_usd, r.rn
    FROM (
      SELECT ordered.role_key, ordered.salary_usd,
             @rn90 := IF(@prev90 = ordered.role_key, @rn90 + 1, 1) AS rn,
             @prev90 := ordered.role_key AS _prev
      FROM (
        SELECT base.role_key, base.salary_usd
        FROM (
          SELECT
            CASE
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN ASSOCIATE' THEN 'ASSOCIATE_PDA'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER') THEN 'STAFF_SD'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER') THEN 'SENIOR_SSD'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%DIRECTOR%' AND (
                   UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%STUDIO%'
                OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PRODUCTION%'
              ) THEN 'DIR_SDD'
              ELSE NULL
            END AS role_key,
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
          WHERE TRIM(c.`Department`) IN ('Studio','Production')
            AND UPPER(TRIM(c.`Department`)) <> 'TECH'
            AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
            AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
            AND c.`Salary` IS NOT NULL
            AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
            AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT IN (
              'AUDIO PRODUCER','UX DESIGNER','SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER',
              'SENIOR USER EXPERIENCE RESEARCHER','CREATIVE SYSTEMS TECHNOLOGY DIRECTOR',
              'CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR',
              'KNOWLEDGE SYSTEMS ADMINISTRATOR','SENIOR EXPERIENCE DESIGNER'
            )
            AND (
              UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN ASSOCIATE'
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER')
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER')
              OR (
                UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%DIRECTOR%'
                AND (
                  UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%STUDIO%'
                  OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PRODUCTION%'
                )
              )
            )
        ) AS base
        ORDER BY base.role_key ASC, base.salary_usd ASC
      ) AS ordered
      CROSS JOIN (SELECT @rn90 := 0, @prev90 := '') AS vars
    ) AS r
  ) AS p90 ON p90.role_key = cg.role_key AND p90.rn = GREATEST(1, CEIL(cnt.total_rows * 0.90))
) AS m
ORDER BY
  FIELD(m.`Level`, 'Associate','Staff','Senior','Director'),
  m.`Roles/Titles`,
  m.`Step`;
```

### How to extend
- Add/adjust synonym groups: Edit the CASE expressions that map raw titles to `role_key`/role groups.
- Add new windows: Duplicate the matrix query and change the comp window and the Band Start/End labels; UNION results for multiple eras.
- Adjust percentiles/guardrails: Change `0.625` and/or the `+ 10000` guardrail and rounding logic per level.
- Tighten/loosen Director matching: Update the `LIKE '%DIRECTOR%' AND ( ... '%STUDIO%' OR '%PRODUCTION%' )` predicate.

### Troubleshooting tips
- Empty Director rows: Confirm actual stored titles; add missing patterns (e.g., `DIRECTOR OF STUDIO`, `DIRECTOR, PRODUCTION DESIGN`).
- Unexpectedly low Step 2: Check role `N`; guardrail may be binding. Consider a higher percentile for small-N roles.
- Title alignment looks off: Verify title history density around comp dates; consider widening the 15-day window if needed (with caution).


