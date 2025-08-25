-- MySQL 5.7 snippet to map comp rows to salary philosophy table
-- Usage: paste the LEFT JOIN block into your final SELECT query.

LEFT JOIN (
  SELECT
    `Comp Group`,
    `Department`,
    `Roles/ Titles`,
    `Step & Level` AS step_level_key,
    CAST(REPLACE(REPLACE(`Annual Salary
USD`, '$',''), ',', '') AS DECIMAL(12,2)) AS target_annual_salary_usd,
    COALESCE(STR_TO_DATE(`Salary Start Effective Date`, '%M %d, %Y'),
             STR_TO_DATE(`Salary Start Effective Date`, '%b %d, %Y')) AS ph_start_date,
    COALESCE(STR_TO_DATE(`Salary End Effective Date`, '%M %d, %Y'),
             STR_TO_DATE(`Salary End Effective Date`, '%b %d, %Y')) AS ph_end_date
  FROM table_3
) AS ph
  ON ph.step_level_key = CONCAT(TRIM(c.`Level`), ' - Step ', TRIM(c.`Step`))
 AND c.comp_effective_date >= ph.ph_start_date
 AND (ph.ph_end_date IS NULL OR c.comp_effective_date <= ph.ph_end_date)






