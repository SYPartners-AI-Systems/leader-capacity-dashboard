/* ----------------------------------------------------------------------------
   Studio/Production - All Roles: percentile-based compensation bands (2016-01-01 to 2022-01-31)

   Source datasets:
     - namely_comp_data_history_w_notes (compensation events)
     - namely_title_history_data_aq     (title history)

   Title-to-comp matching (preserves comp rows):
     1) On/before within 15 days (latest)
     2) After within 15 days (earliest)
     3) Fallback latest prior title (no 15-day constraint)
     4) Fallback to comp row "Job Title"

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

   Role grouping (interchangeable titles → canonical role):
     - 'Studio Designer' group:  'STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER'
     - 'Senior Studio Designer': 'SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER'
     - All other titles remain as-is (after filtering) to provide complete coverage.

   Steps per role:
     - Two-step roles (default): Step 1 = min; Step 2 = ~62.5th percentile with guardrail
         Step 2 = FLOOR(GREATEST(p62_5, Step1 + 10000) / 5000) * 5000
     - Three-step roles (titles containing 'DIRECTOR'): Step 1 = min; Step 2 = ~50th (rounded to $5k);
         Step 3 = ~90th (no rounding)

   Implementation notes (MySQL 5.7):
     - Percentiles via discrete index CEIL(p * N) on rank-ordered salaries
     - Per-role ranking implemented with user variables reset on role change
---------------------------------------------------------------------------- */

-- Base set with comp_effective_date and matched title
SELECT
  role_steps.role_group       AS `Role`,
  role_steps.step_order       AS `Step Order`,
  role_steps.step_label       AS `Step`,
  ROUND(
    CASE
      WHEN role_steps.step_order = 1 THEN mn.min_usd
      WHEN role_steps.is_three_step = 0 AND role_steps.step_order = 2 THEN FLOOR(GREATEST(r62.salary_usd, mn.min_usd + 10000) / 5000) * 5000
      WHEN role_steps.is_three_step = 1 AND role_steps.step_order = 2 THEN FLOOR(COALESCE(r50.salary_usd, mn.min_usd) / 5000) * 5000
      WHEN role_steps.is_three_step = 1 AND role_steps.step_order = 3 THEN COALESCE(r90.salary_usd, mn.min_usd)
    END
  , 2) AS `Salary USD`,
  cnt.total_rows              AS `Num Records`
FROM (
  -- Distinct role list with step model (2-step default; 3-step for Director roles)
  SELECT rl.role_group,
         rl.is_three_step,
         s.step_order,
         CASE
           WHEN s.step_order = 1 THEN 'Step 1: lowest range'
           WHEN s.step_order = 2 AND rl.is_three_step = 0 THEN 'Step 2: ~62.5th percentile (guardrailed)'
           WHEN s.step_order = 2 AND rl.is_three_step = 1 THEN 'Step 2: ~50th percentile'
           WHEN s.step_order = 3 AND rl.is_three_step = 1 THEN 'Step 3: ~90th percentile'
         END AS step_label
  FROM (
    SELECT DISTINCT bx.role_group,
           CASE WHEN UPPER(bx.role_group) LIKE '%DIRECTOR%' THEN 1 ELSE 0 END AS is_three_step
    FROM (
      SELECT
        CASE
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER') THEN 'Senior Studio Designer'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER') THEN 'Studio Designer'
          ELSE TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))
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
    ) AS bx
  ) AS rl
  JOIN (
    SELECT 1 AS step_order
    UNION ALL SELECT 2
    UNION ALL SELECT 3
  ) AS s ON s.step_order <= CASE WHEN rl.is_three_step = 1 THEN 3 ELSE 2 END
) AS role_steps
JOIN (
  -- Counts per role
  SELECT base.role_group, COUNT(*) AS total_rows
  FROM (
    SELECT
      CASE
        WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER') THEN 'Senior Studio Designer'
        WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER') THEN 'Studio Designer'
        ELSE TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))
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
  ) AS base
  GROUP BY base.role_group
) AS cnt
  ON cnt.role_group = role_steps.role_group
JOIN (
  -- Minimum per role
  SELECT base.role_group, MIN(base.salary_usd) AS min_usd
  FROM (
    SELECT
      CASE
        WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER') THEN 'Senior Studio Designer'
        WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER') THEN 'Studio Designer'
        ELSE TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))
      END AS role_group,
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
        'CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR'
      )
  ) AS base
  GROUP BY base.role_group
) AS mn
  ON mn.role_group = role_steps.role_group
LEFT JOIN (
  -- Ranked salaries per role to support percentile selection
  SELECT ordered.role_group, ordered.salary_usd, ordered.comp_effective_date, ordered.employee_number,
         @rn := IF(@prev_role = ordered.role_group, @rn + 1, 1) AS rn,
         @prev_role := ordered.role_group AS _set_prev
  FROM (
    SELECT base.role_group,
           base.salary_usd,
           base.comp_effective_date,
           base.employee_number
    FROM (
      SELECT
        CASE
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER') THEN 'Senior Studio Designer'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER') THEN 'Studio Designer'
          ELSE TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))
        END AS role_group,
        CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
        c.comp_effective_date,
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
    ) AS base
    ORDER BY base.role_group ASC, base.salary_usd ASC, base.comp_effective_date ASC, base.employee_number ASC
  ) AS ordered
  CROSS JOIN (SELECT @rn := 0, @prev_role := '') AS vars
) AS ranked
  ON ranked.role_group = role_steps.role_group
LEFT JOIN (
  -- 62.5th percentile per role
  SELECT r1.role_group, r1.salary_usd, r1.rn
  FROM (
    SELECT ordered.role_group, ordered.salary_usd, ordered.comp_effective_date, ordered.employee_number,
           @rn62 := IF(@prev_role62 = ordered.role_group, @rn62 + 1, 1) AS rn,
           @prev_role62 := ordered.role_group AS _set_prev62
    FROM (
      SELECT base.role_group,
             base.salary_usd,
             base.comp_effective_date,
             base.employee_number
      FROM (
        SELECT
          CASE
            WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER') THEN 'Senior Studio Designer'
            WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER') THEN 'Studio Designer'
            ELSE TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))
          END AS role_group,
          CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
          c.comp_effective_date,
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
      ) AS base
      ORDER BY base.role_group ASC, base.salary_usd ASC, base.comp_effective_date ASC, base.employee_number ASC
    ) AS ordered
    CROSS JOIN (SELECT @rn62 := 0, @prev_role62 := '') AS vars
  ) AS r1
) AS r62
  ON r62.role_group = role_steps.role_group AND r62.rn = GREATEST(1, CEIL(cnt.total_rows * 0.625))
LEFT JOIN (
  -- 50th percentile per role
  SELECT r1.role_group, r1.salary_usd, r1.rn
  FROM (
    SELECT ordered.role_group, ordered.salary_usd, ordered.comp_effective_date, ordered.employee_number,
           @rn50 := IF(@prev_role50 = ordered.role_group, @rn50 + 1, 1) AS rn,
           @prev_role50 := ordered.role_group AS _set_prev50
    FROM (
      SELECT base.role_group,
             base.salary_usd,
             base.comp_effective_date,
             base.employee_number
      FROM (
        SELECT
          CASE
            WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER') THEN 'Senior Studio Designer'
            WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER') THEN 'Studio Designer'
            ELSE TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))
          END AS role_group,
          CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
          c.comp_effective_date,
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
      ) AS base
      ORDER BY base.role_group ASC, base.salary_usd ASC, base.comp_effective_date ASC, base.employee_number ASC
    ) AS ordered
    CROSS JOIN (SELECT @rn50 := 0, @prev_role50 := '') AS vars
  ) AS r1
) AS r50
  ON r50.role_group = role_steps.role_group AND r50.rn = GREATEST(1, CEIL(cnt.total_rows * 0.50))
LEFT JOIN (
  -- 90th percentile per role
  SELECT r1.role_group, r1.salary_usd, r1.rn
  FROM (
    SELECT ordered.role_group, ordered.salary_usd, ordered.comp_effective_date, ordered.employee_number,
           @rn90 := IF(@prev_role90 = ordered.role_group, @rn90 + 1, 1) AS rn,
           @prev_role90 := ordered.role_group AS _set_prev90
    FROM (
      SELECT base.role_group,
             base.salary_usd,
             base.comp_effective_date,
             base.employee_number
      FROM (
        SELECT
          CASE
            WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR STUDIO DESIGNER','SENIOR PRODUCTION DESIGNER','SENIOR STUDIO MANAGER') THEN 'Senior Studio Designer'
            WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DESIGNER','PRODUCTION DESIGNER','STUDIO MANAGER') THEN 'Studio Designer'
            ELSE TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))
          END AS role_group,
          CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
          c.comp_effective_date,
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
          GROUP BY p.`Employee Number`, p.`comp_effective_date`
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
            'CREATIVE TECHNOLOGY DIRECTOR','USER EXPERIENCE DIRECTOR'
          )
      ) AS base
      ORDER BY base.role_group ASC, base.salary_usd ASC, base.comp_effective_date ASC, base.employee_number ASC
    ) AS ordered
    CROSS JOIN (SELECT @rn90 := 0, @prev_role90 := '') AS vars
  ) AS r1
) AS r90
  ON r90.role_group = role_steps.role_group AND r90.rn = GREATEST(1, CEIL(cnt.total_rows * 0.90))
ORDER BY role_steps.role_group, role_steps.step_order;


