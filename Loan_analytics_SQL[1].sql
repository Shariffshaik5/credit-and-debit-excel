USE banking_analytics;

-- ===========================================================
-- DBS BANKING ANALYTICS
-- LOAN DASHBOARD - CORRECTED FOR YOUR MYSQL COLUMN NAMES
-- ===========================================================

-- 1. CHECK TABLES
SHOW TABLES;

-- 2. REPORTING PERIOD

SET @start_date = '2024-01-01';
SET @end_date   = '2025-01-01';

-- ===========================================================
-- KPI QUERIES
-- ===========================================================

-- KPI 1: TOTAL CLIENTS
SELECT COUNT(DISTINCT client_id) AS Total_Clients
FROM dim_client;

-- KPI 2: ACTIVE CLIENTS
SELECT COUNT(DISTINCT client_id) AS Active_Clients
FROM fact_loan
WHERE LOWER(loan_status) = 'active';

-- KPI 3: NEW CLIENTS
SELECT COUNT(*) AS New_Clients
FROM (
    SELECT client_id, MIN(disbursement_date) AS first_loan_date
    FROM fact_loan
    GROUP BY client_id
) x
WHERE first_loan_date >= @start_date
  AND first_loan_date < @end_date;

-- KPI 4: CLIENT RETENTION RATE
WITH periods AS (
    SELECT
        @start_date AS current_start,
        @end_date AS current_end,
        DATE_SUB(
            @start_date,
            INTERVAL TIMESTAMPDIFF(MONTH, @start_date, @end_date) MONTH
        ) AS previous_start
)
SELECT ROUND(
    COUNT(DISTINCT CASE
        WHEN l.disbursement_date >= p.current_start
         AND l.disbursement_date < p.current_end
         AND l.client_id IN (
             SELECT DISTINCT client_id
             FROM fact_loan
             WHERE disbursement_date >= p.previous_start
               AND disbursement_date < p.current_start
         )
        THEN l.client_id
    END) * 100.0 /
    NULLIF((
        SELECT COUNT(DISTINCT client_id)
        FROM fact_loan
        WHERE disbursement_date >= p.previous_start
          AND disbursement_date < p.current_start
    ), 0), 2
) AS Client_Retention_Rate
FROM fact_loan l
CROSS JOIN periods p;

-- KPI 5: TOTAL LOAN AMOUNT DISBURSED
SELECT SUM(loan_amount) AS Total_Loan_Amount_Disbursed
FROM fact_loan
WHERE disbursement_date >= @start_date
  AND disbursement_date < @end_date;

-- KPI 6: TOTAL FUNDED AMOUNT
SELECT SUM(funded_amount) AS Total_Funded_Amount
FROM fact_loan
WHERE disbursement_date >= @start_date
  AND disbursement_date < @end_date;

-- KPI 7: AVERAGE LOAN SIZE
SELECT ROUND(AVG(loan_amount), 2) AS Average_Loan_Size
FROM fact_loan
WHERE disbursement_date >= @start_date
  AND disbursement_date < @end_date;

-- KPI 8: LOAN GROWTH %
WITH periods AS (
    SELECT
        @start_date AS current_start,
        @end_date AS current_end,
        DATE_SUB(
            @start_date,
            INTERVAL TIMESTAMPDIFF(MONTH, @start_date, @end_date) MONTH
        ) AS previous_start
)
SELECT ROUND(
    (
        SUM(CASE
            WHEN l.disbursement_date >= p.current_start
             AND l.disbursement_date < p.current_end
            THEN l.loan_amount ELSE 0 END)
        -
        SUM(CASE
            WHEN l.disbursement_date >= p.previous_start
             AND l.disbursement_date < p.current_start
            THEN l.loan_amount ELSE 0 END)
    ) * 100.0 /
    NULLIF(
        SUM(CASE
            WHEN l.disbursement_date >= p.previous_start
             AND l.disbursement_date < p.current_start
            THEN l.loan_amount ELSE 0 END), 0
    ), 2
) AS Loan_Growth_Percentage
FROM fact_loan l
CROSS JOIN periods p;

-- KPI 9: TOTAL REPAYMENTS COLLECTED
SELECT SUM(total_pymnt) AS Total_Repayments_Collected
FROM fact_repayment;

-- KPI 10: PRINCIPAL RECOVERY RATE
WITH loan_by_account AS (
    SELECT account_id, MAX(loan_amount) AS loan_amount
    FROM fact_loan
    WHERE disbursement_date >= @start_date
      AND disbursement_date < @end_date
    GROUP BY account_id
),
repayment_by_account AS (
    SELECT account_id, SUM(total_rec_prncp) AS principal_recovered
    FROM fact_repayment
    GROUP BY account_id
)
SELECT ROUND(
    SUM(COALESCE(r.principal_recovered, 0)) * 100.0 /
    NULLIF(SUM(l.loan_amount), 0), 2
) AS Principal_Recovery_Rate
FROM loan_by_account l
LEFT JOIN repayment_by_account r
    ON l.account_id = r.account_id;

-- KPI 11: INTEREST INCOME
SELECT SUM(total_rec_int) AS Interest_Income
FROM fact_repayment;

-- KPI 12: DEFAULT RATE
SELECT ROUND(
    COUNT(DISTINCT CASE
        WHEN LOWER(is_default_loan) = 'y' THEN account_id
    END) * 100.0 /
    NULLIF(COUNT(DISTINCT account_id), 0), 2
) AS Default_Rate
FROM fact_repayment;

-- KPI 13: DELINQUENCY RATE
SELECT ROUND(
    COUNT(DISTINCT CASE
        WHEN LOWER(is_delinquent_loan) = 'y' THEN account_id
    END) * 100.0 /
    NULLIF(COUNT(DISTINCT account_id), 0), 2
) AS Delinquency_Rate
FROM fact_repayment;

-- KPI 14: ON-TIME REPAYMENT %
SELECT ROUND(
    COUNT(DISTINCT CASE
        WHEN LOWER(repayment_behavior) = 'on-time' THEN account_id
    END) * 100.0 /
    NULLIF(COUNT(DISTINCT account_id), 0), 2
) AS On_Time_Repayment_Percentage
FROM fact_repayment;

-- ===========================================================
-- CHART QUERIES
-- ===========================================================

-- CHART 1: LOAN DISTRIBUTION BY BRANCH
SELECT branch_name,
       COUNT(DISTINCT account_id) AS Total_Loans,
       SUM(loan_amount) AS Total_Loan_Amount
FROM fact_loan
WHERE disbursement_date >= @start_date
  AND disbursement_date < @end_date
GROUP BY branch_name
ORDER BY Total_Loan_Amount DESC;

-- CHART 2: BRANCH PERFORMANCE CATEGORY SPLIT
SELECT branch_performance_category,
       COUNT(*) AS Branch_Count
FROM dim_branch
GROUP BY branch_performance_category
ORDER BY Branch_Count DESC;

-- CHART 3: BRANCH PERFORMANCE CATEGORY PERCENTAGE
SELECT branch_performance_category,
       COUNT(*) AS Branch_Count,
       ROUND(COUNT(*) * 100.0 /
             NULLIF((SELECT COUNT(*) FROM dim_branch), 0), 2) AS Percentage
FROM dim_branch
GROUP BY branch_performance_category
ORDER BY Branch_Count DESC;

-- CHART 4: PRODUCT-WISE LOAN VOLUME
SELECT l.product_id,
       COUNT(DISTINCT l.account_id) AS Loan_Volume,
       SUM(l.loan_amount) AS Total_Loan_Amount
FROM fact_loan l
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY l.product_id
ORDER BY Total_Loan_Amount DESC;

-- CHART 5: PRODUCT PROFITABILITY / INTEREST INCOME
SELECT l.product_id,
       SUM(r.total_rec_int) AS Interest_Income
FROM fact_loan l
JOIN fact_repayment r ON l.account_id = r.account_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY l.product_id
ORDER BY Interest_Income DESC;

-- CHART 6: LOAN STATUS DISTRIBUTION
SELECT loan_status,
       COUNT(DISTINCT account_id) AS Loan_Count
FROM fact_loan
WHERE disbursement_date >= @start_date
  AND disbursement_date < @end_date
GROUP BY loan_status
ORDER BY Loan_Count DESC;

-- CHART 7: LOAN AMOUNT BY LOAN STATUS
SELECT loan_status,
       SUM(loan_amount) AS Total_Loan_Amount
FROM fact_loan
WHERE disbursement_date >= @start_date
  AND disbursement_date < @end_date
GROUP BY loan_status
ORDER BY Total_Loan_Amount DESC;

-- CHART 8: LOAN TREND BY YEAR
SELECT YEAR(disbursement_date) AS Loan_Year,
       COUNT(DISTINCT account_id) AS Total_Loans,
       SUM(loan_amount) AS Total_Loan_Amount
FROM fact_loan
GROUP BY YEAR(disbursement_date)
ORDER BY Loan_Year;

-- CHART 9: MONTHLY LOAN TREND
SELECT YEAR(disbursement_date) AS Loan_Year,
       MONTH(disbursement_date) AS Loan_Month,
       DATE_FORMAT(disbursement_date, '%Y-%m') AS Year_Month,
       COUNT(DISTINCT account_id) AS Total_Loans,
       SUM(loan_amount) AS Total_Loan_Amount
FROM fact_loan
GROUP BY YEAR(disbursement_date),
         MONTH(disbursement_date),
         DATE_FORMAT(disbursement_date, '%Y-%m')
ORDER BY Loan_Year, Loan_Month;

-- CHART 10: LOAN AMOUNT BY STATE
SELECT b.state_name,
       COUNT(DISTINCT l.account_id) AS Total_Loans,
       SUM(l.loan_amount) AS Total_Loan_Amount
FROM fact_loan l
JOIN dim_branch b ON l.branch_id = b.branch_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY b.state_name
ORDER BY Total_Loan_Amount DESC;

-- CHART 11: LOAN AMOUNT BY REGION
SELECT b.region_name,
       COUNT(DISTINCT l.account_id) AS Total_Loans,
       SUM(l.loan_amount) AS Total_Loan_Amount
FROM fact_loan l
JOIN dim_branch b ON l.branch_id = b.branch_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY b.region_name
ORDER BY Total_Loan_Amount DESC;

-- CHART 12: LOAN AMOUNT BY PURPOSE CATEGORY
SELECT p.purpose_category,
       COUNT(DISTINCT l.account_id) AS Total_Loans,
       SUM(l.loan_amount) AS Total_Loan_Amount
FROM fact_loan l
JOIN dim_product p ON l.product_id = p.product_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY p.purpose_category
ORDER BY Total_Loan_Amount DESC;

-- CHART 13: LOAN COUNT BY PURPOSE CATEGORY
SELECT p.purpose_category,
       COUNT(DISTINCT l.account_id) AS Loan_Count
FROM fact_loan l
JOIN dim_product p ON l.product_id = p.product_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY p.purpose_category
ORDER BY Loan_Count DESC;

-- CHART 14: DEFAULT LOANS BY PRODUCT
SELECT l.product_id,
       COUNT(DISTINCT CASE
           WHEN LOWER(r.is_default_loan) = 'y' THEN l.account_id
       END) AS Default_Loans
FROM fact_loan l
LEFT JOIN fact_repayment r ON l.account_id = r.account_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY l.product_id
ORDER BY Default_Loans DESC;

-- CHART 15: DEFAULT RATE BY PRODUCT
SELECT l.product_id,
       COUNT(DISTINCT l.account_id) AS Total_Loans,
       COUNT(DISTINCT CASE
           WHEN LOWER(r.is_default_loan) = 'y' THEN l.account_id
       END) AS Default_Loans,
       ROUND(
           COUNT(DISTINCT CASE
               WHEN LOWER(r.is_default_loan) = 'y' THEN l.account_id
           END) * 100.0 /
           NULLIF(COUNT(DISTINCT l.account_id), 0), 2
       ) AS Default_Rate
FROM fact_loan l
LEFT JOIN fact_repayment r ON l.account_id = r.account_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY l.product_id
ORDER BY Default_Rate DESC;

-- CHART 16: DELINQUENCY BY PRODUCT
SELECT l.product_id,
       COUNT(DISTINCT l.account_id) AS Total_Loans,
       COUNT(DISTINCT CASE
           WHEN LOWER(r.is_delinquent_loan) = 'y' THEN l.account_id
       END) AS Delinquent_Loans,
       ROUND(
           COUNT(DISTINCT CASE
               WHEN LOWER(r.is_delinquent_loan) = 'y' THEN l.account_id
           END) * 100.0 /
           NULLIF(COUNT(DISTINCT l.account_id), 0), 2
       ) AS Delinquency_Rate
FROM fact_loan l
LEFT JOIN fact_repayment r ON l.account_id = r.account_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY l.product_id
ORDER BY Delinquency_Rate DESC;

-- CHART 17: REPAYMENT BEHAVIOR DISTRIBUTION
SELECT repayment_behavior,
       COUNT(DISTINCT account_id) AS Repayment_Count
FROM fact_repayment
GROUP BY repayment_behavior
ORDER BY Repayment_Count DESC;

-- CHART 18: REPAYMENT BEHAVIOR PERCENTAGE
SELECT repayment_behavior,
       COUNT(DISTINCT account_id) AS Repayment_Count,
       ROUND(
           COUNT(DISTINCT account_id) * 100.0 /
           NULLIF((SELECT COUNT(DISTINCT account_id)
                   FROM fact_repayment), 0), 2
       ) AS Percentage
FROM fact_repayment
GROUP BY repayment_behavior
ORDER BY Repayment_Count DESC;

-- CHART 19: LOAN AMOUNT BY GENDER
SELECT c.gender_id,
       COUNT(DISTINCT l.account_id) AS Total_Loans,
       SUM(l.loan_amount) AS Total_Loan_Amount
FROM fact_loan l
JOIN dim_client c ON l.client_id = c.client_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY c.gender_id
ORDER BY Total_Loan_Amount DESC;

-- CHART 20: LOAN AMOUNT BY AGE
SELECT c.age,
       COUNT(DISTINCT l.account_id) AS Total_Loans,
       SUM(l.loan_amount) AS Total_Loan_Amount
FROM fact_loan l
JOIN dim_client c ON l.client_id = c.client_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY c.age
ORDER BY Total_Loan_Amount DESC;

-- CHART 21: LOAN AMOUNT BY EMPLOYMENT TYPE
SELECT c.employment_type,
       COUNT(DISTINCT l.account_id) AS Total_Loans,
       SUM(l.loan_amount) AS Total_Loan_Amount
FROM fact_loan l
JOIN dim_client c ON l.client_id = c.client_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY c.employment_type
ORDER BY Total_Loan_Amount DESC;

-- CHART 22: LOAN AMOUNT BY INCOME RANGE
SELECT c.client_income_range,
       COUNT(DISTINCT l.account_id) AS Total_Loans,
       SUM(l.loan_amount) AS Total_Loan_Amount
FROM fact_loan l
JOIN dim_client c ON l.client_id = c.client_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY c.client_income_range
ORDER BY Total_Loan_Amount DESC;

-- CHART 23: CREDIT SCORE VS LOAN AMOUNT
SELECT c.credit_score,
       l.loan_amount,
       l.account_id
FROM fact_loan l
JOIN dim_client c ON l.client_id = c.client_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
  AND c.credit_score IS NOT NULL
ORDER BY c.credit_score;

-- CHART 24: LOAN AMOUNT BY CREDIT GRADE
SELECT p.grade,
       COUNT(DISTINCT l.account_id) AS Total_Loans,
       SUM(l.loan_amount) AS Total_Loan_Amount
FROM fact_loan l
JOIN dim_product p ON l.product_id = p.product_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY p.grade
ORDER BY Total_Loan_Amount DESC;

-- CHART 25: LOAN AMOUNT BY INTEREST RATE
SELECT p.int_rate,
       COUNT(DISTINCT l.account_id) AS Total_Loans,
       SUM(l.loan_amount) AS Total_Loan_Amount
FROM fact_loan l
JOIN dim_product p ON l.product_id = p.product_id
WHERE l.disbursement_date >= @start_date
  AND l.disbursement_date < @end_date
GROUP BY p.int_rate
ORDER BY p.int_rate;

-- ===========================================================
-- YEAR-WISE SUMMARY
-- ===========================================================

SELECT YEAR(disbursement_date) AS Loan_Year,
       COUNT(DISTINCT account_id) AS Total_Loans,
       COUNT(DISTINCT client_id) AS Total_Clients,
       SUM(loan_amount) AS Total_Loan_Amount,
       SUM(funded_amount) AS Total_Funded_Amount,
       ROUND(AVG(loan_amount), 2) AS Average_Loan_Size
FROM fact_loan
GROUP BY YEAR(disbursement_date)
ORDER BY Loan_Year;

-- ===========================================================
-- DATA QUALITY CHECKS
-- ===========================================================

SELECT account_id, COUNT(*) AS Row_Count
FROM fact_loan
GROUP BY account_id
HAVING COUNT(*) > 1;

SELECT client_id, COUNT(*) AS Row_Count
FROM dim_client
GROUP BY client_id
HAVING COUNT(*) > 1;

SELECT COUNT(*) AS Loans_Without_Repayment
FROM fact_loan l
LEFT JOIN fact_repayment r ON l.account_id = r.account_id
WHERE r.account_id IS NULL;

SELECT COUNT(*) AS Repayments_Without_Loan
FROM fact_repayment r
LEFT JOIN fact_loan l ON r.account_id = l.account_id
WHERE l.account_id IS NULL;

SELECT COUNT(*) AS Loans_Without_Client
FROM fact_loan l
LEFT JOIN dim_client c ON l.client_id = c.client_id
WHERE c.client_id IS NULL;

SELECT COUNT(*) AS Loans_Without_Branch
FROM fact_loan l
LEFT JOIN dim_branch b ON l.branch_id = b.branch_id
WHERE b.branch_id IS NULL;

SELECT COUNT(*) AS Loans_Without_Product
FROM fact_loan l
LEFT JOIN dim_product p ON l.product_id = p.product_id
WHERE p.product_id IS NULL;
