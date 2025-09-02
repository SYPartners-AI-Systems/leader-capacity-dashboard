/* ----------------------------------------------------------------------------
   Program Management / Project Management Compensation Band Matrix
   Window: 2016-01-01 to 2022-01-31

   Source datasets:
     - `namely_comp_data_history_w_notes` (compensation events)
     - `namely_title_history_data_aq`     (title history)

   Title-to-comp matching (preserves comp rows):
     1) On/before within 15 days (latest)
     2) After within 15 days (earliest)
     3) Fallback latest prior title (no 15-day constraint)
     4) Fallback to comp row 'Job Title'

   Departments: Program Management or Project Management
   Exclusions: Titles containing 'Freelance' or 'Product'

   Roles/Levels (interchangeable titles over time):
     - Associate → Program Coordinator (includes synonyms with 'Project')
     - Staff     → Program Manager     (includes synonyms with 'Project')
     - Senior    → Senior Program Manager / Sr Program Manager (includes 'Project')
     - Director  → Program Director (already established for this window)

   Steps by level for this build:
     - Associate/Staff/Senior → 2 steps
       Step 1 = minimum
       Step 2 = ~62.5th percentile with guardrail and rounding:
         - Index: CEIL(0.625 * N)
         - Guardrail: Step2 >= Step1 + 10000
         - Rounding: FLOOR(value/5000) * 5000

   MySQL 5.7 compatible (rank via user variables)
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
        /* Staff Step 2 + 1 strictly */
        COALESCE(
          FLOOR(GREATEST(stp62.staff_p62_usd, COALESCE(stmin.staff_min_usd, 0) + 10000) / 5000) * 5000 + 1,
          COALESCE(stmin.staff_min_usd, 0) + 10001
        )
      )
      WHEN s.step_order = 2 THEN FLOOR(
        GREATEST(
          p62.salary_usd,
          (
            CASE
              WHEN cg.role_key = 'SENIOR_SPM' THEN GREATEST(
                mn.min_usd,
                COALESCE(
                  FLOOR(GREATEST(stp62.staff_p62_usd, COALESCE(stmin.staff_min_usd, 0) + 10000) / 5000) * 5000 + 1,
                  COALESCE(stmin.staff_min_usd, 0) + 10001
                )
              )
              ELSE mn.min_usd
            END
          ) + 10000
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
JOIN (
  /* counts per role_key */
  SELECT role_key, COUNT(*) AS total_rows
  FROM (
    SELECT
      CASE
        WHEN role_title_norm IN ('PROGRAM COORDINATOR','PROJECT COORDINATOR') THEN 'ASSOC_PC'
        WHEN role_title_norm IN ('PROGRAM MANAGER','PROJECT MANAGER') THEN 'STAFF_PM'
        WHEN role_title_norm IN ('SENIOR PROGRAM MANAGER','SR PROGRAM MANAGER','SENIOR PROJECT MANAGER','SR PROJECT MANAGER') THEN 'SENIOR_SPM'
        ELSE NULL
      END AS role_key
    FROM (
      SELECT
        c.`Employee Number`,
        COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`) AS chosen_title,
        UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) AS chosen_title_norm,
        CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
        c.`Department`,
        c.comp_effective_date,
        CASE
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SR % PROGRAM MANAGER' THEN 'SR PROGRAM MANAGER'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SR % PROJECT MANAGER' THEN 'SR PROJECT MANAGER'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SENIOR % PROGRAM MANAGER' THEN 'SENIOR PROGRAM MANAGER'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SENIOR % PROJECT MANAGER' THEN 'SENIOR PROJECT MANAGER'
          ELSE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)))
        END AS role_title_norm
      FROM (
        SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
        FROM `namely_comp_data_history_w_notes` t1
      ) AS c
      /* Title matching: prefer on/before <=15d, else after <=15d */
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
      /* Title text at chosen date */
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS mtit ON mtit.`Employee Number` = c.`Employee Number` AND mtit.title_change_date = chosen.chosen_date
      /* Fallback title: latest prior (no 15d limit) */
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
      ) AS fb ON fb.`Employee Number` = c.`Employee Number`
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number` AND fbtit.title_change_date = fb.fb_date
      WHERE
        c.`Employee Type` = 'Staff Full Time'
        AND LOWER(TRIM(c.`Type`)) IN ('yearly','salary','salaried','annual')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND DATE(c.comp_effective_date) BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%PRODUCT%'
        AND UPPER(TRIM(c.`Department`)) IN ('PROGRAM MANAGEMENT','PROJECT MANAGEMENT')
    ) base
    HAVING role_key IS NOT NULL
  ) x
  GROUP BY role_key
) AS cnt ON cnt.role_key = cg.role_key
JOIN (
  /* min per role_key */
  SELECT role_key, MIN(salary_usd) AS min_usd
  FROM (
    SELECT
      CASE
        WHEN role_title_norm IN ('PROGRAM COORDINATOR','PROJECT COORDINATOR') THEN 'ASSOC_PC'
        WHEN role_title_norm IN ('PROGRAM MANAGER','PROJECT MANAGER') THEN 'STAFF_PM'
        WHEN role_title_norm IN ('SENIOR PROGRAM MANAGER','SR PROGRAM MANAGER','SENIOR PROJECT MANAGER','SR PROJECT MANAGER') THEN 'SENIOR_SPM'
        ELSE NULL
      END AS role_key,
      salary_usd
    FROM (
      SELECT
        CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
        CASE
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SR % PROGRAM MANAGER' THEN 'SR PROGRAM MANAGER'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SR % PROJECT MANAGER' THEN 'SR PROJECT MANAGER'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SENIOR % PROGRAM MANAGER' THEN 'SENIOR PROGRAM MANAGER'
          WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SENIOR % PROJECT MANAGER' THEN 'SENIOR PROJECT MANAGER'
          ELSE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)))
        END AS role_title_norm
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
      ) AS fb ON fb.`Employee Number` = c.`Employee Number`
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number` AND fbtit.title_change_date = fb.fb_date
      WHERE
        c.`Employee Type` = 'Staff Full Time'
        AND LOWER(TRIM(c.`Type`)) IN ('yearly','salary','salaried','annual')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND DATE(c.comp_effective_date) BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%PRODUCT%'
        AND UPPER(TRIM(c.`Department`)) IN ('PROGRAM MANAGEMENT','PROJECT MANAGEMENT')
    ) base
    HAVING role_key IS NOT NULL
  ) m
  GROUP BY role_key
) AS mn ON mn.role_key = cg.role_key
LEFT JOIN (
  /* 62.5th percentile per role_key via discrete index using user variables */
  SELECT r.role_key, r.salary_usd, r.rn
  FROM (
    SELECT ranked.role_key, ranked.salary_usd,
           @rn62 := IF(@prev62 = ranked.role_key, @rn62 + 1, 1) AS rn,
           @prev62 := ranked.role_key AS _prev
    FROM (
      SELECT ordered.role_key, ordered.salary_usd
      FROM (
        SELECT
          CASE
            WHEN role_title_norm IN ('PROGRAM COORDINATOR','PROJECT COORDINATOR') THEN 'ASSOC_PC'
            WHEN role_title_norm IN ('PROGRAM MANAGER','PROJECT MANAGER') THEN 'STAFF_PM'
            WHEN role_title_norm IN ('SENIOR PROGRAM MANAGER','SR PROGRAM MANAGER','SENIOR PROJECT MANAGER','SR PROJECT MANAGER') THEN 'SENIOR_SPM'
            ELSE NULL
          END AS role_key,
          salary_usd
        FROM (
          SELECT
            CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
            CASE
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SR % PROGRAM MANAGER' THEN 'SR PROGRAM MANAGER'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SR % PROJECT MANAGER' THEN 'SR PROJECT MANAGER'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SENIOR % PROGRAM MANAGER' THEN 'SENIOR PROGRAM MANAGER'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SENIOR % PROJECT MANAGER' THEN 'SENIOR PROJECT MANAGER'
              ELSE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)))
            END AS role_title_norm
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
          ) AS fb ON fb.`Employee Number` = c.`Employee Number`
          LEFT JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number` AND fbtit.title_change_date = fb.fb_date
          WHERE
            c.`Employee Type` = 'Staff Full Time'
            AND LOWER(TRIM(c.`Type`)) IN ('yearly','salary','salaried','annual')
            AND c.`Salary` IS NOT NULL
            AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
            AND DATE(c.comp_effective_date) BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%PRODUCT%'
            AND UPPER(TRIM(c.`Department`)) IN ('PROGRAM MANAGEMENT','PROJECT MANAGEMENT')
        ) base
        HAVING role_key IS NOT NULL
        ORDER BY role_key, salary_usd ASC
      ) AS ordered, (SELECT @rn62 := 0, @prev62 := NULL) vars
    ) ranked
  ) r
  /* join index at ceil(0.625 * N) per role */
  JOIN (
    SELECT role_key,
           GREATEST(1, CEIL(total_rows * 0.625)) AS idx_62
    FROM (
      SELECT role_key, COUNT(*) AS total_rows
      FROM (
        SELECT
          CASE
            WHEN role_title_norm IN ('PROGRAM COORDINATOR','PROJECT COORDINATOR') THEN 'ASSOC_PC'
            WHEN role_title_norm IN ('PROGRAM MANAGER','PROJECT MANAGER') THEN 'STAFF_PM'
            WHEN role_title_norm IN ('SENIOR PROGRAM MANAGER','SR PROGRAM MANAGER','SENIOR PROJECT MANAGER','SR PROJECT MANAGER') THEN 'SENIOR_SPM'
            ELSE NULL
          END AS role_key
        FROM (
          SELECT
            CASE
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SR % PROGRAM MANAGER' THEN 'SR PROGRAM MANAGER'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SR % PROJECT MANAGER' THEN 'SR PROJECT MANAGER'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SENIOR % PROGRAM MANAGER' THEN 'SENIOR PROGRAM MANAGER'
              WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'SENIOR % PROJECT MANAGER' THEN 'SENIOR PROJECT MANAGER'
              ELSE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)))
            END AS role_title_norm
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
          ) AS fb ON fb.`Employee Number` = c.`Employee Number`
          LEFT JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number` AND fbtit.title_change_date = fb.fb_date
          WHERE
            c.`Employee Type` = 'Staff Full Time'
            AND LOWER(TRIM(c.`Type`)) IN ('yearly','salary','salaried','annual')
            AND c.`Salary` IS NOT NULL
            AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
            AND DATE(c.comp_effective_date) BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
            AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%PRODUCT%'
            AND UPPER(TRIM(c.`Department`)) IN ('PROGRAM MANAGEMENT','PROJECT MANAGEMENT')
        ) grouped
      ) y
      GROUP BY role_key
    ) n
  ) idx ON idx.role_key = r.role_key AND idx.idx_62 = r.rn
) AS p62 ON p62.role_key = cg.role_key
/* Staff 62.5th percentile (for Staff Step 2 guard used by Senior floor) */
LEFT JOIN (
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
/* Cross-level guardrail: ensure Senior Step 1 >= Staff Step 1 */
LEFT JOIN (
  SELECT MIN(salary_usd) AS staff_min_usd
  FROM (
    SELECT DISTINCT CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd
    FROM `namely_comp_data_history_w_notes` c
    WHERE UPPER(TRIM(c.`Department`)) IN ('PROGRAM MANAGEMENT','PROJECT MANAGEMENT')
      AND UPPER(TRIM(c.`Job Title`)) LIKE '%PROGRAM MANAGER%'
      AND c.`Employee Type` = 'Staff Full Time'
      AND LOWER(TRIM(c.`Type`)) IN ('yearly','salary','salaried','annual')
      AND c.`Salary` IS NOT NULL
      AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
  ) AS sbase
) AS stmin ON 1=1
ORDER BY
  FIELD(`Level`, 'Associate','Staff','Senior','Director'),
  `Step`;
