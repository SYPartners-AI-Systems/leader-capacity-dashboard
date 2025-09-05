SELECT
  -- Reordered columns as requested
  c.`Employee Type`,
  c.`User Status`,
  div_ou.`Division`                                            AS `Division`,
  dept_ou.`Department`                                         AS `Department`,
  COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)        AS `Job Title`,
  CASE
    /* Salary-specific override: $250k -> Partner/SVP */
    WHEN c.`Salary` = 250000 THEN 'Partner/SVP'
    /* 2016-01-01 to 2022-01-31: salary-only mapping via department philosophy for Partner/Principal titles only */
    WHEN c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
      AND (
        UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PARTNER%'
        OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PRINCIPAL%'
      )
      AND ph_dept_pre.ph_level IS NOT NULL
      THEN ph_dept_pre.ph_level
    /* Salary-based Executive override: $350k+ up to $499,999 */
    WHEN c.`Salary` BETWEEN 349000 AND 499999 THEN 'Executive'
    WHEN c.`Employee Number` = 'EMP-000635'
      AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
        'VENTURE PARTNER & EXECUTIVE DIRECTOR, MIDDLE EAST',
        'EXECUTIVE DIRECTOR, MIDDLE EAST'
      )
      THEN 'Executive'
    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
        'PARTNER & HEAD OF STRATEGY TEAM',
        'PRINCIPAL, STRATEGY',
        'PRINCIPAL, DESIGN',
        'PRINCIPAL & HEAD OF DESIGN TEAM',
        'PRINCIPAL & HEAD OF PROGRAM MANAGEMENT TEAM',
        'PRINCIPAL, PROGRAM MANAGEMENT'
      )
      THEN CASE
        WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'PARTNER%' THEN 'Partner/SVP'
        WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE 'PRINCIPAL%' THEN 'Principal/VP'
      END
    WHEN c.comp_effective_date = latest_effective.latest_comp_effective_date
      AND NULLIF(TRIM(c.`Level`), '') IS NOT NULL
      THEN TRIM(c.`Level`)
    ELSE COALESCE(ph_title_dept.ph_level, ph_title_any.ph_level, ph_dept_pre.ph_level)
  END                                                   AS `Level`,
  CONCAT(
    'Step ',
    TRIM(REPLACE(UPPER(
      CASE
        /* Salary-specific override: $250k -> Step 1 */
        WHEN c.`Salary` = 250000 THEN '1'
        /* 2016-01-01 to 2022-01-31: salary-only mapping via department philosophy for Partner/Principal titles only */
        WHEN c.comp_effective_date BETWEEN DATE('2016-01-01') AND DATE('2022-01-31')
          AND (
            UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PARTNER%'
            OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PRINCIPAL%'
          )
          AND ph_dept_pre.ph_step IS NOT NULL
          THEN ph_dept_pre.ph_step
        /* Salary-based Executive Step override */
        WHEN c.`Salary` BETWEEN 349000 AND 399999 THEN '1'
        WHEN c.`Salary` BETWEEN 400000 AND 449999 THEN '2'
        WHEN c.`Salary` BETWEEN 450000 AND 499999 THEN '3'
        WHEN c.`Employee Number` = 'EMP-000635'
          AND UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
            'VENTURE PARTNER & EXECUTIVE DIRECTOR, MIDDLE EAST',
            'EXECUTIVE DIRECTOR, MIDDLE EAST'
          )
          THEN '1'
        WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN (
            'PARTNER & HEAD OF STRATEGY TEAM',
            'PRINCIPAL, STRATEGY',
            'PRINCIPAL, DESIGN',
            'PRINCIPAL & HEAD OF DESIGN TEAM',
            'PRINCIPAL & HEAD OF PROGRAM MANAGEMENT TEAM',
            'PRINCIPAL, PROGRAM MANAGEMENT'
          )
          THEN '1'  -- All these titles map to Step 1 based on the philosophy table
        WHEN c.comp_effective_date = latest_effective.latest_comp_effective_date
          AND NULLIF(TRIM(c.`Step`), '') IS NOT NULL
          THEN TRIM(c.`Step`)
        ELSE COALESCE(ph_title_dept.ph_step, ph_title_any.ph_step, ph_dept_pre.ph_step)
      END
    ), 'STEP', ''))
  )                                                     AS `Step`,
  c.`Salary`,
  COALESCE(chosen.chosen_date, fb.fb_date)                     AS `Title Change Date (Used)`,
  c.comp_effective_date                                        AS `Comp Effective Date`,
  c.`Salary Start Date`,
  CAST(NULLIF(
    LEAST(
      COALESCE(DATE(c.`Salary End Date`), DATE('9999-12-31')),
      COALESCE(DATE_SUB(mlt_transition.mlt_start_date, INTERVAL 1 DAY), DATE('9999-12-31')),
      COALESCE(DATE_SUB(first_400k.first_400k_date, INTERVAL 1 DAY), DATE('9999-12-31')),
      COALESCE(DATE(tmeta.`Termination Date`), DATE('9999-12-31'))
    ),
    DATE('9999-12-31')
  ) AS DATE) AS `Salary End Date`,
  c.`Salary Notes`,
  c.`Employee Number`,
  c.`Last Name`,
  c.`First Name`,
  tmeta.`Preferred First Name` AS `Preferred First Name`,
  c.`Start Date` AS `Hire Date`,
  tmeta.`Termination Date` AS `Termination Date`,
  office_ou.`Office_Location`                                  AS `Office Location`,
  office_ou.start_date                                         AS `Office Location Start Date`,
  CASE
    WHEN UPPER(TRIM(c.`User Status`)) = 'INACTIVE EMPLOYEE'
      THEN COALESCE(office_ou.end_date, DATE(tmeta.`Termination Date`))
    ELSE office_ou.end_date
  END                                                         AS `Office Location End Date`,
  dept_ou.start_date                                           AS `Department Start Date`,
  CASE
    WHEN UPPER(TRIM(c.`User Status`)) = 'INACTIVE EMPLOYEE'
      THEN COALESCE(dept_ou.end_date, DATE(tmeta.`Termination Date`))
    ELSE dept_ou.end_date
  END                                                         AS `Department End Date`,
  div_ou.start_date                                            AS `Division Start Date`,
  CASE
    WHEN UPPER(TRIM(c.`User Status`)) = 'INACTIVE EMPLOYEE'
      THEN COALESCE(div_ou.end_date, DATE(tmeta.`Termination Date`))
    ELSE div_ou.end_date
  END                                                         AS `Division End Date`,
  c.`Salary Currency`,
  c.`Type`,
  COALESCE(ph_title_dept.target_annual_salary_usd,
           ph_title_any.target_annual_salary_usd,
           ph_dept_pre.target_annual_salary_usd)             AS `Target Annual Salary USD`

FROM (
  SELECT
    t1.*,
    COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
  FROM `namely_comp_data_history_w_notes` t1
) AS c

/* First salary >= $400k per employee (to cap prior records) */
LEFT JOIN (
  SELECT
    `Employee Number` AS employee_number,
    MIN(COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`))) AS first_400k_date
  FROM `namely_comp_data_history_w_notes`
  WHERE CAST(REPLACE(REPLACE(`Salary`, '$',''), ',', '') AS DECIMAL(12,2)) >= 400000
  GROUP BY `Employee Number`
) AS first_400k
  ON first_400k.employee_number = c.`Employee Number`

/* Latest comp effective date per employee */
LEFT JOIN (
  SELECT
    `Employee Number`,
    MAX(COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`))) AS latest_comp_effective_date
  FROM `namely_comp_data_history_w_notes`
  GROUP BY `Employee Number`
) AS latest_effective
  ON latest_effective.`Employee Number` = c.`Employee Number`

/* ---------- MLT transition: earliest Division=MLT start per employee ---------- */
LEFT JOIN (
  SELECT
    LOWER(TRIM(`Email`)) AS email,
    MIN(DATE(`Assignment Start Date`)) AS mlt_start_date
  FROM `dataflow_schema`.`employee_org_units_dept_div_loc`
  WHERE TRIM(`Org Type`) IN ('Division','Divisions')
    AND UPPER(TRIM(`Org Unit`)) = 'MLT'
  GROUP BY LOWER(TRIM(`Email`))
) AS mlt_transition
  ON mlt_transition.email = LOWER(TRIM(c.`Work Email`))

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

/* ---------- Salary philosophy mapping will be driven by Job Title joins below ---------- */

/* ---------- Salary philosophy mapping by Title within date windows ---------- */
LEFT JOIN (
  SELECT
    `Comp Group`    AS comp_group,
    `Department`    AS department,
    `Roles/ Titles` AS role_titles,
    TRIM(`Level`)   AS ph_level,
    TRIM(`Step`)    AS ph_step,
    CAST(REPLACE(REPLACE(`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)) AS target_annual_salary_usd,
    COALESCE(
      STR_TO_DATE(`Comp Band Start Date`, '%M %d, %Y'),
      STR_TO_DATE(`Comp Band Start Date`, '%b %d, %Y'),
      DATE(`Comp Band Start Date`)
    ) AS ph_start_date,
    COALESCE(
      STR_TO_DATE(`Comp Band End Date`, '%M %d, %Y'),
      STR_TO_DATE(`Comp Band End Date`, '%b %d, %Y'),
      DATE(`Comp Band End Date`)
    )   AS ph_end_date
  FROM `dataflow_schema`.`consulting_comp_philosophy`
) AS ph_title_dept
  ON (
       FIND_IN_SET(
         UPPER(TRIM(
           CASE
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR USER EXPERIENCE DESIGNER','SENIOR TECHNOLOGY CONSULTANT','SENIOR EXPERIENCE DESIGNER') THEN 'SENIOR UX DESIGNER'
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DIRECTOR','USER EXPERIENCE DIRECTOR') THEN 'CREATIVE TECHNOLOGY DIRECTOR'
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('PRODUCTION DIRECTOR','MANAGING PRODUCTION DIRECTOR') THEN 'PRODUCTION DESIGN DIRECTOR'
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN MANAGER' THEN 'SENIOR PRODUCTION DESIGNER'
             ELSE COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)
           END
         )),
         REPLACE(UPPER(ph_title_dept.role_titles), ', ', ',')
       ) > 0
       OR FIND_IN_SET(
         UPPER(TRIM(
           CASE
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR USER EXPERIENCE DESIGNER','SENIOR TECHNOLOGY CONSULTANT') THEN 'SENIOR UX DESIGNER'
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'STUDIO DIRECTOR' THEN 'USER EXPERIENCE DIRECTOR'
             ELSE COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)
           END
         )),
         REPLACE(UPPER(REPLACE(REPLACE(ph_title_dept.role_titles, '"', ''), "'", '')), ', ', ',')
       ) > 0
       OR LOCATE(
             UPPER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(
               CASE
                 WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR USER EXPERIENCE DESIGNER','SENIOR TECHNOLOGY CONSULTANT') THEN 'SENIOR UX DESIGNER'
                 WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'STUDIO DIRECTOR' THEN 'USER EXPERIENCE DIRECTOR'
                 ELSE COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)
               END
             ,'.',''),'/',''),'-',''),',',''))),
             UPPER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ph_title_dept.role_titles,'.',''),'/',''),'-',''),',',' '),'  ',' ')))
          ) > 0
       OR UPPER(TRIM(ph_title_dept.role_titles)) LIKE CONCAT('%', UPPER(TRIM(
           CASE
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR USER EXPERIENCE DESIGNER','SENIOR TECHNOLOGY CONSULTANT') THEN 'SENIOR UX DESIGNER'
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'STUDIO DIRECTOR' THEN 'USER EXPERIENCE DIRECTOR'
             ELSE COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)
           END
       )), '%')
     )
 AND (
       UPPER(TRIM(COALESCE(dept_ou.`Department`, div_ou.`Division`, c.`Division`))) = UPPER(TRIM(ph_title_dept.department))
    OR UPPER(TRIM(COALESCE(dept_ou.`Department`, div_ou.`Division`, c.`Division`))) LIKE CONCAT('%', UPPER(TRIM(ph_title_dept.department)), '%')
    OR UPPER(TRIM(ph_title_dept.department)) LIKE CONCAT('%', UPPER(TRIM(COALESCE(dept_ou.`Department`, div_ou.`Division`, c.`Division`))), '%')
     )
 AND GREATEST(c.comp_effective_date, DATE('2016-01-01')) >= ph_title_dept.ph_start_date
 AND (ph_title_dept.ph_end_date IS NULL OR GREATEST(c.comp_effective_date, DATE('2016-01-01')) <= ph_title_dept.ph_end_date)
 AND ph_title_dept.target_annual_salary_usd = COALESCE(
      (
        SELECT MAX(CAST(REPLACE(REPLACE(p2.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)))
        FROM `dataflow_schema`.`consulting_comp_philosophy` p2
        WHERE UPPER(TRIM(p2.`Department`)) = UPPER(TRIM(COALESCE(dept_ou.`Department`, div_ou.`Division`, c.`Division`)))
          AND FIND_IN_SET(
                UPPER(TRIM(
                  CASE
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR USER EXPERIENCE DESIGNER','SENIOR TECHNOLOGY CONSULTANT','SENIOR EXPERIENCE DESIGNER') THEN 'SENIOR UX DESIGNER'
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DIRECTOR','USER EXPERIENCE DIRECTOR') THEN 'CREATIVE TECHNOLOGY DIRECTOR'
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('PRODUCTION DIRECTOR','MANAGING PRODUCTION DIRECTOR') THEN 'PRODUCTION DESIGN DIRECTOR'
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN MANAGER' THEN 'SENIOR PRODUCTION DESIGNER'
                    ELSE COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)
                  END
                )),
                REPLACE(UPPER(p2.`Roles/ Titles`), ', ', ',')
              ) > 0
          AND GREATEST(c.comp_effective_date, DATE('2016-01-01')) >= COALESCE(
                STR_TO_DATE(p2.`Comp Band Start Date`, '%M %d, %Y'),
                STR_TO_DATE(p2.`Comp Band Start Date`, '%b %d, %Y'),
                DATE(p2.`Comp Band Start Date`)
              )
          AND (
                COALESCE(
                  STR_TO_DATE(p2.`Comp Band End Date`, '%M %d, %Y'),
                  STR_TO_DATE(p2.`Comp Band End Date`, '%b %d, %Y'),
                  DATE(p2.`Comp Band End Date`)
                ) IS NULL
                OR GREATEST(c.comp_effective_date, DATE('2016-01-01')) <= COALESCE(
                     STR_TO_DATE(p2.`Comp Band End Date`, '%M %d, %Y'),
                     STR_TO_DATE(p2.`Comp Band End Date`, '%b %d, %Y'),
                     DATE(p2.`Comp Band End Date`)
                )
              )
          AND CAST(REPLACE(REPLACE(p2.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)) <= c.`Salary`
      ),
      (
        SELECT MIN(CAST(REPLACE(REPLACE(p2.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)))
        FROM `dataflow_schema`.`consulting_comp_philosophy` p2
        WHERE UPPER(TRIM(p2.`Department`)) = UPPER(TRIM(COALESCE(dept_ou.`Department`, div_ou.`Division`, c.`Division`)))
          AND FIND_IN_SET(
                UPPER(TRIM(
                  CASE
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR USER EXPERIENCE DESIGNER','SENIOR TECHNOLOGY CONSULTANT') THEN 'SENIOR UX DESIGNER'
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'STUDIO DIRECTOR' THEN 'USER EXPERIENCE DIRECTOR'
                    ELSE COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)
                  END
                )),
                REPLACE(UPPER(p2.`Roles/ Titles`), ', ', ',')
              ) > 0
          AND GREATEST(c.comp_effective_date, DATE('2016-01-01')) >= COALESCE(
                STR_TO_DATE(p2.`Comp Band Start Date`, '%M %d, %Y'),
                STR_TO_DATE(p2.`Comp Band Start Date`, '%b %d, %Y'),
                DATE(p2.`Comp Band Start Date`)
              )
          AND (
                COALESCE(
                  STR_TO_DATE(p2.`Comp Band End Date`, '%M %d, %Y'),
                  STR_TO_DATE(p2.`Comp Band End Date`, '%b %d, %Y'),
                  DATE(p2.`Comp Band End Date`)
                ) IS NULL
                OR GREATEST(c.comp_effective_date, DATE('2016-01-01')) <= COALESCE(
                     STR_TO_DATE(p2.`Comp Band End Date`, '%M %d, %Y'),
                     STR_TO_DATE(p2.`Comp Band End Date`, '%b %d, %Y'),
                     DATE(p2.`Comp Band End Date`)
                )
              )
          AND CAST(REPLACE(REPLACE(p2.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)) > c.`Salary`
      )
    )

LEFT JOIN (
  SELECT
    `Comp Group`    AS comp_group,
    `Roles/ Titles` AS role_titles,
    TRIM(`Level`)   AS ph_level,
    TRIM(`Step`)    AS ph_step,
    CAST(REPLACE(REPLACE(`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)) AS target_annual_salary_usd,
    COALESCE(
      STR_TO_DATE(`Comp Band Start Date`, '%M %d, %Y'),
      STR_TO_DATE(`Comp Band Start Date`, '%b %d, %Y'),
      DATE(`Comp Band Start Date`)
    ) AS ph_start_date,
    COALESCE(
      STR_TO_DATE(`Comp Band End Date`, '%M %d, %Y'),
      STR_TO_DATE(`Comp Band End Date`, '%b %d, %Y'),
      DATE(`Comp Band End Date`)
    )   AS ph_end_date
  FROM `dataflow_schema`.`consulting_comp_philosophy`
) AS ph_title_any
  ON (
       FIND_IN_SET(
         UPPER(TRIM(
           CASE
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR USER EXPERIENCE DESIGNER','SENIOR TECHNOLOGY CONSULTANT','SENIOR EXPERIENCE DESIGNER') THEN 'SENIOR UX DESIGNER'
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DIRECTOR','USER EXPERIENCE DIRECTOR') THEN 'CREATIVE TECHNOLOGY DIRECTOR'
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('PRODUCTION DIRECTOR','MANAGING PRODUCTION DIRECTOR') THEN 'PRODUCTION DESIGN DIRECTOR'
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN MANAGER' THEN 'SENIOR PRODUCTION DESIGNER'
             ELSE COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)
           END
         )),
         REPLACE(UPPER(ph_title_any.role_titles), ', ', ',')
       ) > 0
       OR FIND_IN_SET(
         UPPER(TRIM(
           CASE
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR USER EXPERIENCE DESIGNER','SENIOR TECHNOLOGY CONSULTANT') THEN 'SENIOR UX DESIGNER'
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'STUDIO DIRECTOR' THEN 'USER EXPERIENCE DIRECTOR'
             ELSE COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)
           END
         )),
         REPLACE(UPPER(REPLACE(REPLACE(ph_title_any.role_titles, '"', ''), "'", '')), ', ', ',')
       ) > 0
       OR LOCATE(
             UPPER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(
               CASE
                 WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR USER EXPERIENCE DESIGNER','SENIOR TECHNOLOGY CONSULTANT') THEN 'SENIOR UX DESIGNER'
                 WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'STUDIO DIRECTOR' THEN 'USER EXPERIENCE DIRECTOR'
                 ELSE COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)
               END
             ,'.',''),'/',''),'-',''),',',''))),
             UPPER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ph_title_any.role_titles,'.',''),'/',''),'-',''),',',' '),'  ',' ')))
          ) > 0
       OR UPPER(TRIM(ph_title_any.role_titles)) LIKE CONCAT('%', UPPER(TRIM(
           CASE
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR USER EXPERIENCE DESIGNER','SENIOR TECHNOLOGY CONSULTANT') THEN 'SENIOR UX DESIGNER'
             WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'STUDIO DIRECTOR' THEN 'USER EXPERIENCE DIRECTOR'
             ELSE COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)
           END
       )), '%')
     )
 AND GREATEST(c.comp_effective_date, DATE('2016-01-01')) >= ph_title_any.ph_start_date
 AND (ph_title_any.ph_end_date IS NULL OR GREATEST(c.comp_effective_date, DATE('2016-01-01')) <= ph_title_any.ph_end_date)
 AND ph_title_any.target_annual_salary_usd = COALESCE(
      (
        SELECT MAX(CAST(REPLACE(REPLACE(p3.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)))
        FROM `dataflow_schema`.`consulting_comp_philosophy` p3
        WHERE FIND_IN_SET(
                UPPER(TRIM(
                  CASE
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR USER EXPERIENCE DESIGNER','SENIOR TECHNOLOGY CONSULTANT','SENIOR EXPERIENCE DESIGNER') THEN 'SENIOR UX DESIGNER'
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('STUDIO DIRECTOR','USER EXPERIENCE DIRECTOR') THEN 'CREATIVE TECHNOLOGY DIRECTOR'
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('PRODUCTION DIRECTOR','MANAGING PRODUCTION DIRECTOR') THEN 'PRODUCTION DESIGN DIRECTOR'
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'PRODUCTION DESIGN MANAGER' THEN 'SENIOR PRODUCTION DESIGNER'
                    ELSE COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)
                  END
                )),
                REPLACE(UPPER(p3.`Roles/ Titles`), ', ', ',')
              ) > 0
          AND GREATEST(c.comp_effective_date, DATE('2016-01-01')) >= COALESCE(
                STR_TO_DATE(p3.`Comp Band Start Date`, '%M %d, %Y'),
                STR_TO_DATE(p3.`Comp Band Start Date`, '%b %d, %Y'),
                DATE(p3.`Comp Band Start Date`)
              )
          AND (
                COALESCE(
                  STR_TO_DATE(p3.`Comp Band End Date`, '%M %d, %Y'),
                  STR_TO_DATE(p3.`Comp Band End Date`, '%b %d, %Y'),
                  DATE(p3.`Comp Band End Date`)
                ) IS NULL
                OR GREATEST(c.comp_effective_date, DATE('2016-01-01')) <= COALESCE(
                     STR_TO_DATE(p3.`Comp Band End Date`, '%M %d, %Y'),
                     STR_TO_DATE(p3.`Comp Band End Date`, '%b %d, %Y'),
                     DATE(p3.`Comp Band End Date`)
                )
              )
          AND CAST(REPLACE(REPLACE(p3.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)) <= c.`Salary`
      ),
      (
        SELECT MIN(CAST(REPLACE(REPLACE(p3.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)))
        FROM `dataflow_schema`.`consulting_comp_philosophy` p3
        WHERE FIND_IN_SET(
                UPPER(TRIM(
                  CASE
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) IN ('SENIOR USER EXPERIENCE DESIGNER','SENIOR TECHNOLOGY CONSULTANT') THEN 'SENIOR UX DESIGNER'
                    WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'STUDIO DIRECTOR' THEN 'USER EXPERIENCE DIRECTOR'
                    ELSE COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`)
                  END
                )),
                REPLACE(UPPER(p3.`Roles/ Titles`), ', ', ',')
              ) > 0
          AND GREATEST(c.comp_effective_date, DATE('2016-01-01')) >= COALESCE(
                STR_TO_DATE(p3.`Comp Band Start Date`, '%M %d, %Y'),
                STR_TO_DATE(p3.`Comp Band Start Date`, '%b %d, %Y'),
                DATE(p3.`Comp Band Start Date`)
              )
          AND (
                COALESCE(
                  STR_TO_DATE(p3.`Comp Band End Date`, '%M %d, %Y'),
                  STR_TO_DATE(p3.`Comp Band End Date`, '%b %d, %Y'),
                  DATE(p3.`Comp Band End Date`)
                ) IS NULL
                OR GREATEST(c.comp_effective_date, DATE('2016-01-01')) <= COALESCE(
                     STR_TO_DATE(p3.`Comp Band End Date`, '%M %d, %Y'),
                     STR_TO_DATE(p3.`Comp Band End Date`, '%b %d, %Y'),
                     DATE(p3.`Comp Band End Date`)
                )
              )
          AND CAST(REPLACE(REPLACE(p3.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)) > c.`Salary`
      )
    )

/* ---------- Pre-2022 fallback: department-only, use smallest numeric step per salary/date window and avoid duplicates ---------- */
LEFT JOIN (
  SELECT
    p0.`Department` AS department,
    TRIM(p0.`Level`) AS ph_level,
    TRIM(p0.`Step`)  AS ph_step,
    CAST(REPLACE(REPLACE(p0.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)) AS target_annual_salary_usd,
    COALESCE(
      STR_TO_DATE(p0.`Comp Band Start Date`, '%M %d, %Y'),
      STR_TO_DATE(p0.`Comp Band Start Date`, '%b %d, %Y'),
      DATE(p0.`Comp Band Start Date`)
    ) AS ph_start_date,
    COALESCE(
      STR_TO_DATE(p0.`Comp Band End Date`, '%M %d, %Y'),
      STR_TO_DATE(p0.`Comp Band End Date`, '%b %d, %Y'),
      DATE(p0.`Comp Band End Date`)
    )   AS ph_end_date
  FROM `dataflow_schema`.`consulting_comp_philosophy` p0
  WHERE NOT EXISTS (
    SELECT 1
    FROM `dataflow_schema`.`consulting_comp_philosophy` p1
    WHERE UPPER(TRIM(p1.`Department`)) = UPPER(TRIM(p0.`Department`))
      AND CAST(REPLACE(REPLACE(p1.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2))
          = CAST(REPLACE(REPLACE(p0.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2))
      AND COALESCE(
            STR_TO_DATE(p1.`Comp Band Start Date`, '%M %d, %Y'),
            STR_TO_DATE(p1.`Comp Band Start Date`, '%b %d, %Y'),
            DATE(p1.`Comp Band Start Date`)
          ) = COALESCE(
                STR_TO_DATE(p0.`Comp Band Start Date`, '%M %d, %Y'),
                STR_TO_DATE(p0.`Comp Band Start Date`, '%b %d, %Y'),
                DATE(p0.`Comp Band Start Date`)
              )
      AND (
            (p1.`Comp Band End Date` IS NULL AND p0.`Comp Band End Date` IS NULL)
         OR COALESCE(
              STR_TO_DATE(p1.`Comp Band End Date`, '%M %d, %Y'),
              STR_TO_DATE(p1.`Comp Band End Date`, '%b %d, %Y'),
              DATE(p1.`Comp Band End Date`)
            ) = COALESCE(
                  STR_TO_DATE(p0.`Comp Band End Date`, '%M %d, %Y'),
                  STR_TO_DATE(p0.`Comp Band End Date`, '%b %d, %Y'),
                  DATE(p0.`Comp Band End Date`)
                )
          )
      AND CAST(TRIM(p1.`Step`) AS UNSIGNED) < CAST(TRIM(p0.`Step`) AS UNSIGNED)
  )
) AS ph_dept_pre
  ON UPPER(TRIM(COALESCE(dept_ou.`Department`, div_ou.`Division`, c.`Division`))) = UPPER(TRIM(ph_dept_pre.department))
 AND GREATEST(c.comp_effective_date, DATE('2016-01-01')) <= DATE('2022-01-31')
 AND GREATEST(c.comp_effective_date, DATE('2016-01-01')) >= ph_dept_pre.ph_start_date
 AND (ph_dept_pre.ph_end_date IS NULL OR GREATEST(c.comp_effective_date, DATE('2016-01-01')) <= ph_dept_pre.ph_end_date)
 -- Include all consulting departments; previously excluded TECH/STUDIO cohorts removed
 AND ph_dept_pre.target_annual_salary_usd = COALESCE(
       (
         SELECT MAX(CAST(REPLACE(REPLACE(p0.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)))
         FROM `dataflow_schema`.`consulting_comp_philosophy` p0
         WHERE UPPER(TRIM(p0.`Department`)) = UPPER(TRIM(COALESCE(dept_ou.`Department`, div_ou.`Division`, c.`Division`)))
           AND GREATEST(c.comp_effective_date, DATE('2016-01-01')) >= COALESCE(
                 STR_TO_DATE(p0.`Comp Band Start Date`, '%M %d, %Y'),
                 STR_TO_DATE(p0.`Comp Band Start Date`, '%b %d, %Y'),
                 DATE(p0.`Comp Band Start Date`)
               )
           AND (
                 COALESCE(
                   STR_TO_DATE(p0.`Comp Band End Date`, '%M %d, %Y'),
                   STR_TO_DATE(p0.`Comp Band End Date`, '%b %d, %Y'),
                   DATE(p0.`Comp Band End Date`)
                 ) IS NULL
                 OR GREATEST(c.comp_effective_date, DATE('2016-01-01')) <= COALESCE(
                      STR_TO_DATE(p0.`Comp Band End Date`, '%M %d, %Y'),
                      STR_TO_DATE(p0.`Comp Band End Date`, '%b %d, %Y'),
                      DATE(p0.`Comp Band End Date`)
                 )
               )
           AND CAST(REPLACE(REPLACE(p0.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)) <= c.`Salary`
       ),
       (
         SELECT MIN(CAST(REPLACE(REPLACE(p0.`Annual Salary USD`, '$',''), ',', '') AS DECIMAL(12,2)))
         FROM `dataflow_schema`.`consulting_comp_philosophy` p0
         WHERE UPPER(TRIM(p0.`Department`)) = UPPER(TRIM(COALESCE(dept_ou.`Department`, div_ou.`Division`, c.`Division`)))
           AND GREATEST(c.comp_effective_date, DATE('2016-01-01')) >= COALESCE(
                 STR_TO_DATE(p0.`Comp Band Start Date`, '%M %d, %Y'),
                 STR_TO_DATE(p0.`Comp Band Start Date`, '%b %d, %Y'),
                 DATE(p0.`Comp Band Start Date`)
               )
           AND (
                 COALESCE(
                   STR_TO_DATE(p0.`Comp Band End Date`, '%M %d, %Y'),
                   STR_TO_DATE(p0.`Comp Band End Date`, '%b %d, %Y'),
                   DATE(p0.`Comp Band End Date`)
                 ) IS NULL
                 OR GREATEST(c.comp_effective_date, DATE('2016-01-01')) <= COALESCE(
                      STR_TO_DATE(p0.`Comp Band End Date`, '%M %d, %Y'),
                      STR_TO_DATE(p0.`Comp Band End Date`, '%b %d, %Y'),
                      DATE(p0.`Comp Band End Date`)
                 )
               )
       )
     )

/* Additional diagnostic query to check exact title matching */
/*
SELECT DISTINCT
    `Roles/ Titles`,
    `Level`,
    `Step`,
    `Department`,
    `Comp Band Start Date`,
    `Comp Band End Date`,
    `Annual Salary USD`,
    -- Check if specific titles are found
    FIND_IN_SET('PARTNER & HEAD OF STRATEGY TEAM', REPLACE(UPPER(`Roles/ Titles`), ', ', ',')) as title_1_match,
    FIND_IN_SET('PRINCIPAL, STRATEGY', REPLACE(UPPER(`Roles/ Titles`), ', ', ',')) as title_2_match,
    FIND_IN_SET('PRINCIPAL, DESIGN', REPLACE(UPPER(`Roles/ Titles`), ', ', ',')) as title_3_match,
    FIND_IN_SET('PRINCIPAL & HEAD OF DESIGN TEAM', REPLACE(UPPER(`Roles/ Titles`), ', ', ',')) as title_4_match,
    FIND_IN_SET('PRINCIPAL & HEAD OF PROGRAM MANAGEMENT TEAM', REPLACE(UPPER(`Roles/ Titles`), ', ', ',')) as title_5_match,
    FIND_IN_SET('PRINCIPAL, PROGRAM MANAGEMENT', REPLACE(UPPER(`Roles/ Titles`), ', ', ',')) as title_6_match
FROM `dataflow_schema`.`consulting_comp_philosophy`
WHERE UPPER(`Roles/ Titles`) LIKE '%PARTNER%'
   OR UPPER(`Roles/ Titles`) LIKE '%PRINCIPAL%'
ORDER BY `Roles/ Titles`;
*/

/* Exclude salary reductions for senior leaders effective 2024-08-01 */
/* Exclude employees who joined Managing Partners, Founders, Executive Management departments or MLT division */
/* But keep historical records from BEFORE they joined these groups */
WHERE NOT (
    c.`Employee Number` IN (
        'EMP-000748', 'EMP-000616', 'EMP-000211', 'EMP-001292', 'EMP-000109',
        'EMP-001047', 'EMP-000328', 'EMP-000054', 'EMP-000377', 'EMP-000635',
        'EMP-000024', 'EMP-001269', 'EMP-000271', 'EMP-000509', 'EMP-000315',
        'EMP-000075', 'EMP-000580', 'EMP-000208', 'EMP-000001', 'EMP-000031'
    )
    AND GREATEST(c.comp_effective_date, DATE('2016-01-01')) >= DATE('2024-08-01')
)
AND NOT EXISTS (
    /* Exclude records where compensation effective date is AFTER joining excluded departments/divisions */
    SELECT 1
    FROM `dataflow_schema`.`employee_org_units_dept_div_loc` ou
    WHERE ou.`Email` = LOWER(TRIM(c.`Work Email`))
      AND (
          (TRIM(ou.`Org Type`) IN ('Department','Departments')
           AND UPPER(TRIM(ou.`Org Unit`)) IN ('MANAGING PARTNERS', 'FOUNDERS', 'EXECUTIVE MANAGEMENT'))
          OR
          (TRIM(ou.`Org Type`) IN ('Division','Divisions')
           AND UPPER(TRIM(ou.`Org Unit`)) = 'MLT')
      )
      AND c.comp_effective_date >= DATE(ou.`Assignment Start Date`)
)
AND NOT (
    /* Exclude freelance, freelancer, and intern roles */
    UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%FREELANCE%'
    OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%FREELANCER%'
    OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%INTERN%'
    OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%PRODUCTION DESIGN ASSOCIATE%'
    OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%DESIGN ASSOCIATE%'
    OR UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) LIKE '%ASSOCIATE STRATEGIST%'
)
AND NOT (
    /* Exclude rows with Job Title TERMINATED */
    UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'TERMINATED'
)
AND NOT (
    /* Exclude records with Comp Effective Date or Salary Start Date before 2016-01-01 */
    /* But keep records for active employees with long tenure */
    (c.comp_effective_date < DATE('2016-01-01')
     OR DATE(c.`Salary Start Date`) < DATE('2016-01-01'))
    AND UPPER(TRIM(c.`User Status`)) != 'ACTIVE EMPLOYEE'
)
AND NOT (
    /* Exclude erroneous 2015-07-15 dates from payroll system rollout */
    c.comp_effective_date = DATE('2015-07-15')
    OR DATE(c.`Salary Start Date`) = DATE('2015-07-15')
)
AND NOT (
    /* Exclude employees in specified non-consulting departments */
    UPPER(TRIM(COALESCE(dept_ou.`Department`, div_ou.`Division`, c.`Division`))) IN (
        'ADMIN',
        'BRAND',
        'BUSINESS DEVELOPMENT',
        'BUSINESS OPERATIONS',
        'BUSINESS PERFORMANCE',
        'ENTERPRISE TECHNOLOGY',
        'FINANCE',
        'INTERN PROGRAM',
        'LEARNING & FLOURISHING',
        'OFFICE & COMMUNITY OPS',
        'PEOPLE',
        'TALENT'
    )
)
AND NOT (
    /* Exclude senior leaders once salary reaches >= $400,000 */
    c.`Salary` >= 400000
)
AND NOT EXISTS (
    /* Exclude employees with job titles listed in external excluded_roles (normalized by lowercase and ignoring commas) */
    SELECT 1
    FROM `dataflow_schema`.`excluded_roles` er
    WHERE REPLACE(LOWER(TRIM(er.`Job Titles`)), ',', '') = REPLACE(LOWER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))), ',', '')
)
AND UPPER(TRIM(c.`Employee Type`)) = 'STAFF FULL TIME'
AND UPPER(TRIM(COALESCE(div_ou.`Division`, c.`Division`))) = 'CONSULTING'
;
