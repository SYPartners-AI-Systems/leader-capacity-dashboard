SELECT
  -- Title mapping (unchanged)
  c.`Salary Currency`,
  COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)        AS `Job Title`,
  COALESCE(chosen.chosen_date, fb.fb_date)                     AS `Title Change Date (Used)`,
  c.comp_effective_date                                        AS `Comp Effective Date`,

  -- Org Units: Office Location + dates
  office_ou.`Office_Location`                                  AS `Office Location`,
  office_ou.start_date                                         AS `Office Location Start Date`,
  office_ou.end_date                                           AS `Office Location End Date`,

  -- Org Units: Department + dates
  dept_ou.`Department`                                         AS `Department`,
  dept_ou.start_date                                           AS `Department Start Date`,
  dept_ou.end_date                                             AS `Department End Date`,

  -- Org Units: Division + dates
  div_ou.`Division`                                            AS `Division`,
  div_ou.start_date                                            AS `Division Start Date`,
  div_ou.end_date                                              AS `Division End Date`,

  -- Other comp fields
  c.`Salary Notes`,
  c.`Start Date` AS `Hire Date`,
  c.`Employee Number`,
  c.`Level`,
  c.`Salary End Date`,
  c.`Step`,
  c.`Salary Start Date`,
  c.`User Status`,
  c.`Last Name`,
  c.`Salary`,
  c.`Type`,
  c.`Employee Type`,
  c.`First Name`,
  tmeta.`Preferred First Name` AS `Preferred First Name`,
  tmeta.`Termination Date` AS `Termination Date`

FROM (
  SELECT
    t1.*,
    COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
  FROM `namely_comp_data_history_w_notes` t1
  WHERE UPPER(t1.`Division`) = 'CONSULTING'
    AND DATE(t1.`Start Date`) >= '2016-01-01'
) AS c

/* ---------- Title matching: prefer on/before ≤15d, else after ≤15d ---------- */
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
    WHERE UPPER(`Division`) = 'CONSULTING'
      AND DATE(`Start Date`) >= '2016-01-01'
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
      WHERE UPPER(`Division`) = 'CONSULTING'
        AND DATE(`Start Date`) >= '2016-01-01'
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
      WHERE UPPER(`Division`) = 'CONSULTING'
        AND DATE(`Start Date`) >= '2016-01-01'
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

/* Title text for the chosen date */
LEFT JOIN (
  SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
  FROM `namely_title_history_data_aq`
  WHERE `Title` IS NOT NULL
) AS mtit
  ON mtit.`Employee Number` = c.`Employee Number`
 AND mtit.title_change_date = chosen.chosen_date

/* Fallback title: latest prior to comp date (no 15d limit) */
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
    WHERE UPPER(`Division`) = 'CONSULTING'
      AND DATE(`Start Date`) >= '2016-01-01'
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

/* Employee meta fields: Preferred First Name, Termination Date */
LEFT JOIN (
  SELECT
    `Employee Number`,
    MAX(`Termination Date`) AS `Termination Date`,
    MAX(`Preferred First Name`) AS `Preferred First Name`
  FROM `namely_title_history_data_aq`
  GROUP BY `Employee Number`
) AS tmeta
  ON tmeta.`Employee Number` = c.`Employee Number`

/* ---------- Org Units by type, matched independently to comp date ---------- */

/* Department match window: choose the latest start_date whose range covers comp date */
LEFT JOIN (
  SELECT
    p.`Work Email` AS work_email,
    p.comp_effective_date,
    MAX(r.start_date) AS matched_start_date
  FROM (
    SELECT DISTINCT
      LOWER(TRIM(`Work Email`)) AS `Work Email`,
      COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date
    FROM `namely_comp_data_history_w_notes`
    WHERE UPPER(`Division`) = 'CONSULTING'
      AND DATE(`Start Date`) >= '2016-01-01'
  ) AS p
  JOIN (
    SELECT
      LOWER(TRIM(`Email`)) AS email,
      DATE(`Assignment Start Date`) AS start_date,
      COALESCE(DATE(`Assignment End Date`), DATE('9999-12-31')) AS end_date
    FROM `dataflow_schema`.`employee_org_units_dept_div_loc`
    WHERE TRIM(`Org Type`) IN ('Department','Departments')
  ) AS r
    ON LOWER(TRIM(p.`Work Email`)) = r.email
  WHERE p.comp_effective_date BETWEEN r.start_date AND r.end_date
  GROUP BY p.`Work Email`, p.comp_effective_date
) AS dept_match
  ON LOWER(TRIM(c.`Work Email`)) = LOWER(TRIM(dept_match.work_email))
 AND c.comp_effective_date      = dept_match.comp_effective_date

/* Department values (output NULL end_date if absent) */
LEFT JOIN (
  SELECT
    LOWER(TRIM(`Email`)) AS email,
    DATE(`Assignment Start Date`) AS start_date,
    DATE(`Assignment End Date`)  AS end_date,      -- leave NULL if missing
    `Org Unit`                   AS `Department`
  FROM `dataflow_schema`.`employee_org_units_dept_div_loc`
  WHERE TRIM(`Org Type`) IN ('Department','Departments')
) AS dept_ou
  ON dept_ou.email      = LOWER(TRIM(c.`Work Email`))
 AND dept_ou.start_date = dept_match.matched_start_date

/* Office Location match window */
LEFT JOIN (
  SELECT
    p.`Work Email` AS work_email,
    p.comp_effective_date,
    MAX(r.start_date) AS matched_start_date
  FROM (
    SELECT DISTINCT
      LOWER(TRIM(`Work Email`)) AS `Work Email`,
      COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date
    FROM `namely_comp_data_history_w_notes`
    WHERE UPPER(`Division`) = 'CONSULTING'
      AND DATE(`Start Date`) >= '2016-01-01'
  ) AS p
  JOIN (
    SELECT
      LOWER(TRIM(`Email`)) AS email,
      DATE(`Assignment Start Date`) AS start_date,
      COALESCE(DATE(`Assignment End Date`), DATE('9999-12-31')) AS end_date
    FROM `dataflow_schema`.`employee_org_units_dept_div_loc`
    WHERE TRIM(`Org Type`) IN ('Office Location','Office Locations','Location','Locations','Office')
  ) AS r
    ON LOWER(TRIM(p.`Work Email`)) = r.email
  WHERE p.comp_effective_date BETWEEN r.start_date AND r.end_date
  GROUP BY p.`Work Email`, p.comp_effective_date
) AS office_match
  ON LOWER(TRIM(c.`Work Email`)) = LOWER(TRIM(office_match.work_email))
 AND c.comp_effective_date       = office_match.comp_effective_date

/* Office Location values (output NULL end_date if absent) */
LEFT JOIN (
  SELECT
    LOWER(TRIM(`Email`)) AS email,
    DATE(`Assignment Start Date`) AS start_date,
    DATE(`Assignment End Date`)  AS end_date,      -- leave NULL if missing
    `Org Unit`                   AS `Office_Location`
  FROM `dataflow_schema`.`employee_org_units_dept_div_loc`
  WHERE TRIM(`Org Type`) IN ('Office Location','Office Locations','Location','Locations','Office')
) AS office_ou
  ON office_ou.email      = LOWER(TRIM(c.`Work Email`))
 AND office_ou.start_date = office_match.matched_start_date

/* Division match window */
LEFT JOIN (
  SELECT
    p.`Work Email` AS work_email,
    p.comp_effective_date,
    MAX(r.start_date) AS matched_start_date
  FROM (
    SELECT DISTINCT
      LOWER(TRIM(`Work Email`)) AS `Work Email`,
      COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date
    FROM `namely_comp_data_history_w_notes`
    WHERE UPPER(`Division`) = 'CONSULTING'
      AND DATE(`Start Date`) >= '2016-01-01'
  ) AS p
  JOIN (
    SELECT
      LOWER(TRIM(`Email`)) AS email,
      DATE(`Assignment Start Date`) AS start_date,
      COALESCE(DATE(`Assignment End Date`), DATE('9999-12-31')) AS end_date
    FROM `dataflow_schema`.`employee_org_units_dept_div_loc`
    WHERE TRIM(`Org Type`) IN ('Division','Divisions')
  ) AS r
    ON LOWER(TRIM(p.`Work Email`)) = r.email
  WHERE p.comp_effective_date BETWEEN r.start_date AND r.end_date
  GROUP BY p.`Work Email`, p.comp_effective_date
) AS div_match
  ON LOWER(TRIM(c.`Work Email`)) = LOWER(TRIM(div_match.work_email))
 AND c.comp_effective_date       = div_match.comp_effective_date

/* Division values (output NULL end_date if absent) */
LEFT JOIN (
  SELECT
    LOWER(TRIM(`Email`)) AS email,
    DATE(`Assignment Start Date`) AS start_date,
    DATE(`Assignment End Date`)  AS end_date,      -- leave NULL if missing
    `Org Unit`                   AS `Division`
  FROM `dataflow_schema`.`employee_org_units_dept_div_loc`
  WHERE TRIM(`Org Type`) IN ('Division','Divisions')
) AS div_ou
  ON div_ou.email      = LOWER(TRIM(c.`Work Email`))
 AND div_ou.start_date = div_match.matched_start_date
;
