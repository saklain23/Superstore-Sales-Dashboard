-- drop if exists
DROP DATABASE IF NOT EXISTS Superstore;

-- drop table if exists
DROP TABLE IF EXISTS orders;

CREATE TABLE orders (
    row_id          INT PRIMARY KEY,
    order_id        VARCHAR(30),
    order_date      DATE,         
    ship_date       DATE,
    ship_mode       VARCHAR(50),
    customer_id     VARCHAR(30),
    customer_name   VARCHAR(100),
    segment         VARCHAR(50),
    country_region  VARCHAR(50),
    city            VARCHAR(50),
    state_province  VARCHAR(50),
    postal_code     VARCHAR(20),
    region          VARCHAR(50),
    product_id      VARCHAR(30),
    category        VARCHAR(50),
    sub_category    VARCHAR(50),
    product_name    TEXT,
    sales           NUMERIC(12,2),
    quantity        INT,
    discount        NUMERIC(5,2),
    profit          NUMERIC(12,2)
);

SELECT * FROM orders;


copy orders (row_id,order_id,order_date,ship_date,ship_mode,customer_id,customer_name,
             segment,country_region,city,state_province,postal_code,region,
             product_id,category,sub_category,product_name,sales,quantity,discount,profit)
FROM 'sample_-_superstore.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');



-- Q1: Year-over-Year Sales Growth
-- Compare each year's sales with the previous year 
-- and find out how much sales grew or dropped in percentage

  WITH year_growth  AS (
       SELECT TO_CHAR(order_date, 'YYYY') AS years,
		         SUM(sales) AS total_sales
       FROM orders
	   GROUP BY TO_CHAR(order_date, 'YYYY') 
),
  growth AS (
         SELECT
		       years,
		       total_sales,
		       LAG(total_sales) OVER (ORDER BY years) AS prev_sales,
		       ROUND(
                    100.0 * (total_sales - LAG(total_sales) OVER (ORDER BY years))
		            / NULLIF (LAG(total_sales) OVER (ORDER BY years ),0),2
		            ) AS growth_pct
		 FROM year_growth
      )
	    SELECT * FROM growth
		ORDER BY years;

-- Q2: Running Total of Sales
-- Add up sales day by day and show how the total revenue grew over time.

 WITH daily AS (
      SELECT
	        order_date, 
		    SUM(sales) AS revenue
	FROM orders
	GROUP BY order_date
 )
     SELECT order_date,
	        revenue,
	        SUM(revenue) OVER (ORDER BY order_date
			ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW 
		 )  AS running_total
	 FROM daily
	 ORDER BY order_date;
	 
-- Q3: Top 3 Products per Category
-- Find the top 3 best-selling products in each category.   

   WITH ranked AS(
        SELECT
		     product_name,
			 category,
			 SUM(sales) AS total_sales,
		   ROW_NUMBER() OVER (PARTITION BY category ORDER BY SUM(sales)DESC
		) AS rn
		FROM orders
		GROUP BY product_name, category
   )
       SELECT *
	   FROM ranked
	   WHERE rn<=3
	   ORDER BY category, rn;
	   
-- Q4: Above-Average Customers
-- Find customers who are spending more money than the average customer.

   WITH customer_spend AS(
          SELECT 
		     customer_id,
		     customer_name,
				 SUM(sales) AS total_spend
				 FROM orders
				 GROUP BY customer_id, customer_name
	)
	SELECT *
	FROM customer_spend
	WHERE total_spend > (SELECT AVG(total_spend)FROM customer_spend)
	ORDER BY total_spend DESC;
	   
-- Q5: Discount vs Profit
-- Check whether giving more discount increases profit or decreases it.

  WITH bucketed  AS (
             SELECT
			  CASE
			      WHEN discount = 0     THEN 'no discount'
				  WHEN discount <= 0.20 THEN 'low discount (1-20%)'
				  WHEN discount <= 0.40 THEN 'medium (21-40%)'
				  ELSE 'high (40%+)'
				  END discount_bucket,
				  sales,
				  profit
				  FROM orders 
  )
  SELECT 
       discount_bucket,
	   COUNT(*) AS total,
	   ROUND(SUM(profit),2) AS total_profit,
	   ROUND(AVG(profit),2) AS avg_profit
	   FROM bucketed
	   GROUP BY discount_bucket
	   ORDER BY discount_bucket;
  
-- Q6: Repeat vs One-time Customers
-- Find how many customers bought only once and how many came back to buy again.

   WITH customer_orders AS (
            SELECT
			     customer_id,
				 COUNT(DISTINCT order_id) AS order_count
				 FROM orders
				 GROUP BY customer_id
   )
           SELECT
              CASE 
		      WHEN order_count = 1 THEN 'one time'
		      ELSE 'repeated'
		      END AS customer_type,
		      COUNT(*) AS customers
		   FROM customer_orders
		   GROUP BY customer_type;

-- Q7: Shipping Delay by Mode
-- Find the average delivery time for each shipping mode and see which mode has the most delay.

      WITH delivery AS (
    SELECT
        ship_mode,
        ship_date - order_date AS delivery_days
    FROM orders
)
SELECT
    ship_mode,
    ROUND(AVG(delivery_days), 2) AS avg_days,
    MIN(delivery_days) AS min_days,
    MAX(delivery_days) AS max_days,
    COUNT(*) AS orders
FROM delivery
GROUP BY ship_mode
ORDER BY avg_days DESC;

-- Q8: RFM Segmentation
-- Score each customer on Recency, Frequency, Monetary. Then segment them into:
-- Champion, Loyal, At Risk, Lost.

	 WITH rfm_base AS(
          SELECT customer_id,
		         MAX(order_date) AS recency_date,
				 COUNT(DISTINCT order_id) AS frequency,
				 SUM(sales) AS monetary
				 FROM orders
				 GROUP BY customer_id
	 ),
    rfm_score AS(
         SELECT *,
		 NTILE(4) OVER (ORDER BY recency_date DESC) AS r_score,
		 NTILE(4) OVER (ORDER BY frequency DESC) AS f_score,
		 NTILE(4) OVER (ORDER BY monetary DESC) AS m_score
		 FROM rfm_base
	),
	segments AS (
         SELECT*,
		 CASE 
		 WHEN r_score = 4 AND f_score >=3 AND m_score >= 3 THEN 'champion'
		 WHEN r_score >= 3 AND f_score >=3 THEN 'loyal'
		 WHEN r_score <=2 AND f_score >=3 THEN 'at risk'
		 ELSE 'lost'
		 END AS segment_status
		 FROM rfm_score
		 
	)
	SELECT
	 segment_status,
	 COUNT(*) AS customers
	 FROM segments
	 GROUP BY segment_status
	 ORDER BY customers DESC;

	
-- Q9: Pareto Analysis (80/20 Rule)
-- Check whether 20% of products are bringing 80% of sales.

	WITH product_sales AS(
          SELECT product_name,
		  SUM(sales) AS sum_of_sales
		  FROM orders
		  GROUP BY product_name
	),
	
	cumulative AS (
	       SELECT*,
		   SUM(sum_of_sales) OVER (ORDER BY sum_of_sales DESC) AS cumulative_sales,
		   SUM(sum_of_sales) OVER () AS total_sales,
		   ROW_NUMBER() OVER (ORDER BY sum_of_sales DESC) AS rn,
		   COUNT(*) OVER () AS total_product
		   FROM product_sales),
	pareto AS (
	         SELECT*,
             ROUND(100.0 * cumulative_sales / total_sales,2) AS cumulative_pct,
			 ROUND(100.0 * rn / total_product,2) AS product_pct
			 FROM cumulative)
     
	SELECT product_name,
	       sum_of_sales,
		   cumulative_pct,
		   product_pct
		   FROM pareto
		   WHERE product_pct <=20
	ORDER BY product_pct DESC LIMIT 5;

-- Q10: Cohort Retention
-- Find which year's customers were the most loyal and kept buying in the following years.

  WITH cohort AS(
          SELECT customer_id,
		        MIN(TO_CHAR(order_date, 'YYYY')) AS years
				FROM orders
				GROUP BY customer_id
  ),
  activity AS (
                 SELECT DISTINCT 
				           customer_id,
				           EXTRACT(YEAR FROM order_date) AS activity_years
						   FROM orders
  ),
  cohort_activity AS (
        SELECT a.customer_id,
		        c.years AS cohort_years,
				a.activity_years
				FROM activity a
				JOIN cohort c ON a.customer_id = c.customer_id
	),
				
	cohort_count AS(
                 SELECT 
				 cohort_years,
				 activity_years,
				 COUNT (DISTINCT customer_id) AS customers
				 FROM cohort_activity
				 GROUP BY cohort_years, activity_years
				 ),

	retention AS (
          SELECT cohort_years,
		  activity_years,
		  customers,
		  MAX(customers) OVER (PARTITION BY cohort_years) AS cohort_base,
		  ROUND(100.0 * customers / MAX(customers) OVER (PARTITION BY cohort_years),2) AS retention_pct
		  FROM cohort_count
	)
	SELECT cohort_years,
	        activity_years,
			customers,
			cohort_base,
			retention_pct
			FROM retention
		    ORDER BY cohort_years, activity_years;
			
-- Q11: Month-over-Month Growth
-- Compare each month's sales with the previous month and show which months 
-- sales went up and which went down.				 

  WITH monthly AS(
     SELECT DATE_TRUNC('month', order_date)::DATE AS months,
	 SUM(sales) AS sales
	 FROM orders
	 GROUP BY months
  ),
     growth AS(
     SELECT months,
	        sales,
			LAG(sales) OVER (ORDER BY months) AS prev_sales,
			ROUND(100.0 * (sales - LAG(sales) OVER (ORDER BY months))
			/ NULLIF(LAG(sales) OVER (ORDER BY months),0),2)
			AS growth_pct
			FROM monthly
	 )
	 SELECT * FROM growth
	 ORDER BY months;
	 
-- Q12: Region-wise Sales & Profit
-- Find total sales, total profit, and profit margin for each region and compare them.	 

 WITH compare AS (
    SELECT region,
           SUM(sales) AS total_sales,
           SUM(profit) AS total_profit
    FROM orders
    GROUP BY region
),
margin AS (
    SELECT region,
           total_sales,
           total_profit,
           ROUND(100.0 * total_profit / NULLIF(total_sales, 0), 2) AS profit_margin
    FROM compare
)
SELECT * FROM margin
ORDER BY profit_margin DESC;

-- Q13: Profit Margin Pivot (Region × Category)
-- Find the profit margin for each region and category combination and see 
-- which combination is the most profitable.
   SELECT region,
          ROUND(100.0 * SUM(CASE WHEN category = 'Furniture' THEN profit ELSE 0 END)
		  / NULLIF (SUM(CASE WHEN category = 'Furniture' THEN sales ELSE 0 END),0),2) AS furniture_margin,

		  ROUND(100.0 * SUM(CASE WHEN category = 'Technology' THEN profit ELSE 0 END)
		  / NULLIF (SUM(CASE WHEN category = 'Technology' THEN sales ELSE 0 END),0),2) AS tech_margin,

		  ROUND(100.0 * SUM(CASE WHEN category = 'Office Supplies' THEN profit ELSE 0 END)
		  / NULLIF (SUM(CASE WHEN category = 'Office Supplies' THEN sales ELSE 0 END),0),2) AS office_margin
		  FROM orders
		  GROUP BY region
		  ORDER BY region;

-- Q14: Consistently Loss-Making Products
-- Find products that lose money every single year, not just once.

 WITH yearly_profit AS(
       SELECT 
	          product_name,
			  DATE_TRUNC('year', order_date)::DATE AS years,
			  SUM(profit) AS total_profit
			  FROM orders
			  GROUP BY product_name, years
 ),
 yearly_count AS(
      SELECT
	     product_name,
	     COUNT(*) AS total_years,
		 COUNT(*) FILTER (WHERE total_profit < 0) AS loss_years
		 FROM yearly_profit
		 GROUP BY product_name
		 
 )
SELECT*
FROM yearly_count
WHERE loss_years = total_years AND total_years >=2;


-- Q15: Customer Lifetime Value (CLV)
-- Find the most valuable customer in each segment and show how much money 
-- they spent in total, and their rank within the segment.
  WITH customer_stats AS(
    SELECT customer_id,
	       segment,
        COUNT(DISTINCT order_id) AS order_count,
		SUM(sales) AS total_spend,
		ROUND(AVG(sales),2) AS avg_sales,
		MIN(order_date) AS first_order,
		MAX(order_date) AS last_order,
   ROUND((MAX(order_date) - MIN(order_date))/ 365.0,2) AS lifespan_year,
   ROUND(COUNT(DISTINCT order_id) / NULLIF ((MAX(order_date) - MIN(order_date)) / 365.0,0),2) AS order_per_year
    FROM orders
    GROUP BY customer_id, segment
	),
   ranked AS (
       SELECT*,
	   RANK() OVER (PARTITION BY segment ORDER BY total_spend DESC) AS rn_in_segment
	   FROM customer_stats
  )
  SELECT segment,
         customer_id,
         total_spend,
		 rn_in_segment
		 FROM ranked
		 WHERE rn_in_segment <=5
		 ORDER BY segment, rn_in_segment;
   
	
	
	




















