-- Domo MySQL DataFlow (MySQL 5.7-compatible)
-- Output a report of comp rows where no title could be matched (neither ±15d nor fallback-before)

SELECT
  c.`Employee Number`,
  c.`First Name`,
  c.`Last Name`,
  c.`Division`,
  c.`Department`,
  c.`Job Title`                  AS `Comp Job Title (Original)`,
  c.comp_effective_date          AS `Comp Effective Date`,
  prior.prior_date               AS `Nearest Title Change (Before)`,
  prior_t.`Title`                AS `Nearest Title (Before)`,
  CASE WHEN prior.prior_date IS NULL THEN NULL ELSE DATEDIFF(c.comp_effective_date, prior.prior_date) END AS `Days From Prior`,
  nexts.next_date                AS `Nearest Title Change (After)`,
  next_t.`Title`                 AS `Nearest Title (After)`,
  CASE WHEN nexts.next_date IS NULL THEN NULL ELSE DATEDIFF(nexts.next_date, c.comp_effective_date) END AS `Days To Next`,
  CASE
    WHEN thc.th_count = 0 THEN 'no title history for employee'
    WHEN prior.prior_date IS NULL THEN CONCAT('only future titles; nearest +', DATEDIFF(nexts.next_date, c.comp_effective_date), 'd')
    WHEN nexts.next_date IS NULL THEN CONCAT('only older titles; nearest -', DATEDIFF(c.comp_effective_date, prior.prior_date), 'd')
    ELSE 'no title within ±15d and none before used as fallback'
  END AS `Reason`,
  c.`Work Email`                 AS `Work Email`,
  CONCAT_WS('; ',
    CASE
      WHEN c.`Work Email` IS NULL OR TRIM(c.`Work Email`) = '' THEN 'missing work email'
      ELSE NULL
    END,
    CASE
      WHEN c.`Work Email` IS NULL OR TRIM(c.`Work Email`) = '' THEN NULL
      WHEN NOT EXISTS (
        SELECT 1
        FROM `dataflow_schema`.`employee_org_units_dept_div_loc` ou_any
        WHERE LOWER(TRIM(ou_any.`Email`)) = LOWER(TRIM(c.`Work Email`))
      ) THEN 'no org-units for email'
      ELSE NULL
    END,
    CASE
      WHEN c.`Work Email` IS NULL OR TRIM(c.`Work Email`) = '' THEN NULL
      WHEN EXISTS (
        SELECT 1
        FROM `dataflow_schema`.`employee_org_units_dept_div_loc` ou_d
        WHERE LOWER(TRIM(ou_d.`Email`)) = LOWER(TRIM(c.`Work Email`))
          AND TRIM(ou_d.`Org Type`) IN ('Department','Departments')
          AND c.comp_effective_date BETWEEN DATE(ou_d.`Assignment Start Date`) AND COALESCE(DATE(ou_d.`Assignment End Date`), DATE('9999-12-31'))
      ) THEN NULL
      ELSE 'no Department covering comp date'
    END,
    CASE
      WHEN c.`Work Email` IS NULL OR TRIM(c.`Work Email`) = '' THEN NULL
      WHEN EXISTS (
        SELECT 1
        FROM `dataflow_schema`.`employee_org_units_dept_div_loc` ou_v
        WHERE LOWER(TRIM(ou_v.`Email`)) = LOWER(TRIM(c.`Work Email`))
          AND TRIM(ou_v.`Org Type`) IN ('Division','Divisions')
          AND c.comp_effective_date BETWEEN DATE(ou_v.`Assignment Start Date`) AND COALESCE(DATE(ou_v.`Assignment End Date`), DATE('9999-12-31'))
      ) THEN NULL
      ELSE 'no Division covering comp date'
    END,
    CASE
      WHEN c.`Work Email` IS NULL OR TRIM(c.`Work Email`) = '' THEN NULL
      WHEN EXISTS (
        SELECT 1
        FROM `dataflow_schema`.`employee_org_units_dept_div_loc` ou_o
        WHERE LOWER(TRIM(ou_o.`Email`)) = LOWER(TRIM(c.`Work Email`))
          AND TRIM(ou_o.`Org Type`) IN ('Office Location','Office Locations','Location','Locations','Office')
          AND c.comp_effective_date BETWEEN DATE(ou_o.`Assignment Start Date`) AND COALESCE(DATE(ou_o.`Assignment End Date`), DATE('9999-12-31'))
      ) THEN NULL
      ELSE 'no Office Location covering comp date'
    END
  ) AS `Org Units Notes`
FROM
  ( SELECT
      t1.*,
      COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
    FROM `namely_comp_data_history_w_notes` t1
    WHERE UPPER(t1.`Division`) = 'CONSULTING'
      AND DATE(t1.`Start Date`) >= '2016-01-01' ) AS c
LEFT JOIN (
  SELECT
    p.`Employee Number`, p.comp_effective_date,
    COALESCE(ob.match_date, af.match_date) AS chosen_date
  FROM
    ( SELECT DISTINCT
        COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
        `Employee Number`
      FROM `namely_comp_data_history_w_notes`
      WHERE UPPER(`Division`) = 'CONSULTING'
        AND DATE(`Start Date`) >= '2016-01-01' ) AS p
    LEFT JOIN (
      SELECT p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
      FROM ( SELECT DISTINCT
               COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
               `Employee Number`
             FROM `namely_comp_data_history_w_notes`
             WHERE UPPER(`Division`) = 'CONSULTING'
               AND DATE(`Start Date`) >= '2016-01-01' ) p2
      JOIN ( SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL ) th2
        ON th2.`Employee Number` = p2.`Employee Number`
      WHERE th2.title_change_date <= p2.comp_effective_date
        AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
      GROUP BY p2.`Employee Number`, p2.comp_effective_date
    ) ob
      ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
    LEFT JOIN (
      SELECT p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
      FROM ( SELECT DISTINCT
               COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
               `Employee Number`
             FROM `namely_comp_data_history_w_notes`
             WHERE UPPER(`Division`) = 'CONSULTING'
               AND DATE(`Start Date`) >= '2016-01-01' ) p3
      JOIN ( SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
             FROM `namely_title_history_data_aq`
             WHERE `Title` IS NOT NULL ) th3
        ON th3.`Employee Number` = p3.`Employee Number`
      WHERE th3.title_change_date >= p3.comp_effective_date
        AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
      GROUP BY p3.`Employee Number`, p3.comp_effective_date
    ) af
      ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
) chosen
  ON chosen.`Employee Number` = c.`Employee Number`
 AND chosen.comp_effective_date = c.comp_effective_date
LEFT JOIN (
  SELECT x.`Employee Number`, x.comp_effective_date, MAX(DATE(th.`Title Change Date`)) AS prior_date
  FROM ( SELECT DISTINCT
           COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
           `Employee Number`
         FROM `namely_comp_data_history_w_notes`
         WHERE UPPER(`Division`) = 'CONSULTING'
           AND DATE(`Start Date`) >= '2016-01-01' ) x
  LEFT JOIN `namely_title_history_data_aq` th
    ON th.`Employee Number` = x.`Employee Number`
   AND DATE(th.`Title Change Date`) <= x.comp_effective_date
  GROUP BY x.`Employee Number`, x.comp_effective_date
) prior
  ON prior.`Employee Number` = c.`Employee Number`
 AND prior.comp_effective_date = c.comp_effective_date
LEFT JOIN `namely_title_history_data_aq` prior_t
  ON prior_t.`Employee Number` = c.`Employee Number`
 AND DATE(prior_t.`Title Change Date`) = prior.prior_date
LEFT JOIN (
  SELECT x.`Employee Number`, x.comp_effective_date, MIN(DATE(th.`Title Change Date`)) AS next_date
  FROM ( SELECT DISTINCT
           COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
           `Employee Number`
         FROM `namely_comp_data_history_w_notes`
         WHERE UPPER(`Division`) = 'CONSULTING'
           AND DATE(`Start Date`) >= '2016-01-01' ) x
  LEFT JOIN `namely_title_history_data_aq` th
    ON th.`Employee Number` = x.`Employee Number`
   AND DATE(th.`Title Change Date`) >= x.comp_effective_date
  GROUP BY x.`Employee Number`, x.comp_effective_date
) nexts
  ON nexts.`Employee Number` = c.`Employee Number`
 AND nexts.comp_effective_date = c.comp_effective_date
LEFT JOIN `namely_title_history_data_aq` next_t
  ON next_t.`Employee Number` = c.`Employee Number`
 AND DATE(next_t.`Title Change Date`) = nexts.next_date
LEFT JOIN (
  SELECT `Employee Number`, COUNT(*) AS th_count
  FROM `namely_title_history_data_aq`
  GROUP BY `Employee Number`
) thc
  ON thc.`Employee Number` = c.`Employee Number`
WHERE chosen.chosen_date IS NULL;


