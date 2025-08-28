/* ----------------------------------------------------------------------------
   Multi-role compensation band calculation with outlier trimming
   Roles: Creative Director, Strategy Director, Program Director
   Range: 2016-01-01 to 2022-01-31

   Methodology:
   - Trim outliers per role by salary between ~5th and ~95th percentile (discrete)
   - Compute steps on trimmed data:
     Step 1: minimum
     Step 2: ~50th percentile (median)
     Step 3: ~90th percentile

   MySQL 5.7-compatible using user variables for ranking.
---------------------------------------------------------------------------- */

(
SELECT
  'Creative Director' AS `Role`,
  sr.step_order AS `Step Order`,
  sr.step_label AS `Step`,
  ROUND(r.salary_usd, 2) AS `Salary USD`,
  cnt.filtered_rows AS `Num Records`
FROM (
  SELECT 1 AS step_order, 'Step 1: lowest range' AS step_label, 0.00 AS pct
  UNION ALL
  SELECT 2 AS step_order, 'Step 2: ~50th percentile (trimmed)' AS step_label, 0.50 AS pct
  UNION ALL
  SELECT 3 AS step_order, 'Step 3: ~90th percentile (trimmed)' AS step_label, 0.90 AS pct
) AS sr
CROSS JOIN (
  SELECT COUNT(*) AS filtered_rows
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
    CROSS JOIN (
      SELECT
        /* 5th percentile salary */
        (SELECT r1.salary_usd FROM (
           SELECT CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
                  @p05 := @p05 + 1 AS rn
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
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS mtit2 ON mtit2.`Employee Number` = c2.`Employee Number` AND mtit2.title_change_date = ob.match_date
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS fbtit2 ON fbtit2.`Employee Number` = c2.`Employee Number`
           WHERE UPPER(TRIM(COALESCE(mtit2.`Title`, fbtit2.`Title`, c2.`Job Title`))) = 'CREATIVE DIRECTOR'
             AND UPPER(TRIM(c2.`Employee Type`)) = 'STAFF FULL TIME'
             AND UPPER(TRIM(c2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
             AND c2.`Salary` IS NOT NULL
             AND CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
             AND c2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
           CROSS JOIN (SELECT @p05 := 0) AS v05
           ORDER BY salary_usd ASC, c2.comp_effective_date ASC, c2.`Employee Number` ASC
         ) AS r1 WHERE r1.rn = GREATEST(1, CEIL((SELECT COUNT(*) FROM (
           SELECT 1 FROM (
             SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
             FROM `namely_comp_data_history_w_notes` t1
           ) AS c3
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS mtit3 ON mtit3.`Employee Number` = c3.`Employee Number`
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS fbtit3 ON fbtit3.`Employee Number` = c3.`Employee Number`
           WHERE UPPER(TRIM(COALESCE(mtit3.`Title`, fbtit3.`Title`, c3.`Job Title`))) = 'CREATIVE DIRECTOR'
             AND UPPER(TRIM(c3.`Employee Type`)) = 'STAFF FULL TIME'
             AND UPPER(TRIM(c3.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
             AND c3.`Salary` IS NOT NULL
             AND CAST(REPLACE(REPLACE(c3.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
             AND c3.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
         ) z) * 0.05))) AS p05_salary,
        /* 95th percentile salary */
        (SELECT r2.salary_usd FROM (
           SELECT CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
                  @p95 := @p95 + 1 AS rn
           FROM (
             SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
             FROM `namely_comp_data_history_w_notes` t1
           ) AS c4
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS mtit4 ON mtit4.`Employee Number` = c4.`Employee Number`
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS fbtit4 ON fbtit4.`Employee Number` = c4.`Employee Number`
           WHERE UPPER(TRIM(COALESCE(mtit4.`Title`, fbtit4.`Title`, c4.`Job Title`))) = 'CREATIVE DIRECTOR'
             AND UPPER(TRIM(c4.`Employee Type`)) = 'STAFF FULL TIME'
             AND UPPER(TRIM(c4.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
             AND c4.`Salary` IS NOT NULL
             AND CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
             AND c4.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
           CROSS JOIN (SELECT @p95 := 0) AS v95
           ORDER BY salary_usd ASC, c4.comp_effective_date ASC, c4.`Employee Number` ASC
         ) AS r2 WHERE r2.rn = GREATEST(1, CEIL((SELECT COUNT(*) FROM (
           SELECT 1 FROM (
             SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
             FROM `namely_comp_data_history_w_notes` t1
           ) AS c5
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS mtit5 ON mtit5.`Employee Number` = c5.`Employee Number`
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS fbtit5 ON fbtit5.`Employee Number` = c5.`Employee Number`
           WHERE UPPER(TRIM(COALESCE(mtit5.`Title`, fbtit5.`Title`, c5.`Job Title`))) = 'CREATIVE DIRECTOR'
             AND UPPER(TRIM(c5.`Employee Type`)) = 'STAFF FULL TIME'
             AND UPPER(TRIM(c5.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
             AND c5.`Salary` IS NOT NULL
             AND CAST(REPLACE(REPLACE(c5.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
             AND c5.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
         ) z2) * 0.95))) AS p95_salary
    ) AS bounds
    WHERE CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) BETWEEN bounds.p05_salary AND bounds.p95_salary
  ) AS trimmed_count
) AS cnt
LEFT JOIN (
  SELECT ranked_filtered.rn, ranked_filtered.salary_usd
  FROM (
    SELECT base.salary_usd, @rf := @rf + 1 AS rn
    FROM (
      SELECT CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
             c.comp_effective_date AS comp_effective_date,
             c.`Employee Number` AS employee_number
      FROM (
        SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
        FROM `namely_comp_data_history_w_notes` t1
      ) AS c
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS mtit ON mtit.`Employee Number` = c.`Employee Number`
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number`
      WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'CREATIVE DIRECTOR'
        AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) BETWEEN (
          SELECT b1.p05_salary FROM (
            SELECT r1.salary_usd AS p05_salary FROM (
              SELECT CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
                     @pp05 := @pp05 + 1 AS rn
              FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) AS c2
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS mtit2 ON mtit2.`Employee Number` = c2.`Employee Number`
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS fbtit2 ON fbtit2.`Employee Number` = c2.`Employee Number`
              WHERE UPPER(TRIM(COALESCE(mtit2.`Title`, fbtit2.`Title`, c2.`Job Title`))) = 'CREATIVE DIRECTOR'
                AND UPPER(TRIM(c2.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(c2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND c2.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND c2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
              CROSS JOIN (SELECT @pp05 := 0) AS vv05
              ORDER BY salary_usd ASC, c2.comp_effective_date ASC, c2.`Employee Number` ASC
            ) AS r1
            WHERE r1.rn = GREATEST(1, CEIL((SELECT COUNT(*) FROM (
              SELECT 1 FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) AS cc
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS mt ON mt.`Employee Number` = cc.`Employee Number`
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS fb ON fb.`Employee Number` = cc.`Employee Number`
              WHERE UPPER(TRIM(COALESCE(mt.`Title`, fb.`Title`, cc.`Job Title`))) = 'CREATIVE DIRECTOR'
                AND UPPER(TRIM(cc.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(cc.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND cc.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(cc.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND cc.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            ) zc) * 0.05))
        ) AND (
          SELECT b2.p95_salary FROM (
            SELECT r2.salary_usd AS p95_salary FROM (
              SELECT CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
                     @pp95 := @pp95 + 1 AS rn
              FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) AS c4
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` Is NOT NULL
              ) AS mtit4 ON mtit4.`Employee Number` = c4.`Employee Number`
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS fbtit4 ON fbtit4.`Employee Number` = c4.`Employee Number`
              WHERE UPPER(TRIM(COALESCE(mtit4.`Title`, fbtit4.`Title`, c4.`Job Title`))) = 'CREATIVE DIRECTOR'
                AND UPPER(TRIM(c4.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(c4.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND c4.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND c4.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
              CROSS JOIN (SELECT @pp95 := 0) AS vv95
              ORDER BY salary_usd ASC, c4.comp_effective_date ASC, c4.`Employee Number` ASC
            ) AS r2
            WHERE r2.rn = GREATEST(1, CEIL((SELECT COUNT(*) FROM (
              SELECT 1 FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) AS cc2
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS mt2 ON mt2.`Employee Number` = cc2.`Employee Number`
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS fb2 ON fb2.`Employee Number` = cc2.`Employee Number`
              WHERE UPPER(TRIM(COALESCE(mt2.`Title`, fb2.`Title`, cc2.`Job Title`))) = 'CREATIVE DIRECTOR'
                AND UPPER(TRIM(cc2.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(cc2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND cc2.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(cc2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND cc2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            ) zc2) * 0.95))
        )
    ) AS base
    CROSS JOIN (SELECT @rf := 0) AS v_rf
    ORDER BY base.salary_usd ASC, base.comp_effective_date ASC, base.employee_number ASC
  ) AS ranked_filtered
) AS r
ON r.rn = CASE
  WHEN sr.step_order = 1 THEN 1
  WHEN sr.step_order = 2 THEN GREATEST(1, CEIL(cnt.filtered_rows * 0.50))
  WHEN sr.step_order = 3 THEN GREATEST(1, CEIL(cnt.filtered_rows * 0.90))
END
)
UNION ALL
(
SELECT
  'Strategy Director' AS `Role`,
  sr.step_order AS `Step Order`,
  sr.step_label AS `Step`,
  ROUND(r.salary_usd, 2) AS `Salary USD`,
  cnt.filtered_rows AS `Num Records`
FROM (
  SELECT 1 AS step_order, 'Step 1: lowest range' AS step_label, 0.00 AS pct
  UNION ALL
  SELECT 2 AS step_order, 'Step 2: ~50th percentile (trimmed)' AS step_label, 0.50 AS pct
  UNION ALL
  SELECT 3 AS step_order, 'Step 3: ~90th percentile (trimmed)' AS step_label, 0.90 AS pct
) AS sr
CROSS JOIN (
  SELECT COUNT(*) AS filtered_rows
  FROM (
    SELECT 1
    FROM (
      SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
      FROM `namely_comp_data_history_w_notes` t1
    ) AS c
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS mtit ON mtit.`Employee Number` = c.`Employee Number`
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number`
    CROSS JOIN (
      SELECT
        (SELECT r1.salary_usd FROM (
           SELECT CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
                  @s05 := @s05 + 1 AS rn
           FROM (
             SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
             FROM `namely_comp_data_history_w_notes` t1
           ) AS c2
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS mtit2 ON mtit2.`Employee Number` = c2.`Employee Number`
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS fbtit2 ON fbtit2.`Employee Number` = c2.`Employee Number`
           WHERE UPPER(TRIM(COALESCE(mtit2.`Title`, fbtit2.`Title`, c2.`Job Title`))) = 'STRATEGY DIRECTOR'
             AND UPPER(TRIM(c2.`Employee Type`)) = 'STAFF FULL TIME'
             AND UPPER(TRIM(c2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
             AND c2.`Salary` IS NOT NULL
             AND CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
             AND c2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
           CROSS JOIN (SELECT @s05 := 0) AS v05
           ORDER BY salary_usd ASC, c2.comp_effective_date ASC, c2.`Employee Number` ASC
         ) AS r1 WHERE r1.rn = GREATEST(1, CEIL((SELECT COUNT(*) FROM (
           SELECT 1 FROM (
             SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
             FROM `namely_comp_data_history_w_notes` t1
           ) AS c3
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS mtit3 ON mtit3.`Employee Number` = c3.`Employee Number`
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS fbtit3 ON fbtit3.`Employee Number` = c3.`Employee Number`
           WHERE UPPER(TRIM(COALESCE(mtit3.`Title`, fbtit3.`Title`, c3.`Job Title`))) = 'STRATEGY DIRECTOR'
             AND UPPER(TRIM(c3.`Employee Type`)) = 'STAFF FULL TIME'
             AND UPPER(TRIM(c3.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
             AND c3.`Salary` IS NOT NULL
             AND CAST(REPLACE(REPLACE(c3.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
             AND c3.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
         ) z) * 0.05))) AS p05_salary,
        (SELECT r2.salary_usd FROM (
           SELECT CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
                  @s95 := @s95 + 1 AS rn
           FROM (
             SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
             FROM `namely_comp_data_history_w_notes` t1
           ) AS c4
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS mtit4 ON mtit4.`Employee Number` = c4.`Employee Number`
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS fbtit4 ON fbtit4.`Employee Number` = c4.`Employee Number`
           WHERE UPPER(TRIM(COALESCE(mtit4.`Title`, fbtit4.`Title`, c4.`Job Title`))) = 'STRATEGY DIRECTOR'
             AND UPPER(TRIM(c4.`Employee Type`)) = 'STAFF FULL TIME'
             AND UPPER(TRIM(c4.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
             AND c4.`Salary` IS NOT NULL
             AND CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
             AND c4.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
           CROSS JOIN (SELECT @s95 := 0) AS v95
           ORDER BY salary_usd ASC, c4.comp_effective_date ASC, c4.`Employee Number` ASC
         ) AS r2 WHERE r2.rn = GREATEST(1, CEIL((SELECT COUNT(*) FROM (
           SELECT 1 FROM (
             SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
             FROM `namely_comp_data_history_w_notes` t1
           ) AS c5
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS mtit5 ON mtit5.`Employee Number` = c5.`Employee Number`
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS fbtit5 ON fbtit5.`Employee Number` = c5.`Employee Number`
           WHERE UPPER(TRIM(COALESCE(mtit5.`Title`, fbtit5.`Title`, c5.`Job Title`))) = 'STRATEGY DIRECTOR'
             AND UPPER(TRIM(c5.`Employee Type`)) = 'STAFF FULL TIME'
             AND UPPER(TRIM(c5.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
             AND c5.`Salary` IS NOT NULL
             AND CAST(REPLACE(REPLACE(c5.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
             AND c5.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
         ) z2) * 0.95))) AS p95_salary
    ) AS bounds
    WHERE CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) BETWEEN bounds.p05_salary AND bounds.p95_salary
  ) AS trimmed_count
) AS cnt
LEFT JOIN (
  SELECT ranked_filtered.rn, ranked_filtered.salary_usd
  FROM (
    SELECT base.salary_usd, @rf2 := @rf2 + 1 AS rn
    FROM (
      SELECT CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
             c.comp_effective_date AS comp_effective_date,
             c.`Employee Number` AS employee_number
      FROM (
        SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
        FROM `namely_comp_data_history_w_notes` t1
      ) AS c
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS mtit ON mtit.`Employee Number` = c.`Employee Number`
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number`
      WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'STRATEGY DIRECTOR'
        AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) BETWEEN (
          SELECT b1.p05_salary FROM (
            SELECT r1.salary_usd AS p05_salary FROM (
              SELECT CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
                     @ps05 := @ps05 + 1 AS rn
              FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) AS c2
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS mtit2 ON mtit2.`Employee Number` = c2.`Employee Number`
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS fbtit2 ON fbtit2.`Employee Number` = c2.`Employee Number`
              WHERE UPPER(TRIM(COALESCE(mtit2.`Title`, fbtit2.`Title`, c2.`Job Title`))) = 'STRATEGY DIRECTOR'
                AND UPPER(TRIM(c2.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(c2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND c2.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND c2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
              CROSS JOIN (SELECT @ps05 := 0) AS vv05
              ORDER BY salary_usd ASC, c2.comp_effective_date ASC, c2.`Employee Number` ASC
            ) AS r1
            WHERE r1.rn = GREATEST(1, CEIL((SELECT COUNT(*) FROM (
              SELECT 1 FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) AS cc
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS mt ON mt.`Employee Number` = cc.`Employee Number`
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) As fb ON fb.`Employee Number` = cc.`Employee Number`
              WHERE UPPER(TRIM(COALESCE(mt.`Title`, fb.`Title`, cc.`Job Title`))) = 'STRATEGY DIRECTOR'
                AND UPPER(TRIM(cc.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(cc.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND cc.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(cc.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND cc.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            ) zc) * 0.05))
        ) AND (
          SELECT b2.p95_salary FROM (
            SELECT r2.salary_usd AS p95_salary FROM (
              SELECT CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
                     @ps95 := @ps95 + 1 AS rn
              FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) AS c4
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` Is NOT NULL
              ) AS mtit4 ON mtit4.`Employee Number` = c4.`Employee Number`
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS fbtit4 ON fbtit4.`Employee Number` = c4.`Employee Number`
              WHERE UPPER(TRIM(COALESCE(mtit4.`Title`, fbtit4.`Title`, c4.`Job Title`))) = 'STRATEGY DIRECTOR'
                AND UPPER(TRIM(c4.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(c4.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND c4.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND c4.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
              CROSS JOIN (SELECT @ps95 := 0) AS vv95
              ORDER BY salary_usd ASC, c4.comp_effective_date ASC, c4.`Employee Number` ASC
            ) AS r2
            WHERE r2.rn = GREATEST(1, CEIL((SELECT COUNT(*) FROM (
              SELECT 1 FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) AS cc2
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS mt2 ON mt2.`Employee Number` = cc2.`Employee Number`
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS fb2 ON fb2.`Employee Number` = cc2.`Employee Number`
              WHERE UPPER(TRIM(COALESCE(mt2.`Title`, fb2.`Title`, cc2.`Job Title`))) = 'STRATEGY DIRECTOR'
                AND UPPER(TRIM(cc2.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(cc2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND cc2.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(cc2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND cc2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            ) zc2) * 0.95))
        )
    ) AS base
    CROSS JOIN (SELECT @rf2 := 0) AS v_rf2
    ORDER BY base.salary_usd ASC, base.comp_effective_date ASC, base.employee_number ASC
  ) AS ranked_filtered
) AS r
ON r.rn = CASE
  WHEN sr.step_order = 1 THEN 1
  WHEN sr.step_order = 2 THEN GREATEST(1, CEIL(cnt.filtered_rows * 0.50))
  WHEN sr.step_order = 3 THEN GREATEST(1, CEIL(cnt.filtered_rows * 0.90))
END
)
UNION ALL
(
SELECT
  'Program Director' AS `Role`,
  sr.step_order AS `Step Order`,
  sr.step_label AS `Step`,
  ROUND(r.salary_usd, 2) AS `Salary USD`,
  cnt.filtered_rows AS `Num Records`
FROM (
  SELECT 1 AS step_order, 'Step 1: lowest range' AS step_label, 0.00 AS pct
  UNION ALL
  SELECT 2 AS step_order, 'Step 2: ~50th percentile (trimmed)' AS step_label, 0.50 AS pct
  UNION ALL
  SELECT 3 AS step_order, 'Step 3: ~90th percentile (trimmed)' AS step_label, 0.90 AS pct
) AS sr
CROSS JOIN (
  SELECT COUNT(*) AS filtered_rows
  FROM (
    SELECT 1
    FROM (
      SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
      FROM `namely_comp_data_history_w_notes` t1
    ) AS c
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS mtit ON mtit.`Employee Number` = c.`Employee Number`
    LEFT JOIN (
      SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
      FROM `namely_title_history_data_aq`
      WHERE `Title` IS NOT NULL
    ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number`
    CROSS JOIN (
      SELECT
        (SELECT r1.salary_usd FROM (
           SELECT CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
                  @pgr05 := @pgr05 + 1 AS rn
           FROM (
             SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
             FROM `namely_comp_data_history_w_notes` t1
           ) AS c2
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS mtit2 ON mtit2.`Employee Number` = c2.`Employee Number`
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS fbtit2 ON fbtit2.`Employee Number` = c2.`Employee Number`
           WHERE UPPER(TRIM(COALESCE(mtit2.`Title`, fbtit2.`Title`, c2.`Job Title`))) = 'PROGRAM DIRECTOR'
             AND UPPER(TRIM(c2.`Employee Type`)) = 'STAFF FULL TIME'
             AND UPPER(TRIM(c2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
             AND c2.`Salary` IS NOT NULL
             AND CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
             AND c2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
           CROSS JOIN (SELECT @pgr05 := 0) AS v05
           ORDER BY salary_usd ASC, c2.comp_effective_date ASC, c2.`Employee Number` ASC
         ) AS r1 WHERE r1.rn = GREATEST(1, CEIL((SELECT COUNT(*) FROM (
           SELECT 1 FROM (
             SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
             FROM `namely_comp_data_history_w_notes` t1
           ) AS c3
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS mtit3 ON mtit3.`Employee Number` = c3.`Employee Number`
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS fbtit3 ON fbtit3.`Employee Number` = c3.`Employee Number`
           WHERE UPPER(TRIM(COALESCE(mtit3.`Title`, fbtit3.`Title`, c3.`Job Title`))) = 'PROGRAM DIRECTOR'
             AND UPPER(TRIM(c3.`Employee Type`)) = 'STAFF FULL TIME'
             AND UPPER(TRIM(c3.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
             AND c3.`Salary` IS NOT NULL
             AND CAST(REPLACE(REPLACE(c3.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
             AND c3.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
         ) z) * 0.05))) AS p05_salary,
        (SELECT r2.salary_usd FROM (
           SELECT CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
                  @pgr95 := @pgr95 + 1 AS rn
           FROM (
             SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
             FROM `namely_comp_data_history_w_notes` t1
           ) AS c4
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS mtit4 ON mtit4.`Employee Number` = c4.`Employee Number`
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS fbtit4 ON fbtit4.`Employee Number` = c4.`Employee Number`
           WHERE UPPER(TRIM(COALESCE(mtit4.`Title`, fbtit4.`Title`, c4.`Job Title`))) = 'PROGRAM DIRECTOR'
             AND UPPER(TRIM(c4.`Employee Type`)) = 'STAFF FULL TIME'
             AND UPPER(TRIM(c4.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
             AND c4.`Salary` IS NOT NULL
             AND CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
             AND c4.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
           CROSS JOIN (SELECT @pgr95 := 0) AS v95
           ORDER BY salary_usd ASC, c4.comp_effective_date ASC, c4.`Employee Number` ASC
         ) AS r2 WHERE r2.rn = GREATEST(1, CEIL((SELECT COUNT(*) FROM (
           SELECT 1 FROM (
             SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
             FROM `namely_comp_data_history_w_notes` t1
           ) AS c5
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS mtit5 ON mtit5.`Employee Number` = c5.`Employee Number`
           LEFT JOIN (
             SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL
           ) AS fbtit5 ON fbtit5.`Employee Number` = c5.`Employee Number`
           WHERE UPPER(TRIM(COALESCE(mtit5.`Title`, fbtit5.`Title`, c5.`Job Title`))) = 'PROGRAM DIRECTOR'
             AND UPPER(TRIM(c5.`Employee Type`)) = 'STAFF FULL TIME'
             AND UPPER(TRIM(c5.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
             AND c5.`Salary` IS NOT NULL
             AND CAST(REPLACE(REPLACE(c5.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
             AND c5.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
         ) z2) * 0.95))) AS p95_salary
    ) AS bounds
    WHERE CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) BETWEEN bounds.p05_salary AND bounds.p95_salary
  ) AS trimmed_count
) AS cnt
LEFT JOIN (
  SELECT ranked_filtered.rn, ranked_filtered.salary_usd
  FROM (
    SELECT base.salary_usd, @rf3 := @rf3 + 1 AS rn
    FROM (
      SELECT CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
             c.comp_effective_date AS comp_effective_date,
             c.`Employee Number` AS employee_number
      FROM (
        SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
        FROM `namely_comp_data_history_w_notes` t1
      ) AS c
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS mtit ON mtit.`Employee Number` = c.`Employee Number`
      LEFT JOIN (
        SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS fbtit ON fbtit.`Employee Number` = c.`Employee Number`
      WHERE UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PROGRAM DIRECTOR'
        AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
        AND UPPER(TRIM(c.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
        AND c.`Salary` IS NOT NULL
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
        AND c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
        AND CAST(REPLACE(REPLACE(c.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) BETWEEN (
          SELECT b1.p05_salary FROM (
            SELECT r1.salary_usd AS p05_salary FROM (
              SELECT CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
                     @pgs05 := @pgs05 + 1 AS rn
              FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) AS c2
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS mtit2 ON mtit2.`Employee Number` = c2.`Employee Number`
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS fbtit2 ON fbtit2.`Employee Number` = c2.`Employee Number`
              WHERE UPPER(TRIM(COALESCE(mtit2.`Title`, fbtit2.`Title`, c2.`Job Title`))) = 'PROGRAM DIRECTOR'
                AND UPPER(TRIM(c2.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(c2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND c2.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(c2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND c2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
              CROSS JOIN (SELECT @pgs05 := 0) AS vv05
              ORDER BY salary_usd ASC, c2.comp_effective_date ASC, c2.`Employee Number` ASC
            ) AS r1
            WHERE r1.rn = GREATEST(1, CEIL((SELECT COUNT(*) FROM (
              SELECT 1 FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) AS cc
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS mt ON mt.`Employee Number` = cc.`Employee Number`
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) As fb ON fb.`Employee Number` = cc.`Employee Number`
              WHERE UPPER(TRIM(COALESCE(mt.`Title`, fb.`Title`, cc.`Job Title`))) = 'PROGRAM DIRECTOR'
                AND UPPER(TRIM(cc.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(cc.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND cc.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(cc.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND cc.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            ) zc) * 0.05))
        ) AND (
          SELECT b2.p95_salary FROM (
            SELECT r2.salary_usd AS p95_salary FROM (
              SELECT CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) AS salary_usd,
                     @pgs95 := @pgs95 + 1 AS rn
              FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) AS c4
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS mtit4 ON mtit4.`Employee Number` = c4.`Employee Number`
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS fbtit4 ON fbtit4.`Employee Number` = c4.`Employee Number`
              WHERE UPPER(TRIM(COALESCE(mtit4.`Title`, fbtit4.`Title`, c4.`Job Title`))) = 'PROGRAM DIRECTOR'
                AND UPPER(TRIM(c4.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(c4.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND c4.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(c4.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND c4.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
              CROSS JOIN (SELECT @pgs95 := 0) AS vv95
              ORDER BY salary_usd ASC, c4.comp_effective_date ASC, c4.`Employee Number` ASC
            ) AS r2
            WHERE r2.rn = GREATEST(1, CEIL((SELECT COUNT(*) FROM (
              SELECT 1 FROM (
                SELECT t1.*, COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
                FROM `namely_comp_data_history_w_notes` t1
              ) AS cc2
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS mt2 ON mt2.`Employee Number` = cc2.`Employee Number`
              LEFT JOIN (
                SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
                FROM `namely_title_history_data_aq`
                WHERE `Title` IS NOT NULL
              ) AS fb2 ON fb2.`Employee Number` = cc2.`Employee Number`
              WHERE UPPER(TRIM(COALESCE(mt2.`Title`, fb2.`Title`, cc2.`Job Title`))) = 'PROGRAM DIRECTOR'
                AND UPPER(TRIM(cc2.`Employee Type`)) = 'STAFF FULL TIME'
                AND UPPER(TRIM(cc2.`Type`)) IN ('YEARLY','SALARY','SALARIED','ANNUAL')
                AND cc2.`Salary` IS NOT NULL
                AND CAST(REPLACE(REPLACE(cc2.`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) > 0
                AND cc2.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
            ) zc2) * 0.95))
        )
    ) AS base
    CROSS JOIN (SELECT @rf3 := 0) AS v_rf3
    ORDER BY base.salary_usd ASC, base.comp_effective_date ASC, base.employee_number ASC
  ) AS ranked_filtered
) AS r
ON r.rn = CASE
  WHEN sr.step_order = 1 THEN 1
  WHEN sr.step_order = 2 THEN GREATEST(1, CEIL(cnt.filtered_rows * 0.50))
  WHEN sr.step_order = 3 THEN GREATEST(1, CEIL(cnt.filtered_rows * 0.90))
END
)
ORDER BY `Role`, `Step Order`;
