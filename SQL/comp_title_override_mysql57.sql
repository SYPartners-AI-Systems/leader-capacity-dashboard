-- Domo MySQL DataFlow (MySQL 5.7-compatible)
-- Inputs:
--   namely_comp_data_history_w_notes   (comp source)
--   namely_title_history_data_aq       (title history)
-- Output:
--   Consulting-only comp history with Job Title overridden from Title History
--   using ±15-day window (prefer on/before), with fallback to latest prior title.

SELECT
  c.`Salary Currency`,
  c.`Office Location`,
  /* Overridden title */
  COALESCE(mtit.`Title`, fbtit.`Title`, c.`Job Title`) AS `Job Title`,
  /* Debug: which date was used and strategy */
  COALESCE(chosen.chosen_date, fb.fb_date) AS `Title Change Date (Used)`,
  c.comp_effective_date                    AS `Comp Effective Date`,
  CASE
    WHEN mtit.`Title` IS NOT NULL THEN 'window±15d'
    WHEN fbtit.`Title` IS NOT NULL THEN 'fallback_before'
    ELSE 'no_match'
  END AS `Title Match Strategy`,
  
  c.`Division`,
  c.`Salary Notes`,
  c.`Start Date`,
  c.`Employee Number`,
  c.`Level`,
  c.`Salary End Date`,
  c.`Step`,
  c.`Salary Start Date`,
  c.`Department`,
  c.`User Status`,
  c.`Last Name`,
  c.`Salary`,
  c.`Type`,
  c.`Employee Type`,
  c.`First Name`
FROM
  (
    SELECT
      t1.*,
      COALESCE(DATE(t1.`Salary Start Date`), DATE(t1.`Start Date`)) AS comp_effective_date
    FROM `namely_comp_data_history_w_notes` t1
    WHERE UPPER(t1.`Division`) = 'CONSULTING'
      AND DATE(t1.`Start Date`) >= '2016-01-01'
  ) AS c

  /* On/before within 15 days: latest title change <= comp date */
  LEFT JOIN (
    SELECT
      p.`Employee Number`,
      p.comp_effective_date,
      MAX(th.title_change_date) AS match_date
    FROM
      (
        SELECT DISTINCT
          COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
          `Employee Number`
        FROM `namely_comp_data_history_w_notes`
        WHERE UPPER(`Division`) = 'CONSULTING'
          AND DATE(`Start Date`) >= '2016-01-01'
      ) AS p
      JOIN (
        SELECT
          `Employee Number`,
          DATE(`Title Change Date`) AS title_change_date
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS th
        ON th.`Employee Number` = p.`Employee Number`
    WHERE th.title_change_date <= p.comp_effective_date
      AND DATEDIFF(p.comp_effective_date, th.title_change_date) <= 15
    GROUP BY p.`Employee Number`, p.comp_effective_date
  ) AS ob
    ON ob.`Employee Number` = c.`Employee Number`
   AND ob.comp_effective_date = c.comp_effective_date

  /* After within 15 days: earliest title change >= comp date */
  LEFT JOIN (
    SELECT
      p.`Employee Number`,
      p.comp_effective_date,
      MIN(th.title_change_date) AS match_date
    FROM
      (
        SELECT DISTINCT
          COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
          `Employee Number`
        FROM `namely_comp_data_history_w_notes`
        WHERE UPPER(`Division`) = 'CONSULTING'
          AND DATE(`Start Date`) >= '2016-01-01'
      ) AS p
      JOIN (
        SELECT
          `Employee Number`,
          DATE(`Title Change Date`) AS title_change_date
        FROM `namely_title_history_data_aq`
        WHERE `Title` IS NOT NULL
      ) AS th
        ON th.`Employee Number` = p.`Employee Number`
    WHERE th.title_change_date >= p.comp_effective_date
      AND DATEDIFF(th.title_change_date, p.comp_effective_date) <= 15
    GROUP BY p.`Employee Number`, p.comp_effective_date
  ) AS af
    ON af.`Employee Number` = c.`Employee Number`
   AND af.comp_effective_date = c.comp_effective_date

  /* Choose match date: prefer on/before; else after */
  LEFT JOIN (
    SELECT
      p.`Employee Number`,
      p.comp_effective_date,
      COALESCE(ob.match_date, af.match_date) AS chosen_date
    FROM
      (
        SELECT DISTINCT
          COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
          `Employee Number`
        FROM `namely_comp_data_history_w_notes`
        WHERE UPPER(`Division`) = 'CONSULTING'
          AND DATE(`Start Date`) >= '2016-01-01'
      ) AS p
      LEFT JOIN (
        SELECT
          p2.`Employee Number`, p2.comp_effective_date, MAX(th2.title_change_date) AS match_date
        FROM
          (
            SELECT DISTINCT
              COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
              `Employee Number`
            FROM `namely_comp_data_history_w_notes`
            WHERE UPPER(`Division`) = 'CONSULTING'
              AND DATE(`Start Date`) >= '2016-01-01'
          ) AS p2
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) AS th2
            ON th2.`Employee Number` = p2.`Employee Number`
        WHERE th2.title_change_date <= p2.comp_effective_date
          AND DATEDIFF(p2.comp_effective_date, th2.title_change_date) <= 15
        GROUP BY p2.`Employee Number`, p2.comp_effective_date
      ) AS ob
        ON ob.`Employee Number` = p.`Employee Number` AND ob.comp_effective_date = p.comp_effective_date
      LEFT JOIN (
        SELECT
          p3.`Employee Number`, p3.comp_effective_date, MIN(th3.title_change_date) AS match_date
        FROM
          (
            SELECT DISTINCT
              COALESCE(DATE(`Salary Start Date`), DATE(`Start Date`)) AS comp_effective_date,
              `Employee Number`
            FROM `namely_comp_data_history_w_notes`
            WHERE UPPER(`Division`) = 'CONSULTING'
              AND DATE(`Start Date`) >= '2016-01-01'
          ) AS p3
          JOIN (
            SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date
            FROM `namely_title_history_data_aq`
            WHERE `Title` IS NOT NULL
          ) AS th3
            ON th3.`Employee Number` = p3.`Employee Number`
        WHERE th3.title_change_date >= p3.comp_effective_date
          AND DATEDIFF(th3.title_change_date, p3.comp_effective_date) <= 15
        GROUP BY p3.`Employee Number`, p3.comp_effective_date
      ) AS af
        ON af.`Employee Number` = p.`Employee Number` AND af.comp_effective_date = p.comp_effective_date
  ) AS chosen
    ON chosen.`Employee Number` = c.`Employee Number`
   AND chosen.comp_effective_date = c.comp_effective_date

  /* Title for chosen date */
  LEFT JOIN (
    SELECT `Employee Number`, DATE(`Title Change Date`) AS title_change_date, `Title`
    FROM `namely_title_history_data_aq`
    WHERE `Title` IS NOT NULL
  ) AS mtit
    ON mtit.`Employee Number` = c.`Employee Number`
   AND mtit.title_change_date = chosen.chosen_date

  /* Fallback: latest title before comp date */
  LEFT JOIN (
    SELECT
      p.`Employee Number`,
      p.comp_effective_date,
      MAX(th.title_change_date) AS fb_date
    FROM
      (
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
   AND fbtit.title_change_date = fb.fb_date;


