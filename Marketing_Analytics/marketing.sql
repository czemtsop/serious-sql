/******************************************************************************
  This script generates personalized film recommendations for customers
  of the DVD Rental Company based on their rental history and preferences.
  It uses SQL to analyze rental data, categorize films, and rank actors.
  The final output includes recommendations for both categories and actors.
******************************************************************************/

/******************************************************************************
#### a. Identify the 2 most watched categories and get statistics on them
******************************************************************************/

-- 1. Create *joint_tables* to consolidate the data needed to associate film
--    categories with customers via rentals. Also get
--    the most recent rental date for each customer in each category and
--    the number of films customer watched in each category (cust_cat_rental_count)

DROP TABLE IF EXISTS joint_tables;
CREATE TEMP TABLE joint_tables AS
  SELECT
    r.customer_id,
    r.rental_date,
    i.film_id,
    fc.category_id,
    f.title,
    COUNT(*) OVER (PARTITION BY r.customer_id)::NUMERIC cust_rental_count, --Total number of films rented by customer
    COUNT(*) OVER (PARTITION BY r.customer_id, fc.category_id)::NUMERIC cust_cat_rental_count,
    MAX(r.rental_date) OVER (PARTITION BY r.customer_id, fc.category_id) cust_cat_latest_rental_date,
    MAX(r.rental_date) OVER (PARTITION BY i.film_id) film_latest_rental_date, -- last day each film was rented
    COUNT(*) OVER (PARTITION BY fc.category_id)::NUMERIC cat_total, -- total number of films rented in a category
    COUNT(*) OVER (PARTITION BY i.film_id) film_views -- number of times a film was rented
  FROM dvd_rentals.rental r
    INNER JOIN dvd_rentals.inventory i ON r.inventory_id = i.inventory_id
    INNER JOIN dvd_rentals.film_category fc ON i.film_id = fc.film_id
    INNER JOIN dvd_rentals.film f ON i.film_id = f.film_id;

-- 2. Create *distinct_cust_table* to remove duplicates from *joint_tables*.

DROP TABLE IF EXISTS distinct_cust_table;
CREATE TEMP TABLE distinct_cust_table AS
    SELECT DISTINCT
      customer_id,
      cust_cat_latest_rental_date,
      category_id,
      cat_total,
      cust_cat_rental_count,
      cust_rental_count
    FROM joint_tables;

-- 3. Use *joint_tables* to create *ranked_cust_categories* which identifies the top two categories for each customer.
--    Also compute:
--    - number of films customer watched in category, compared to the average number of films each customer watched in same category (cat_avg_comparison)
--    - percentile customer falls in when compared to other viewers of same category (cust_cat_percentile)
--    - number of films watched in category compared with total number of films watched by the customer (cust_cat_percentage).

DROP TABLE IF EXISTS ranked_cust_categories;
  CREATE TEMP TABLE ranked_cust_categories AS
    WITH distinct_cust_stat AS (
      SELECT
        customer_id,
        category_id,
        cust_cat_rental_count,
        cust_rental_count,
        DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY cust_cat_rental_count DESC, cust_cat_latest_rental_date DESC) category_ranking,-- Categories ranked for each customer
        CEILING(cust_cat_rental_count - AVG(cust_cat_rental_count) OVER (PARTITION BY category_id)) cat_avg_comparison,
        CEILING(100 * PERCENT_RANK() OVER (PARTITION BY category_id ORDER BY cust_cat_rental_count DESC)) cust_cat_percentile,
        ROUND(100 * cust_cat_rental_count / cust_rental_count) cust_cat_percentage
      FROM distinct_cust_table
    )
    SELECT * FROM distinct_cust_stat
    WHERE category_ranking < 3;


/******************************************************************************
#### b. Movie recommendations based on Category 1 and Category 2
******************************************************************************/

-- 1. Create *cust_watched_films* to store the list of films watched by each customer.
--    This is used to filter out films that have already been watched when generating recommendations.

DROP TABLE IF EXISTS cust_watched_films;
CREATE TEMP TABLE cust_watched_films AS
  SELECT DISTINCT
    customer_id,
    film_id
  FROM joint_tables;

-- 2. Create *film_cat_ranking* to identify the most watched films in each category.
--    Use the latest rental date to sort if there's a tie on the number of views.

DROP TABLE IF EXISTS film_cat_ranking;
CREATE TEMP TABLE film_cat_ranking AS
    SELECT DISTINCT
      film_id,
      title,
      category_id,
      film_views,
      DENSE_RANK() OVER (PARTITION BY category_id ORDER BY film_views DESC, film_latest_rental_date DESC) cat_film_rank
    FROM joint_tables;

-- 3. Create *cat_recommendations* to identify the top 3 recommendations for each customer's top 2 categories,
--    filtering out the films they have already watched.
--    Also include a message for each recommendation that provides context on the customer's viewing habits.

DROP TABLE IF EXISTS cat_recommendations;
CREATE TEMP TABLE cat_recommendations AS
  WITH preferred_films AS (
    SELECT
      rcc.customer_id,
      rcc.category_id,
      rcc.category_ranking,
      rcc.cat_avg_comparison,
      rcc.cust_cat_percentile,
      rcc.cust_cat_percentage,
      rcc.cust_cat_rental_count,
      fcr.film_id,
      fcr.title,
      DENSE_RANK() OVER (PARTITION BY rcc.customer_id, rcc.category_id ORDER BY fcr.cat_film_rank) cat_recommendation_rank
    FROM ranked_cust_categories rcc
      INNER JOIN film_cat_ranking fcr ON rcc.category_id = fcr.category_id
      AND NOT EXISTS (
        SELECT 1
        FROM cust_watched_films cwf
        WHERE
          cwf.customer_id = rcc.customer_id
          AND cwf.film_id = fcr.film_id
      )
  )
  SELECT
    pf.customer_id,
    UPPER(c.name) category_name,
    pf.category_ranking,
    pf.film_id,
    INITCAP(pf.title) title,
    pf.cat_recommendation_rank,
    CONCAT('You''ve watched ', pf.cust_cat_rental_count, ' ', c.name, ' films, ',
      CASE
        WHEN pf.category_ranking = 1 THEN
          CONCAT('that''s ', pf.cat_avg_comparison, ' more than the DVD Rental Co average and puts you in the top ', pf.cust_cat_percentile, '% of ', c.name, ' Gurus!')
        ELSE CONCAT('making up ', pf.cust_cat_percentage, '% of your entire viewing history!')
      END
    ) msg
  FROM preferred_films pf
    INNER JOIN dvd_rentals.category c ON pf.category_id = c.category_id
  WHERE cat_recommendation_rank < 4;

-- 4. Create *cust_cat_recommendations* to summarize the recommendations so
--    there's only one record per customer.

DROP TABLE IF EXISTS cust_cat_recommendations;
CREATE TEMP TABLE cust_cat_recommendations AS
  SELECT
    customer_id,
    MAX(CASE WHEN category_ranking = 1 THEN category_name END) cat1,
    MAX(CASE WHEN category_ranking = 1 THEN msg END) msg1,
    MAX(CASE WHEN category_ranking = 1 AND cat_recommendation_rank = 1 THEN title END) cat1_film1,
    MAX(CASE WHEN category_ranking = 1 AND cat_recommendation_rank = 2 THEN title END) cat1_film2,
    MAX(CASE WHEN category_ranking = 1 AND cat_recommendation_rank = 3 THEN title END) cat1_film3,
    MAX(CASE WHEN category_ranking = 2 THEN category_name END) cat2,
    MAX(CASE WHEN category_ranking = 2 THEN msg END) msg2,
    MAX(CASE WHEN category_ranking = 2 AND cat_recommendation_rank = 1 THEN title END) cat2_film1,
    MAX(CASE WHEN category_ranking = 2 AND cat_recommendation_rank = 2 THEN title END) cat2_film2,
    MAX(CASE WHEN category_ranking = 2 AND cat_recommendation_rank = 3 THEN title END) cat2_film3
  FROM cat_recommendations
  GROUP BY customer_id;


/******************************************************************************
#### c. Identify each customer's favourite (most watched) actor
******************************************************************************/

-- 1. Create *actor_stats* to consolidate the data needed to associate actors with customers via rentals.
--    Also count the number of films each customer watched for a particular actor

DROP TABLE IF EXISTS actor_stats;
CREATE TEMP TABLE actor_stats AS
    SELECT
      jt.customer_id,
      jt.film_id,
      jt.title,
      jt.film_latest_rental_date,
      jt.film_views,
      fa.actor_id,
      a.first_name a_first_name,
      a.last_name a_last_name,
      COUNT(*) OVER (PARTITION BY jt.customer_id, fa.actor_id) cust_actor_total
    FROM joint_tables jt
      INNER JOIN dvd_rentals.film_actor fa ON jt.film_id = fa.film_id
      INNER JOIN dvd_rentals.actor a ON fa.actor_id = a.actor_id;

-- 2. Create *cust_fave_actor* to identify each customer's favourite actor.
--    Rank the actors by number of films watched, then first and last name to get rid of any ties.

DROP TABLE IF EXISTS cust_fave_actor;
CREATE TEMP TABLE cust_fave_actor AS
  WITH customer_actor_ranking AS (
    SELECT DISTINCT
      customer_id,
      actor_id,
      cust_actor_total,
      DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY cust_actor_total DESC, a_first_name, a_last_name) actor_ranking-- Actors ranked for each customer
    FROM actor_stats
  )
  SELECT
    customer_id,
    actor_id,
    cust_actor_total
  FROM customer_actor_ranking
  WHERE actor_ranking < 2;


/******************************************************************************
#### d. Film recommendations based on customer's favourite actor
******************************************************************************/

-- 1. Use *actor_stats* to create *film_actor_ranking* that identifes the most
--    watched films for each actor.
--    Rank the films by number of views, then latest rental date to get rid of any ties.

DROP TABLE IF EXISTS film_actor_ranking;
CREATE TEMP TABLE film_actor_ranking AS -- Films ranked by actor
    SELECT DISTINCT
      film_id,
      title,
      actor_id,
      a_first_name,
      a_last_name,
      film_views,
      DENSE_RANK() OVER (PARTITION BY actor_id ORDER BY film_views DESC, film_latest_rental_date DESC) actor_film_rank
    FROM actor_stats;

-- 2. Create *actor_recommendations* to identify the top 3 recommendations for each customer's favourite actor,
--    filtering out the films they have already watched and those that have already been recommended.

DROP TABLE IF EXISTS actor_recommendations;
CREATE TEMP TABLE actor_recommendations AS
  WITH preferred_actor_films AS (
    SELECT
      car.customer_id,
      car.cust_actor_total,
      far.a_first_name || ' ' || far.a_last_name actor,
      INITCAP(far.a_first_name) a_first_name,
      INITCAP(far.title) title,
      DENSE_RANK() OVER (PARTITION BY car.customer_id, car.actor_id ORDER BY actor_film_rank) actor_recommendation_rank
    FROM cust_fave_actor car
      INNER JOIN film_actor_ranking far ON car.actor_id = far.actor_id
    WHERE NOT EXISTS (
        SELECT 1
        FROM cust_watched_films cwf
        WHERE
          cwf.customer_id = car.customer_id
          AND cwf.film_id = far.film_id
      )
      AND NOT EXISTS (
        SELECT 1
        FROM cat_recommendations cr
        WHERE
          cr.customer_id = car.customer_id
          AND cr.film_id = far.film_id
    )
    )
    SELECT * FROM preferred_actor_films
    WHERE actor_recommendation_rank < 4;

-- 3. Create *cust_actor_recommendations* to summarize the recommendations so
--    there's only one record per customer.
--    Also include a message for each recommendation that provides context on the customer's viewing habits.

DROP TABLE IF EXISTS cust_actor_recommendations;
CREATE TEMP TABLE cust_actor_recommendations AS
  SELECT
    customer_id,
    actor,
    CONCAT('You''ve watched ', cust_actor_total, ' films featuring ', actor, '! Here are some other films ', a_first_name, ' stars in that might interest you!') actor_msg,
    MAX(CASE WHEN actor_recommendation_rank = 1 THEN title END) actor_film1,
    MAX(CASE WHEN actor_recommendation_rank = 2 THEN title END) actor_film2,
    MAX(CASE WHEN actor_recommendation_rank = 3 THEN title END) actor_film3
  FROM actor_recommendations
  GROUP BY 1, 2, 3;
  

/******************************************************************************
## Final Output: Combine the recommendations into a single table
******************************************************************************/

DROP TABLE IF EXISTS recommendations;
CREATE TEMP TABLE recommendations AS
  SELECT
    cr.*,
    ar.actor,
    ar.actor_msg,
    ar.actor_film1,
    ar.actor_film2,
    ar.actor_film3
  FROM cust_cat_recommendations cr
    INNER JOIN cust_actor_recommendations ar ON cr.customer_id = ar.customer_id
  ORDER BY cr.customer_id;
  

SELECT * FROM recommendations
ORDER BY customer_id
LIMIT 15;