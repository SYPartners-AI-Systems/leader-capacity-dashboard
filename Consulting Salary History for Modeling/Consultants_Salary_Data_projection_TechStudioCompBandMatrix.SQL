/* ----------------------------------------------------------------------------
   Tech/Studio Compensation Band Matrix (2016-01-01 to 2022-01-31)

   Comp Group: 'Core Consulting'
   Department (output label): 'Tech, Studio, Studio Tech/UX'

   Role groups and Levels (synonyms treated as the same role):
     - Staff → 'STAFF_AP_UX'
         Titles: 'AUDIO PRODUCER','UX DESIGNER','USER EXPERIENCE DESIGNER'
         Steps: 2 (Step1=min, Step2=~62.5th with $10k guardrail; $5k rounding)
     - Senior → 'SENIOR_AP_UX'
         Titles: 'SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER','SENIOR USER EXPERIENCE RESEARCHER'
         Steps: 2 (Step1=min, Step2=~62.5th with $10k guardrail; $5k rounding)
     - Director → 'DIR_TECH_UX'
         Titles: 'CREATIVE SYSTEMS TECHNOLOGY DIRECTOR','CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR'
         Steps: 3 (Step1=min, Step2=~50th rounded to $5k, Step3=~90th)

   Title-to-comp matching (preserves comp rows):
     1) On/before within 15 days (latest)
     2) After within 15 days (earliest)
     3) Fallback latest prior title (no 15-day constraint)
     4) Fallback to comp row 'Job Title'

   Filters:
     - Departments: Studio or Tech (EXCLUDE 'Production')
     - Employee Type = 'Staff Full Time'
     - Type in {'yearly','salary','salaried','annual'}
     - Salary not null and > 0
     - comp_effective_date between 2016-01-01 and 2022-01-31
     - Exclude titles containing 'Freelance'

   Implementation notes (MySQL 5.7-compatible):
     - Percentiles via discrete index CEIL(p * N) over salaries sorted ASC
     - Guardrail for 2-step roles: Step2 >= Step1 + 10000, rounded down to $5,000
---------------------------------------------------------------------------- */

SELECT
  'Core Consulting' AS `Comp Group`,
  'Tech, Studio, Studio Tech/UX' AS `Department`,
  m.`Roles/Titles`,
  m.`Level`,
  m.`Step`,
  m.`Annual Salary USD`,
  DATE('2016-01-01') AS `Comp Band Start Date`,
  DATE('2022-01-31') AS `Comp Band End Date`
FROM (
  SELECT
    CASE WHEN cg.role_key = 'STAFF_AP_UX'  THEN 'Audio Producer,UX Designer,User Experience Designer'
         WHEN cg.role_key = 'SENIOR_AP_UX' THEN 'Senior Audio Producer,Senior UX Designer,Senior User Experience Researcher'
         WHEN cg.role_key = 'DIR_TECH_UX'  THEN 'Creative Systems Technology Director,Creative Technology Director,User Experience Director'
    END AS `Roles/Titles`,
    CASE WHEN cg.role_key = 'STAFF_AP_UX'  THEN 'Staff'
         WHEN cg.role_key = 'SENIOR_AP_UX' THEN 'Senior'
         WHEN cg.role_key = 'DIR_TECH_UX'  THEN 'Director'
    END AS `Level`,
    CONCAT('Step ', s.step_order) AS `Step`,
    ROUND(
      CASE
        WHEN cg.role_key IN ('STAFF_AP_UX','SENIOR_AP_UX') AND s.step_order = 1 THEN mn.min_usd
        WHEN cg.role_key IN ('STAFF_AP_UX','SENIOR_AP_UX') AND s.step_order = 2 THEN FLOOR(GREATEST(p62.salary_usd, mn.min_usd + 10000) / 5000) * 5000
        WHEN cg.role_key = 'DIR_TECH_UX' AND s.step_order = 1 THEN mn.min_usd
        WHEN cg.role_key = 'DIR_TECH_UX' AND s.step_order = 2 THEN FLOOR(COALESCE(p50.salary_usd, mn.min_usd) / 5000) * 5000
        WHEN cg.role_key = 'DIR_TECH_UX' AND s.step_order = 3 THEN COALESCE(p90.salary_usd, mn.min_usd)
      END, 2
    ) AS `Annual Salary USD`
  FROM (
    SELECT 'STAFF_AP_UX' AS role_key UNION ALL
    SELECT 'SENIOR_AP_UX' UNION ALL
    SELECT 'DIR_TECH_UX'
  ) AS cg
  JOIN (
    SELECT 1 AS step_order UNION ALL SELECT 2 UNION ALL SELECT 3
  ) AS s ON s.step_order <= CASE WHEN cg.role_key = 'DIR_TECH_UX' THEN 3 ELSE 2 END
  JOIN (
    -- counts per group
    SELECT role_key, COUNT(*) AS total_rows
    FROM (
      SELECT
        CASE
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('AUDIO PRODUCER','UX DESIGNER','USER EXPERIENCE DESIGNER') THEN 'STAFF_AP_UX'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER','SENIOR USER EXPERIENCE RESEARCHER') THEN 'SENIOR_AP_UX'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('CREATIVE SYSTEMS TECHNOLOGY DIRECTOR','CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR','MANAGING TECHNOLOGY DIRECTOR') THEN 'DIR_TECH_UX'
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
      WHERE (TRIM(c.`Department`) IN ('Studio','Tech') OR c.`Department` IS NULL OR TRIM(c.`Department`) = '')
        AND (c.`Department` IS NULL OR UPPER(TRIM(c.`Department`)) <> 'PRODUCTION')
        AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
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
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('AUDIO PRODUCER','UX DESIGNER','USER EXPERIENCE DESIGNER') THEN 'STAFF_AP_UX'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER','SENIOR USER EXPERIENCE RESEARCHER') THEN 'SENIOR_AP_UX'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('CREATIVE SYSTEMS TECHNOLOGY DIRECTOR','CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR','MANAGING TECHNOLOGY DIRECTOR') THEN 'DIR_TECH_UX'
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
      WHERE (TRIM(c.`Department`) IN ('Studio','Tech') OR c.`Department` IS NULL OR TRIM(c.`Department`) = '')
        AND (c.`Department` IS NULL OR UPPER(TRIM(c.`Department`)) <> 'PRODUCTION')
        AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
        AND (
          UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('AUDIO PRODUCER','UX DESIGNER','USER EXPERIENCE DESIGNER')
          OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER','SENIOR USER EXPERIENCE RESEARCHER')
          OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('CREATIVE SYSTEMS TECHNOLOGY DIRECTOR','CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR')
        )
    ) AS bmin
    WHERE bmin.role_key IS NOT NULL
    GROUP BY role_key
  ) AS mn ON mn.role_key = cg.role_key
  LEFT JOIN (
    -- 62.5th percentile per group (for 2-step roles)
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
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('AUDIO PRODUCER','UX DESIGNER','USER EXPERIENCE DESIGNER') THEN 'STAFF_AP_UX'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER','SENIOR USER EXPERIENCE RESEARCHER') THEN 'SENIOR_AP_UX'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('CREATIVE SYSTEMS TECHNOLOGY DIRECTOR','CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR') THEN 'DIR_TECH_UX'
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
          WHERE (TRIM(c.`Department`) IN ('Studio','Tech') OR c.`Department` IS NULL OR TRIM(c.`Department`) = '')
            AND (c.`Department` IS NULL OR UPPER(TRIM(c.`Department`)) <> 'PRODUCTION')
            AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
            AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
            AND c.`Salary` IS NOT NULL
            AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
            AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
            AND (
              UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('AUDIO PRODUCER','UX DESIGNER','USER EXPERIENCE DESIGNER')
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER','SENIOR USER EXPERIENCE RESEARCHER')
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('CREATIVE SYSTEMS TECHNOLOGY DIRECTOR','CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR','MANAGING TECHNOLOGY DIRECTOR')
            )
        ) AS base
        ORDER BY base.role_key ASC, base.salary_usd ASC
      ) AS ordered
      CROSS JOIN (SELECT @rn62 := 0, @prev62 := '') AS vars
    ) AS r
  ) AS p62 ON p62.role_key = cg.role_key AND p62.rn = GREATEST(1, CEIL(cnt.total_rows * 0.625))
  LEFT JOIN (
    -- 50th percentile per group (directors)
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
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('AUDIO PRODUCER','UX DESIGNER','USER EXPERIENCE DESIGNER') THEN 'STAFF_AP_UX'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER','SENIOR USER EXPERIENCE RESEARCHER') THEN 'SENIOR_AP_UX'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('CREATIVE SYSTEMS TECHNOLOGY DIRECTOR','CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR') THEN 'DIR_TECH_UX'
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
          WHERE (TRIM(c.`Department`) IN ('Studio','Tech') OR c.`Department` IS NULL OR TRIM(c.`Department`) = '')
            AND (c.`Department` IS NULL OR UPPER(TRIM(c.`Department`)) <> 'PRODUCTION')
            AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
            AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
            AND c.`Salary` IS NOT NULL
            AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
            AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
            AND (
              UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('AUDIO PRODUCER','UX DESIGNER','USER EXPERIENCE DESIGNER')
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER','SENIOR USER EXPERIENCE RESEARCHER')
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('CREATIVE SYSTEMS TECHNOLOGY DIRECTOR','CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR','MANAGING TECHNOLOGY DIRECTOR')
            )
        ) AS base
        ORDER BY base.role_key ASC, base.salary_usd ASC
      ) AS ordered
      CROSS JOIN (SELECT @rn50 := 0, @prev50 := '') AS vars
    ) AS r
  ) AS p50 ON p50.role_key = cg.role_key AND p50.rn = GREATEST(1, CEIL(cnt.total_rows * 0.50))
  LEFT JOIN (
    -- 90th percentile per group (directors)
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
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('AUDIO PRODUCER','UX DESIGNER','USER EXPERIENCE DESIGNER') THEN 'STAFF_AP_UX'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER','SENIOR USER EXPERIENCE RESEARCHER') THEN 'SENIOR_AP_UX'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('CREATIVE SYSTEMS TECHNOLOGY DIRECTOR','CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR') THEN 'DIR_TECH_UX'
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
          WHERE (TRIM(c.`Department`) IN ('Studio','Tech') OR c.`Department` IS NULL OR TRIM(c.`Department`) = '')
            AND (c.`Department` IS NULL OR UPPER(TRIM(c.`Department`)) <> 'PRODUCTION')
            AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
            AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
            AND c.`Salary` IS NOT NULL
            AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
            AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
            AND (
              UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('AUDIO PRODUCER','UX DESIGNER','USER EXPERIENCE DESIGNER')
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR AUDIO PRODUCER','SENIOR UX DESIGNER','SENIOR USER EXPERIENCE RESEARCHER')
              OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('CREATIVE SYSTEMS TECHNOLOGY DIRECTOR','CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR','MANAGING TECHNOLOGY DIRECTOR')
            )
        ) AS base
        ORDER BY base.role_key ASC, base.salary_usd ASC
      ) AS ordered
      CROSS JOIN (SELECT @rn90 := 0, @prev90 := '') AS vars
    ) AS r
  ) AS p90 ON p90.role_key = cg.role_key AND p90.rn = GREATEST(1, CEIL(cnt.total_rows * 0.90))
) AS m
ORDER BY
  FIELD(m.`Level`, 'Staff','Senior','Director'),
  m.`Roles/Titles`,
  m.`Step`;


