/* ---------- Misalignment report: Terminated titles and date discrepancies ---------- */
SELECT
  c.`Employee Number`,
  c.`First Name`,
  c.`Last Name`,
  c.`User Status`,
  c.`Employee Type`,
  COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`) AS `Job Title (Used)`,
  COALESCE(chosen.chosen_date, fb.fb_date)             AS `Title Change Date (Used)`,
  c.comp_effective_date                                AS `Comp Effective Date`,
  c.`Salary Start Date`,
  c.`Salary End Date`,
  c.`Start Date`                                       AS `Hire Date`,
  tmeta.`Termination Date`                             AS `Termination Date`,
  c.`Division`,
  c.`Department`,
  c.`Work Email`,
  CONCAT_WS('; ',
    CASE
      WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'TERMINATED'
        THEN 'title is TERMINATED'
      ELSE NULL
    END,
    CASE
      WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'TERMINATED'
           AND tmeta.`Termination Date` IS NULL THEN 'terminated title but missing termination date'
      ELSE NULL
    END,
    CASE
      WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'TERMINATED'
           AND UPPER(TRIM(c.`User Status`)) = 'ACTIVE EMPLOYEE' THEN 'terminated title but user marked active'
      ELSE NULL
    END,
    CASE
      WHEN UPPER(TRIM(c.`User Status`)) = 'INACTIVE EMPLOYEE'
           AND tmeta.`Termination Date` IS NULL THEN 'inactive but termination date missing'
      ELSE NULL
    END,
    CASE
      WHEN tmeta.`Termination Date` IS NOT NULL
           AND c.comp_effective_date > DATE(tmeta.`Termination Date`) THEN 'comp effective after termination'
      ELSE NULL
    END,
    CASE
      WHEN tmeta.`Termination Date` IS NOT NULL
           AND COALESCE(chosen.chosen_date, fb.fb_date) > DATE(tmeta.`Termination Date`) THEN 'title change after termination'
      ELSE NULL
    END,
    CASE
      WHEN tmeta.`Termination Date` IS NOT NULL
           AND DATE(c.`Salary End Date`) > DATE(tmeta.`Termination Date`) THEN 'salary end after termination'
      ELSE NULL
    END,
    CASE
      WHEN DATE(c.`Salary End Date`) IS NOT NULL
           AND DATE(c.`Start Date`) IS NOT NULL
           AND DATE(c.`Salary End Date`) < DATE(c.`Start Date`) THEN 'salary end before hire date'
      ELSE NULL
    END,
    CASE
      WHEN DATE(c.`Start Date`) IS NOT NULL
           AND c.comp_effective_date < DATE(c.`Start Date`) THEN 'comp effective before hire date'
      ELSE NULL
    END,
    CASE
      WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'TERMINATED'
           AND tmeta.`Termination Date` IS NOT NULL
           AND DATE(c.`Salary End Date`) IS NOT NULL
           AND DATE(c.`Salary End Date`) <> DATE(tmeta.`Termination Date`) THEN 'terminated title but salary end != termination date'
      ELSE NULL
    END
  ) AS `Misalignment Flags`,
  (
    (CASE WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'TERMINATED' THEN 1 ELSE 0 END) +
    (CASE WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'TERMINATED' AND tmeta.`Termination Date` IS NULL THEN 1 ELSE 0 END) +
    (CASE WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'TERMINATED' AND UPPER(TRIM(c.`User Status`)) = 'ACTIVE EMPLOYEE' THEN 1 ELSE 0 END) +
    (CASE WHEN UPPER(TRIM(c.`User Status`)) = 'INACTIVE EMPLOYEE' AND tmeta.`Termination Date` IS NULL THEN 1 ELSE 0 END) +
    (CASE WHEN tmeta.`Termination Date` IS NOT NULL AND c.comp_effective_date > DATE(tmeta.`Termination Date`) THEN 1 ELSE 0 END) +
    (CASE WHEN tmeta.`Termination Date` IS NOT NULL AND COALESCE(chosen.chosen_date, fb.fb_date) > DATE(tmeta.`Termination Date`) THEN 1 ELSE 0 END) +
    (CASE WHEN tmeta.`Termination Date` IS NOT NULL AND DATE(c.`Salary End Date`) > DATE(tmeta.`Termination Date`) THEN 1 ELSE 0 END) +
    (CASE WHEN DATE(c.`Salary End Date`) IS NOT NULL AND DATE(c.`Start Date`) IS NOT NULL AND DATE(c.`Salary End Date`) < DATE(c.`Start Date`) THEN 1 ELSE 0 END) +
    (CASE WHEN DATE(c.`Start Date`) IS NOT NULL AND c.comp_effective_date < DATE(c.`Start Date`) THEN 1 ELSE 0 END) +
    (CASE WHEN UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'TERMINATED' AND tmeta.`Termination Date` IS NOT NULL AND DATE(c.`Salary End Date`) IS NOT NULL AND DATE(c.`Salary End Date`) <> DATE(tmeta.`Termination Date`) THEN 1 ELSE 0 END)
  ) AS `Flag Count`
FROM (
  SELECT
    t1.*,  -- typo fix: t1.*, not 11.*
    COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
  FROM `namely_comp_data_history_w_notes` t1
  WHERE UPPER(t1.`Division`) = 'CONSULTING'
    AND DATE(t1.`Start Date`) >= '2016-01-01'
) AS c
/* Title matching: prefer on/before ≤15d, else after ≤15d */
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
/* Title text for the chosen and fallback dates */
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
/* Employee meta fields: Termination Date */
LEFT JOIN (
  SELECT
    `Employee Number`,
    MAX(`Termination Date`) AS `Termination Date`
  FROM `namely_title_history_data_aq`
  GROUP BY `Employee Number`
) AS tmeta
  ON tmeta.`Employee Number` = c.`Employee Number`
WHERE (
  UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'TERMINATED'
) OR (
  /* any of the discrepancy conditions */
  (UPPER(TRIM(c.`User Status`)) = 'INACTIVE EMPLOYEE' AND tmeta.`Termination Date` IS NULL) OR
  (tmeta.`Termination Date` IS NOT NULL AND c.comp_effective_date > DATE(tmeta.`Termination Date`)) OR
  (tmeta.`Termination Date` IS NOT NULL AND COALESCE(chosen.chosen_date, fb.fb_date) > DATE(tmeta.`Termination Date`)) OR
  (tmeta.`Termination Date` IS NOT NULL AND DATE(c.`Salary End Date`) > DATE(tmeta.`Termination Date`)) OR
  (DATE(c.`Salary End Date`) IS NOT NULL AND DATE(c.`Start Date`) IS NOT NULL AND DATE(c.`Salary End Date`) < DATE(c.`Start Date`)) OR
  (DATE(c.`Start Date`) IS NOT NULL AND c.comp_effective_date < DATE(c.`Start Date`)) OR
  (UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'TERMINATED' AND tmeta.`Termination Date` IS NOT NULL AND DATE(c.`Salary End Date`) IS NOT NULL AND DATE(c.`Salary End Date`) <> DATE(tmeta.`Termination Date`)) OR
  (UPPER(TRIM(COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`))) = 'TERMINATED' AND UPPER(TRIM(c.`User Status`)) = 'ACTIVE EMPLOYEE')
)
ORDER BY `Flag Count` DESC, c.`Employee Number`, `Comp Effective Date` DESC;


