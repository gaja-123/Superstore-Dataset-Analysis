use  superstore_db;
-- 1. Which regions have the highest median sales and profits?
WITH RankedSales AS (
    SELECT Region, Sales,
           ROW_NUMBER() OVER (PARTITION BY Region ORDER BY Sales) AS rn,
           COUNT(*) OVER (PARTITION BY Region) AS cnt
    FROM superstore
)
SELECT Region,
       AVG(Sales) AS Median_Sales
FROM RankedSales
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
GROUP BY Region;

WITH RankedProfits AS (
    SELECT Region, Profit,
           ROW_NUMBER() OVER (PARTITION BY Region ORDER BY Profit) AS rn,
           COUNT(*) OVER (PARTITION BY Region) AS cnt
    FROM superstore
)
SELECT Region,
       AVG(Profit) AS Median_Profit
FROM RankedProfits
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
GROUP BY Region;

-- 2. What are the median profit margins by category?

WITH RankedMargins AS (
    SELECT Category,
           Profit / Sales AS Profit_Margin,
           ROW_NUMBER() OVER (PARTITION BY Category ORDER BY Profit / Sales) AS rn,
           COUNT(*) OVER (PARTITION BY Category) AS cnt
    FROM superstore
    WHERE Sales != 0
)
SELECT Category,
       AVG(Profit_Margin) AS Median_Profit_Margin
FROM RankedMargins
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
GROUP BY Category;


-- 3.How do profit margins vary across discount ranges?

WITH Discounted AS (
    SELECT 
        CASE
            WHEN Discount BETWEEN 0 AND 0.2 THEN '0-20%'
            WHEN Discount > 0.2 AND Discount <= 0.3 THEN '20-30%'
            WHEN Discount > 0.3 AND Discount <= 0.5 THEN '30-50%'
            WHEN Discount > 0.5 AND Discount <= 0.8 THEN '50-80%'
            WHEN Discount > 0.8 AND Discount <= 1 THEN '80-100%'
        END AS Discount_Group,
        Profit / Sales AS Profit_Margin
    FROM superstore
    WHERE Sales != 0
),
Ranked AS (
    SELECT 
        Discount_Group,
        Profit_Margin,
        ROW_NUMBER() OVER (PARTITION BY Discount_Group ORDER BY Profit_Margin) AS rn,
        COUNT(*) OVER (PARTITION BY Discount_Group) AS cnt
    FROM Discounted
)
SELECT 
    Discount_Group,
    ROUND(AVG(Profit_Margin), 4) AS Median_Profit_Margin
FROM Ranked
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
GROUP BY Discount_Group
ORDER BY Median_Profit_Margin DESC;

-- 4.What is the median order frequency by customer segment?
WITH RFM AS (
    SELECT 
        Customer_ID,
        Region,
        DATEDIFF('2025-07-24', MAX(Order_Date)) AS recency,
        COUNT(DISTINCT Order_ID) AS frequency,
        SUM(Sales) AS monetary
    FROM superstore
    GROUP BY Customer_ID, Region
),
Ranked AS (
    SELECT *,
        RANK() OVER (PARTITION BY Region ORDER BY recency ASC) AS recency_rank,  -- reverse for descending
        RANK() OVER (PARTITION BY Region ORDER BY frequency) AS frequency_rank,
        RANK() OVER (PARTITION BY Region ORDER BY monetary) AS monetary_rank
    FROM RFM
),
Scored AS (
    SELECT *,
        NTILE(5) OVER (PARTITION BY Region ORDER BY recency_rank) AS recency_score,
        NTILE(5) OVER (PARTITION BY Region ORDER BY frequency_rank) AS frequency_score,
        NTILE(5) OVER (PARTITION BY Region ORDER BY monetary_rank) AS monetary_score
    FROM Ranked
),
Segmented AS (
    SELECT *,
        CASE
            WHEN recency_score >= 4 AND frequency_score >= 4 AND monetary_score >= 4 THEN 'High-Value'
            WHEN recency_score <= 2 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'Loyal'
            WHEN recency_score <= 2 AND frequency_score <= 2 THEN 'At-Risk'
            WHEN recency_score >= 3 AND frequency_score <= 2 THEN 'Lost'
            ELSE 'Other'
        END AS customer_segment
    FROM Scored
),
FrequencyRanked AS (
    SELECT 
        customer_segment,
        frequency,
        ROW_NUMBER() OVER (PARTITION BY customer_segment ORDER BY frequency) AS rn,
        COUNT(*) OVER (PARTITION BY customer_segment) AS cnt
    FROM Segmented
)
SELECT 
    customer_segment,
    ROUND(AVG(frequency), 2) AS Median_Order_Frequency
FROM FrequencyRanked
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
GROUP BY customer_segment
ORDER BY FIELD(customer_segment, 'High-Value', 'Loyal', 'Other', 'At-Risk', 'Lost');





-- 5.How does Furniture’s profit margin compare to other categories?

WITH Categorized AS (
    SELECT 
        Category,
        CASE 
            WHEN Category = 'Furniture' THEN 'Furniture'
            ELSE 'Others'
        END AS category_group,
        ROUND(Profit / Sales, 4) AS profit_margin
    FROM superstore
    WHERE Sales > 0
),
Ranked AS (
    SELECT 
        category_group,
        profit_margin,
        ROW_NUMBER() OVER (PARTITION BY category_group ORDER BY profit_margin) AS rn,
        COUNT(*) OVER (PARTITION BY category_group) AS cnt
    FROM Categorized
)
SELECT 
    category_group,
    ROUND(AVG(profit_margin), 4) AS Median_Profit_Margin
FROM Ranked
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
GROUP BY category_group
ORDER BY Median_Profit_Margin DESC;


-- 6. Is there significant variation in profit across quarters?

WITH Quarterly AS (
    SELECT 
        QUARTER(Order_Date) AS quarter,
        ROUND(Profit, 2) AS profit
    FROM superstore
    WHERE Profit IS NOT NULL
),
Ranked AS (
    SELECT 
        quarter,
        profit,
        ROW_NUMBER() OVER (PARTITION BY quarter ORDER BY profit) AS rn,
        COUNT(*) OVER (PARTITION BY quarter) AS cnt
    FROM Quarterly
)
SELECT 
    CONCAT('Q', quarter) AS Quarter,
    ROUND(AVG(profit), 2) AS Median_Profit
FROM Ranked
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
GROUP BY quarter
ORDER BY quarter;


-- 7.a.What are the monthly median profits for top 10% customers ?

WITH CustomerProfit AS (
    SELECT 
        Customer_ID,
        SUM(Profit) AS total_profit
    FROM superstore
    GROUP BY Customer_ID
),
RankedCustomers AS (
    SELECT 
        Customer_ID,
        total_profit,
        NTILE(10) OVER (ORDER BY total_profit DESC) AS decile
    FROM CustomerProfit
),
TopCustomers AS (
    SELECT Customer_ID
    FROM RankedCustomers
    WHERE decile = 1
),
MonthlyProfit AS (
    SELECT 
        MONTH(Order_Date) AS month_num,
        ROUND(Profit, 2) AS profit
    FROM superstore
    WHERE Customer_ID IN (SELECT Customer_ID FROM TopCustomers)
      AND Order_Date IS NOT NULL
      AND Profit IS NOT NULL
),
Ranked AS (
    SELECT 
        month_num,
        profit,
        ROW_NUMBER() OVER (PARTITION BY month_num ORDER BY profit) AS rn,
        COUNT(*) OVER (PARTITION BY month_num) AS cnt
    FROM MonthlyProfit
),
Named AS (
    SELECT 
        month_num,
        CASE month_num
            WHEN 1 THEN 'January'
            WHEN 2 THEN 'February'
            WHEN 3 THEN 'March'
            WHEN 4 THEN 'April'
            WHEN 5 THEN 'May'
            WHEN 6 THEN 'June'
            WHEN 7 THEN 'July'
            WHEN 8 THEN 'August'
            WHEN 9 THEN 'September'
            WHEN 10 THEN 'October'
            WHEN 11 THEN 'November'
            WHEN 12 THEN 'December'
        END AS Month,
        profit,
        rn,
        cnt
    FROM Ranked
)
SELECT 
    Month,
    ROUND(AVG(profit), 2) AS Median_Profit
FROM Named
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
GROUP BY Month
ORDER BY FIELD(Month,
    'January','February','March','April','May','June',
    'July','August','September','October','November','December');
    
-- 7.b What are the monthly median profits for top 10%  products?
WITH ProductProfit AS (
    SELECT 
        Product_ID,
        SUM(Profit) AS total_profit
    FROM superstore
    GROUP BY Product_ID
),
RankedProducts AS (
    SELECT 
        Product_ID,
        total_profit,
        NTILE(10) OVER (ORDER BY total_profit DESC) AS decile
    FROM ProductProfit
),
TopProducts AS (
    SELECT Product_ID
    FROM RankedProducts
    WHERE decile = 1
),
MonthlyProfit AS (
    SELECT 
        MONTH(Order_Date) AS month_num,
        ROUND(Profit, 2) AS profit
    FROM superstore
    WHERE Product_ID IN (SELECT Product_ID FROM TopProducts)
      AND Order_Date IS NOT NULL
      AND Profit IS NOT NULL
),
Ranked AS (
    SELECT 
        month_num,
        profit,
        ROW_NUMBER() OVER (PARTITION BY month_num ORDER BY profit) AS rn,
        COUNT(*) OVER (PARTITION BY month_num) AS cnt
    FROM MonthlyProfit
),
Named AS (
    SELECT 
        month_num,
        CASE month_num
            WHEN 1 THEN 'January'
            WHEN 2 THEN 'February'
            WHEN 3 THEN 'March'
            WHEN 4 THEN 'April'
            WHEN 5 THEN 'May'
            WHEN 6 THEN 'June'
            WHEN 7 THEN 'July'
            WHEN 8 THEN 'August'
            WHEN 9 THEN 'September'
            WHEN 10 THEN 'October'
            WHEN 11 THEN 'November'
            WHEN 12 THEN 'December'
        END AS Month,
        profit,
        rn,
        cnt
    FROM Ranked
)
SELECT 
    Month,
    ROUND(AVG(profit), 2) AS Median_Profit
FROM Named
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
GROUP BY Month
ORDER BY FIELD(Month,
    'January','February','March','April','May','June',
    'July','August','September','October','November','December');


---



