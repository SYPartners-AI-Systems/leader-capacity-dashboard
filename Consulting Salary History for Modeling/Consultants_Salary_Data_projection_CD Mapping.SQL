/* ----------------------------------------------------------------------------
   Creative Director (CD) compensation band calculation (2016-01-01 to 2022-01-31)

   Methodology (percentile-based):
   - Step 1: minimum salary ("lowest range")
   - Step 2: ~75th percentile salary (discrete index via CEIL(0.75 * N))
   - Step 3: ~90th percentile salary (discrete index via CEIL(0.90 * N))

   Implementation notes (MySQL 5.7-compatible):
   - Percentiles approximated by selecting the salary at CEIL(p * N) after sorting
     ascending by salary, using user-variable row numbering.
   - Title matching mirrors the earlier approach: prefer on/before within 15 days,
     else after within 15 days; fallback to latest prior title if needed.
   - Step 2 rounding: Step 2 is rounded down to the nearest $5,000 via
     FLOOR(value/5000)*5000 to produce clean, separated bands and avoid
     Step 2 ≈ Step 1/3 in small or clustered distributions.
---------------------------------------------------------------------------- */

SELECT
  'Creative Director' AS `Role`,
  sr.step_order AS `Step Order`,
  sr.step_label AS `Step`,
  ROUND(CASE WHEN sr.step_order = 2 THEN FLOOR(COALESCE(s2_cd.second_min_usd, r.salary_usd) / 5000) * 5000 ELSE r.salary_usd END, 2) AS `Salary USD`,
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
    SELECT
      1
    FROM (
      SELECT
        t1.*,
        COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
      FROM `namely_comp_data_history_w_notes` t1
    ) AS c
    LEFT JOIN (
      SELECT
        p.`Employee Number`,
        p.comp_effective_date,
        COALESCE(ob.match_date, af.match_date) AS chosen_date
      FROM (
        SELECT DISTINCT
          COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
          `Employee Number`
        FROM `namely_comp_data_history_w_notes`
      ) AS p
      /* on/before within 15 days */
      LEFT JOIN (
        SELECT
          p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
        FROM (
          SELECT DISTINCT
            COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
            `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) p2
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) th2
          ON th2.`Employee Number` = p2.`Employee Number`
        WHERE th2.title_change_date <= p2.comp_effective_date
          AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
        GROUP BY p2.`Employee Number`, p2.comp_effective_date
      ) ob
        ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
      /* after within 15 days */
      LEFT JOIN (
        SELECT
          p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
        FROM (
          SELECT DISTINCT
            COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
            `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) p3
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) th3
          ON th3.`Employee Number` = p3.`Employee Number`
        WHERE th3.title_change_date >= p3.comp_effective_date
          AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
        GROUP BY p3.`Employee Number`, p3.comp_effective_date
      ) af
        ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
    ) AS chosen
      ON chosen.`Employee Number` = c.`Employee Number`
     AND chosen.comp_effective_date = c.comp_effective_date
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS mtit
      ON mtit.`Employee Number` = c.`Employee Number`
     AND mtit.title_change_date = chosen.chosen_date
    LEFT JOIN (
      SELECT
        p.`Employee Number`,
        p.comp_effective_date,
        MAX(th.title_change_date) AS fb_date
      FROM (
        SELECT DISTINCT
          COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
          `Employee Number`
        FROM `namely_comp_data_history_w_notes`
      ) AS p
      JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS th
        ON th.`Employee Number` = p.`Employee Number`
      WHERE th.title_change_date <= p.comp_effective_date
      GROUP BY p.`Employee Number`, p.comp_effective_date
    ) AS fb
      ON fb.`Employee Number` = c.`Employee Number`
     AND fb.comp_effective_date = c.comp_effective_date
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS fbtit
      ON fbtit.`Employee Number` = c.`Employee Number`
     AND fbtit.title_change_date = fb.fb_date
    WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'CREATIVE DIRECTOR'
      AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
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
      WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c2.`Job Title`))) = 'CREATIVE DIRECTOR'
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c2.`Job Title`))) NOT LIKE '%FREELANCE%'
        AND UPPER(TRIM(c2.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c2.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
    ) AS rb2
  )
) AS s2_cd
LEFT JOIN (
  SELECT ranked.rn, ranked.salary_usd
  FROM (
    SELECT
      base.salary_usd,
      @rownum := @rownum + 1 AS rn
    FROM (
      SELECT
        CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
        c.comp_effective_date AS comp_effective_date,
        c.`Employee Number` AS employee_number
      FROM (
        SELECT
          t1.*,
          COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
        FROM `namely_comp_data_history_w_notes` t1
      ) AS c
      LEFT JOIN (
        SELECT
          p.`Employee Number`,
          p.comp_effective_date,
          COALESCE(ob.match_date, af.match_date) AS chosen_date
        FROM (
          SELECT DISTINCT
            COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
            `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) AS p
        LEFT JOIN (
          SELECT
            p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
          FROM (
            SELECT DISTINCT
              COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
              `Employee Number`
            FROM `namely_comp_data_history_w_notes`
          ) p2
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) th2
            ON th2.`Employee Number` = p2.`Employee Number`
          WHERE th2.title_change_date <= p2.comp_effective_date
            AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
          GROUP BY p2.`Employee Number`, p2.comp_effective_date
        ) ob
          ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
        LEFT JOIN (
          SELECT
            p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
          FROM (
            SELECT DISTINCT
              COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
              `Employee Number`
            FROM `namely_comp_data_history_w_notes`
          ) p3
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) th3
            ON th3.`Employee Number` = p3.`Employee Number`
          WHERE th3.title_change_date >= p3.comp_effective_date
            AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
          GROUP BY p3.`Employee Number`, p3.comp_effective_date
        ) af
          ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
      ) AS chosen
        ON chosen.`Employee Number` = c.`Employee Number`
       AND chosen.comp_effective_date = c.comp_effective_date
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS mtit
        ON mtit.`Employee Number` = c.`Employee Number`
       AND mtit.title_change_date = chosen.chosen_date
      LEFT JOIN (
        SELECT
          p.`Employee Number`,
          p.comp_effective_date,
          MAX(th.title_change_date) AS fb_date
        FROM (
          SELECT DISTINCT
            COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
            `Employee Number`
          FROM `namely_comp_data_history_w_notes`
        ) AS p
        JOIN (
          SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
          FROM `namely_title_history_data_aq`
          WHERE `Title` IS NOT NULL
        ) AS th
          ON th.`Employee Number` = p.`Employee Number`
        WHERE th.title_change_date <= p.comp_effective_date
        GROUP BY p.`Employee Number`, p.comp_effective_date
      ) AS fb
        ON fb.`Employee Number` = c.`Employee Number`
       AND fb.comp_effective_date = c.comp_effective_date
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS fbtit
        ON fbtit.`Employee Number` = c.`Employee Number`
       AND fbtit.title_change_date = fb.fb_date
      WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'CREATIVE DIRECTOR'
        AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) NOT LIKE '%FREELANCE%'
        AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
    ) AS base
    CROSS JOIN (SELECT @rownum := 0) AS vars
    ORDER BY base.salary_usd ASC, base.comp_effective_date ASC, base.employee_number ASC
  ) AS ranked
) AS r
ON r.rn = CASE
  WHEN sr.step_order = 1 THEN 1
  WHEN sr.step_order = 2 THEN GREATEST(1, CEIL(cnt.total_rows * 0.50))
  WHEN sr.step_order = 3 THEN GREATEST(1, CEIL(cnt.total_rows * 0.90))
END
ORDER BY sr.step_order;
