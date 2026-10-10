CREATE DATABASE IF NOT EXISTS marketing_analytics;
USE marketing_analytics;

SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_name LIKE '%conversion%' OR table_name LIKE '%ads%';


RENAME TABLE marketing_analytics.kag_conversion_data TO marketing_analytics.ads;

SELECT COUNT(*) FROM ads;

-- - ASSUMPTIONS ->
--   1) Total_Conversion = enquiries, Approved_Conversion = sales (confirm on the Kaggle page)
--   2) The dataset has NO revenue column. ROI in Q3 uses ASSUMED revenue per sale (30 / 50 / 100)

SELECT COUNT(*) FROM ads;        -- 1143 aana chahiye
SELECT * FROM ads LIMIT 10;

-- =================================================================

USE marketing_analytics;

-- [CHECK A] Row count. Expected: 1143
SELECT COUNT(*) AS total_rows FROM ads;

-- [CHECK B] Ads per campaign. Expected: 916 -> 54, 936 -> 464, 1178 -> 625
SELECT xyz_campaign_id, COUNT(*) AS ads FROM ads GROUP BY xyz_campaign_id;

-- [CHECK C] Totals. Expected: impressions 213434828, clicks 38165, spend 58705.23, sales 1079
SELECT SUM(impressions) AS impressions, SUM(clicks) AS clicks,
       ROUND(SUM(spent), 2) AS spend, SUM(approved_conversion) AS sales
FROM ads;


-- [0.1] Data quality checks
SELECT COUNT(*)                                        AS total_ads,
       COUNT(DISTINCT ad_id)                           AS unique_ads,
       COUNT(DISTINCT xyz_campaign_id)                 AS campaigns,
       SUM(CASE WHEN spent = 0 THEN 1 ELSE 0 END)      AS ads_with_zero_spend,
       SUM(CASE WHEN impressions IS NULL OR clicks IS NULL OR spent IS NULL THEN 1 ELSE 0 END) AS rows_with_nulls,
       SUM(CASE WHEN clicks > impressions THEN 1 ELSE 0 END)                                   AS clicks_more_than_impressions,
       SUM(CASE WHEN approved_conversion > total_conversion THEN 1 ELSE 0 END)                 AS sales_more_than_enquiries
FROM ads;


-- =====================================================================
-- SECTION 1 : CAMPAIGN PERFORMANCE
-- =====================================================================

-- [Q1] Core ad metrics per campaign: CTR, CPC, CPM, cost per enquiry, cost per sale
SELECT xyz_campaign_id                                                  AS campaign,
       COUNT(*)                                                         AS ads,
       SUM(impressions)                                                 AS impressions,
       SUM(clicks)                                                      AS clicks,
       ROUND(SUM(spent), 2)                                             AS spend,
       SUM(total_conversion)                                            AS enquiries,
       SUM(approved_conversion)                                         AS sales,
       ROUND(100.0 * SUM(clicks) / SUM(impressions), 3)                 AS ctr_pct,
       ROUND(SUM(spent) / NULLIF(SUM(clicks), 0), 3)                    AS cpc,
       ROUND(1000.0 * SUM(spent) / SUM(impressions), 2)                 AS cpm,
       ROUND(SUM(spent) / NULLIF(SUM(total_conversion), 0), 2)          AS cost_per_enquiry,
       ROUND(SUM(spent) / NULLIF(SUM(approved_conversion), 0), 2)       AS cost_per_sale
FROM ads
GROUP BY xyz_campaign_id
ORDER BY cost_per_sale;
-- insights:
-- campaign performance
-- Campaign 916 has the lowest cost per sale (6.24), followed by 936 (15.81) and 1178 (63.83).
-- Campaign 1178 also has the lowest CTR (0.018%) and the highest CPC (1.54).

-- [Q2] Marketing funnel per campaign: impressions -> clicks -> enquiries -> sales (LAG window function)
WITH stages AS (
    SELECT xyz_campaign_id AS campaign, 1 AS step_no, 'impressions' AS stage, SUM(impressions)         AS volume FROM ads GROUP BY xyz_campaign_id
    UNION ALL
    SELECT xyz_campaign_id, 2, 'clicks',      SUM(clicks)              FROM ads GROUP BY xyz_campaign_id
    UNION ALL
    SELECT xyz_campaign_id, 3, 'enquiries',   SUM(total_conversion)    FROM ads GROUP BY xyz_campaign_id
    UNION ALL
    SELECT xyz_campaign_id, 4, 'sales',       SUM(approved_conversion) FROM ads GROUP BY xyz_campaign_id
)
SELECT campaign,
       step_no,
       stage,
       volume,
       ROUND(100.0 * volume / LAG(volume) OVER (PARTITION BY campaign ORDER BY step_no), 3) AS pct_of_previous_stage
FROM stages
ORDER BY campaign, step_no;

-- key insight
-- marketing funnel
-- Campaign 1178 loses most of its customers between click and enquiry:
-- only 7.4% of clicks become enquiries, compared with 27.1% in campaign 936 and 51.3% in campaign 916.
-- The enquiry-to-sale rate is similar across all three (33% to 41%).

-- [Q3] ROI and ROAS per campaign using an ASSUMED revenue per sale (sensitivity analysis)
--      break_even_revenue_per_sale = the minimum revenue per sale at which the campaign does not lose money
--      The 30 / 50 / 100 below are placeholders. After running Q1, change them to values around your
--      real cost_per_sale so the sensitivity table shows where each campaign turns profitable.
WITH assumptions AS (
    SELECT 30.0 AS revenue_per_sale
    UNION ALL SELECT 50.0
    UNION ALL SELECT 100.0
),
camp AS (
    SELECT xyz_campaign_id AS campaign,
           SUM(spent)               AS spend,
           SUM(approved_conversion) AS sales
    FROM ads
    GROUP BY xyz_campaign_id
)
SELECT c.campaign,
       ROUND(c.spend, 2)                                         AS spend,
       c.sales,
       a.revenue_per_sale,
       ROUND(c.sales * a.revenue_per_sale, 2)                    AS assumed_revenue,
       ROUND(c.sales * a.revenue_per_sale / c.spend, 2)          AS roas,
       ROUND(100.0 * (c.sales * a.revenue_per_sale - c.spend) / c.spend, 1) AS roi_pct,
       ROUND(c.spend / NULLIF(c.sales, 0), 2)                    AS break_even_revenue_per_sale
FROM camp c
CROSS JOIN assumptions a
ORDER BY c.campaign, a.revenue_per_sale;

-- key insight:
-- : ROI and break-even
-- Assuming a revenue of 50 per sale, campaigns 916 and 936 are highly profitable (ROI of +701% and +216%), while campaign 1178 loses money (-21.7%).
-- Campaign 1178 only breaks even when each sale brings in at least 63.83.


-- =====================================================================
-- SECTION 2 : AUDIENCE ANALYSIS
-- =====================================================================

-- [Q4] Best age and gender segment inside each campaign (RANK + PARTITION BY)
WITH seg AS (
    SELECT xyz_campaign_id AS campaign,
           age,
           gender,
           SUM(spent)               AS spend,
           SUM(approved_conversion) AS sales
    FROM ads
    GROUP BY xyz_campaign_id, age, gender
    HAVING SUM(approved_conversion) > 0
)
SELECT campaign,
       age,
       gender,
       ROUND(spend, 2)                 AS spend,
       sales,
       ROUND(spend / sales, 2)         AS cost_per_sale,
       RANK() OVER (PARTITION BY campaign ORDER BY spend / sales) AS efficiency_rank
FROM seg
ORDER BY campaign, efficiency_rank;

-- key insights:
-- Age and gender segments
-- In campaign 1178, men aged 30-34 are the cheapest segment (30.77 per sale) and women aged 45-49 the most expensive (137.76), which is about 4.5 times higher.
-- The same pattern appears in campaign 936 (2.81 versus 62.30).

-- [Q5] Top interest segments by sales, with efficiency (ignore tiny segments)
SELECT interest,
       COUNT(*)                                                   AS ads,
       ROUND(SUM(spent), 2)                                       AS spend,
       SUM(approved_conversion)                                   AS sales,
       ROUND(SUM(spent) / NULLIF(SUM(approved_conversion), 0), 2) AS cost_per_sale,
       ROUND(100.0 * SUM(approved_conversion) / NULLIF(SUM(total_conversion), 0), 1) AS enquiry_to_sale_pct
FROM ads
GROUP BY interest
HAVING SUM(spent) >= 100
ORDER BY sales DESC
LIMIT 10;

-- key insights:
-- Interest segments

-- Interest 16 drives the most sales (141) at 57.34 per sale, while interest 29 delivers 132 sales at a lower cost of 38.22.
-- Interest 27 is a weak performer, with 54 sales at 95.85 per sale.

-- =====================================================================
-- SECTION 3 : WASTE AND BUDGET OPTIMISATION
-- =====================================================================

-- [Q6] Wasted spend: money spent on ads that produced zero sales
SELECT xyz_campaign_id                                              AS campaign,
       COUNT(*)                                                     AS zero_sale_ads,
       ROUND(SUM(spent), 2)                                         AS wasted_spend,
       ROUND(100.0 * SUM(spent) / (SELECT SUM(spent) FROM ads), 2)  AS pct_of_total_budget
FROM ads
WHERE approved_conversion = 0 AND spent > 0
GROUP BY xyz_campaign_id
ORDER BY wasted_spend DESC;

-- key insight:
-- Wasted spend
-- 423 ads spent money but produced no sales, wasting 14,754 or about 25% of the total budget. Campaign 1178 alone accounts for 12,770 of this (21.75% of the total budget).

-- [Q7] Ad quality quadrant: compare every ad's CTR and sales-per-click with the overall average
WITH overall AS (
    SELECT 1.0 * SUM(clicks) / SUM(impressions)             AS avg_ctr,
           1.0 * SUM(approved_conversion) / SUM(clicks)     AS avg_sales_per_click
    FROM ads
),
ad_level AS (
    SELECT ad_id,
           xyz_campaign_id,
           spent,
           1.0 * clicks / impressions                        AS ctr,
           1.0 * approved_conversion / NULLIF(clicks, 0)     AS sales_per_click
    FROM ads
    WHERE impressions > 0 AND clicks > 0
)
SELECT CASE WHEN a.ctr >= o.avg_ctr AND a.sales_per_click >= o.avg_sales_per_click THEN '1) Star: clicks and sells'
            WHEN a.ctr >= o.avg_ctr                                                THEN '2) Clicks but does not sell'
            WHEN a.sales_per_click >= o.avg_sales_per_click                        THEN '3) Quiet seller: scale it'
            ELSE                                                                        '4) Underperformer' END AS ad_type,
       COUNT(*)                          AS ads,
       ROUND(SUM(a.spent), 2)            AS spend,
       ROUND(100.0 * SUM(a.spent) / (SELECT SUM(spent) FROM ads), 1) AS pct_of_budget
FROM ad_level a
CROSS JOIN overall o
GROUP BY 1
ORDER BY 1;

-- key insight:
-- Ad quality quadrant
-- 334 ads (43.8% of the budget) attract clicks but convert poorly, whereas the 154 “star” ads that both attract clicks and sell receive only 10.5% of the budget.
-- The 218 “quiet seller” ads convert well and could be scaled up.

-- [Q8] Budget share vs sales share per campaign (efficiency index above 1 = deserves more budget)
WITH camp AS (
    SELECT xyz_campaign_id AS campaign,
           SUM(spent)               AS spend,
           SUM(approved_conversion) AS sales
    FROM ads
    GROUP BY xyz_campaign_id
)
SELECT campaign,
       ROUND(100.0 * spend / SUM(spend) OVER (), 1)               AS budget_share_pct,
       ROUND(100.0 * sales / SUM(sales) OVER (), 1)               AS sales_share_pct,
       ROUND((1.0 * sales / SUM(sales) OVER ()) / (spend / SUM(spend) OVER ()), 2) AS efficiency_index
FROM camp
ORDER BY efficiency_index DESC;

-- key insight:
-- Budget share versus sales share
-- Campaign 1178 takes 94.8% of the budget but delivers only 80.8% of sales (efficiency index 0.85).
-- Campaigns 916 and 936 deliver far more sales than their budget share (efficiency index 8.72 and 3.44).



-- [Q9] Quartiles of ad efficiency (NTILE): how much cheaper are the best ads than the worst ones?
WITH ranked AS (
    SELECT ad_id,
           spent,
           approved_conversion,
           NTILE(4) OVER (ORDER BY spent / approved_conversion) AS quartile   -- 1 = cheapest per sale
    FROM ads
    WHERE approved_conversion > 0 AND spent > 0
)
SELECT quartile,
       COUNT(*)                                  AS ads,
       ROUND(SUM(spent), 2)                      AS spend,
       SUM(approved_conversion)                  AS sales,
       ROUND(SUM(spent) / SUM(approved_conversion), 2) AS cost_per_sale
FROM ranked
GROUP BY quartile
ORDER BY quartile;

-- key insight:
-- Efficiency quartiles
-- The best quartile of ads costs 3.17 per sale and the worst quartile costs 112.13, a gap of about 35 times
-- The worst quartile spent 23,434 to produce 209 sales, while the best quartile spent only 501 to produce 158.


-- [Q10] Pareto: how few ads drive most of the sales? (cumulative window function)
WITH ad_sales AS (
    SELECT ad_id, approved_conversion AS sales
    FROM ads
    WHERE approved_conversion > 0
),
ordered AS (
    SELECT ad_id,
           sales,
           ROW_NUMBER() OVER (ORDER BY sales DESC, ad_id)                                               AS ad_rank,
           SUM(sales) OVER (ORDER BY sales DESC, ad_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_sales,
           SUM(sales) OVER ()                                                                           AS total_sales,
           COUNT(*) OVER ()                                                                             AS total_ads
    FROM ad_sales
)
SELECT ad_rank,
       ad_id,
       sales,
       ROUND(100.0 * running_sales / total_sales, 1)  AS cumulative_sales_pct,
       ROUND(100.0 * ad_rank / total_ads, 1)          AS cumulative_ads_pct
FROM ordered
WHERE ad_rank <= 20
ORDER BY ad_rank;

-- key insight:
-- Pareto analysis
-- The top 20 ads, which are 3.4% of the ads that made a sale, generated 19.6% of all sales.
-- Sales are therefore moderately concentrated, and the strongest ads should be studied and replicated.


-- Overall conclusion
-- “The largest campaign takes 95% of the budget but converts poorly after the click,
--  so shifting budget towards better campaigns and audience segments, and cutting zero-sale 
--  ads, would lower the cost per sale.”

-- A tip for the interview: when you explain a query, use this order: question, 
-- result, business action. For example, for Q6: “I wanted to know how much budget
--  was wasted; 25% produced no sales; so I would pause those ads first.”



-- # Ad Campaign Performance & ROI Analysis (SQL)

-- **Tools:** MySQL 8.0, MySQL Workbench | **Skills:** CTEs, window functions (RANK, NTILE, LAG, running totals), CASE WHEN, aggregation, sensitivity analysis

-- ## Business problem
-- A marketing team ran three Facebook ad campaigns and wants to know:
-- - Which campaign brings in a sale at the lowest cost?
-- - Which audience segments (age, gender, interest) are the most and least efficient?
-- - How much budget is wasted, and where should it move?

-- ## Dataset
-- "Sales Conversion Optimization" (Kaggle), `KAG_conversion_data.csv`: **1,143 ads** from **3 campaigns** (916, 936, 1178).
-- Columns: ad_id, campaign ids, age, gender, interest, Impressions, Clicks, Spent, Total_Conversion (enquiries), Approved_Conversion (sales).

-- ## Data checks
-- No NULL values, no duplicate ad_id, no ad with clicks above impressions, and no ad with more sales than enquiries.
-- 207 ads received zero clicks and therefore have zero spend, so ratios use `NULLIF` to avoid division by zero.

-- ## Key findings
-- | Campaign | Ads | Spend | Sales | CPC | Cost per sale |
-- |---|---|---|---|---|---|
-- | 916 | 54 | 149.71 | 24 | 1.32 | 6.24 |
-- | 936 | 464 | 2,893.37 | 183 | 1.46 | 15.81 |
-- | 1178 | 625 | 55,662.15 | 872 | 1.54 | 63.83 |

-- 1. **Budget is concentrated in the least efficient campaign.** Campaign 1178 received 94.8% of the spend but produced 80.8% of the sales (efficiency index 0.85). Its cost per sale is about 4x that of campaign 936.
-- 2. **The problem is conversion, not click price.** CPC is similar across campaigns (1.32 to 1.54). The gap comes from the click-to-enquiry rate: 51.3% (916), 27.1% (936) and only 7.4% (1178). Enquiry-to-sale rates are close (33% to 41%).
-- 3. **About 25% of the budget produced no sales.** 423 ads with spend generated zero sales, costing 14,754 in total, of which 12,770 (21.75% of the whole budget) sits in campaign 1178.
-- 4. **Large gap between the best and worst ads.** Ads in the cheapest quartile cost 3.17 per sale versus 112.13 in the most expensive quartile (about 35x).
-- 5. **Audience pattern.** In campaigns 936 and 1178, women aged 45-49 were the most expensive segment (62.30 and 137.76 per sale), while men aged 30-34 were the cheapest (2.81 and 30.77).
-- 6. **Click quality.** 334 ads (43.8% of spend) get above-average clicks but below-average sales per click.
-- 7. **Profitability depends on revenue per sale.** With an assumed revenue of 50 per sale, campaigns 916 and 936 are profitable (ROI +701% and +216%) while 1178 loses money (ROI -21.7%). Campaign 1178 breaks even only at about 64 revenue per sale.

-- ## Recommendations
-- - Cap or reduce spend on campaign 1178 until its click-to-enquiry rate improves (landing page, ad message, audience), and pause the zero-sale ads.
-- - Test shifting part of the budget to campaigns 916 and 936 and measure whether their cost per sale holds at higher spend.
-- - Shift budget within each campaign from women 45-49 towards the best-performing segments, and review interests 29 and 16, which drive the most sales.

-- ## Assumptions and limitations
-- - Total_Conversion is treated as enquiries and Approved_Conversion as sales (as described on the Kaggle dataset page).
-- - The dataset has **no revenue column**. ROI uses assumed revenue per sale (30, 50, 100) for a sensitivity analysis; real revenue data is needed for a true ROI.
-- - Campaign 916 has only 54 ads and very low spend, so its efficiency may not hold at a larger scale. Moving budget there is a hypothesis to test, not a proven result.
-- - Spend is in the dataset's own currency units (not stated).

-- ## Files
-- - `03_roi_queries_ready_to_run.sql`: all queries (data checks, Q1 to Q10).

-- ## SQL queries
-- | # | Question | Techniques |
-- |---|---|---|
-- | Q1 | Campaign metrics: CTR, CPC, CPM, cost per sale | GROUP BY, NULLIF |
-- | Q2 | Impressions to clicks to enquiries to sales funnel | UNION ALL, LAG |
-- | Q3 | ROI, ROAS and break-even at assumed revenue | CTE, CROSS JOIN |
-- | Q4 | Best age/gender segment per campaign | RANK, PARTITION BY |
-- | Q5 | Top interests by sales and efficiency | HAVING |
-- | Q6 | Wasted spend on zero-sale ads | Subquery |
-- | Q7 | Ad quality quadrant (CTR vs sales per click) | CTE, CASE WHEN |
-- | Q8 | Budget share vs sales share per campaign | Window SUM OVER |
-- | Q9 | Efficiency quartiles | NTILE |
-- | Q10 | Pareto: share of sales from the top ads | Running total window |