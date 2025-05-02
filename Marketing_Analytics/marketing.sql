DROP TABLE IF EXISTS joint_tables;
CREATE TEMP TABLE joint_tables AS
  SELECT
    r.customer_id,
    r.rental_date,
    i.film_id,
    fc.category_id,
    f.title,
    COUNT(*) OVER (PARTITION BY r.customer_id)::NUMERIC cust_rental_count, --Total number of films rented by customer
    COUNT(*) OVER (PARTITION BY r.customer_id, fc.category_id)::NUMERIC cust_cat_rental_count, -- number of films rented by customer in each category
    MAX(r.rental_date) OVER (PARTITION BY r.customer_id, fc.category_id) cust_cat_latest_rental_date, -- last date customer rented a film in each category
    MAX(r.rental_date) OVER (PARTITION BY i.film_id) film_latest_rental_date, -- last day each film was rented
    COUNT(*) OVER (PARTITION BY fc.category_id)::NUMERIC cat_total, -- total number of films rented in a category
    COUNT(*) OVER (PARTITION BY i.film_id) film_views -- number of times a film was rented
  FROM dvd_rentals.rental r
    INNER JOIN dvd_rentals.inventory i ON r.inventory_id = i.inventory_id
    INNER JOIN dvd_rentals.film_category fc ON i.film_id = fc.film_id
    INNER JOIN dvd_rentals.film f ON i.film_id = f.film_id;

DROP TABLE IF EXISTS distinct_cust_table;
CREATE TEMP TABLE distinct_cust_table AS -- Data on each customer's rentals by category without duplicates from films
    SELECT DISTINCT
      customer_id,
      cust_cat_latest_rental_date,
      category_id,
      cat_total,
      cust_cat_rental_count,
      cust_rental_count
    FROM joint_tables;

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
        ROUND(100 * cust_cat_rental_count / cust_rental_count) category_percentage,
        CEILING(100 * PERCENT_RANK() OVER (PARTITION BY category_id ORDER BY cust_cat_rental_count DESC)) cat_percentile
      FROM distinct_cust_table
    )
    SELECT * FROM distinct_cust_stat
    WHERE category_ranking < 3;

DROP TABLE IF EXISTS cust_watched_films;
CREATE TEMP TABLE cust_watched_films AS -- List of films watched by each customer
  SELECT DISTINCT
    customer_id,
    film_id
  FROM joint_tables;

DROP TABLE IF EXISTS film_cat_ranking;
CREATE TEMP TABLE film_cat_ranking AS -- Films ranked by category
    SELECT DISTINCT
      film_id,
      title,
      category_id,
      film_views,
      DENSE_RANK() OVER (PARTITION BY category_id ORDER BY film_views DESC, film_latest_rental_date DESC) cat_film_rank
    FROM joint_tables;

DROP TABLE IF EXISTS cat_recommendations;
CREATE TEMP TABLE cat_recommendations AS
  WITH preferred_films AS (
    SELECT
      rcc.customer_id,
      rcc.category_id,
      rcc.category_ranking,
      rcc.cat_avg_comparison,
      rcc.cat_percentile,
      rcc.category_percentage,
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
    pf.*,
    c.name category_name,
    CONCAT('You''ve watched ', pf.cust_cat_rental_count, ' ', c.name, ' films, ',
      CASE
        WHEN pf.category_ranking = 1 THEN
          CONCAT('that''s ', pf.cat_avg_comparison, ' more than the DVD Rental Co average and puts you in the top ', pf.cat_percentile, '% of ', c.name, ' Gurus!')
        ELSE CONCAT('making up ', pf.category_percentage, '% of your entire viewing history!')
      END
    ) msg
  FROM preferred_films pf
    INNER JOIN dvd_rentals.category c ON pf.category_id = c.category_id
  WHERE cat_recommendation_rank < 4;

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


DROP TABLE IF EXISTS actor_stats;
CREATE TEMP TABLE actor_stats AS -- General data on films
    SELECT
      jt.customer_id,
      jt.film_id,
      jt.title,
      jt.film_latest_rental_date,
      jt.film_views,
      fa.actor_id,
      a.first_name a_first_name,
      a.last_name a_last_name,
      COUNT(*) OVER (PARTITION BY jt.customer_id, fa.actor_id) cust_actor_total-- Number of films each customer watched for a particular actor
    FROM joint_tables jt
      INNER JOIN dvd_rentals.film_actor fa ON jt.film_id = fa.film_id
      INNER JOIN dvd_rentals.actor a ON fa.actor_id = a.actor_id;

DROP TABLE IF EXISTS customer_actor_ranking;
CREATE TEMP TABLE customer_actor_ranking AS -- Actors ranked for each customer
    SELECT DISTINCT
      customer_id,
      actor_id,
      cust_actor_total,
      DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY cust_actor_total DESC, a_first_name) cust_actor_ranking-- Actors ranked by customer
    FROM actor_stats;

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

DROP TABLE IF EXISTS actor_recommendations;
CREATE TEMP TABLE actor_recommendations AS
  WITH preferred_actor_films AS (
    SELECT
      car.customer_id,
      car.actor_id,
      car.cust_actor_total,
      INITCAP(far.a_first_name || ' ' || far.a_last_name) actor,
      far.a_first_name,
      far.film_id,
      far.title,
      DENSE_RANK() OVER (PARTITION BY car.customer_id, car.actor_id ORDER BY actor_film_rank) actor_recommendation_rank
    FROM customer_actor_ranking car
      INNER JOIN film_actor_ranking far ON car.actor_id = far.actor_id
    WHERE cust_actor_ranking < 2
      AND NOT EXISTS (
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

DROP TABLE IF EXISTS cust_actor_recommendations;
CREATE TEMP TABLE cust_actor_recommendations AS
  SELECT
    customer_id,
    actor,
    MAX(CASE WHEN actor_recommendation_rank = 1 THEN title END) actor_choice_1,
    MAX(CASE WHEN actor_recommendation_rank = 2 THEN title END) actor_choice_2,
    MAX(CASE WHEN actor_recommendation_rank = 3 THEN title END) actor_choice_3,
    CONCAT('You''ve watched ', cust_actor_total, ' films featuring ', actor, '! Here are some other films ', a_first_name, ' stars in that might interest you!') actor_msg
  FROM actor_recommendations
  GROUP BY 1, 2, 6;
  

DROP TABLE IF EXISTS recommendations;
CREATE TEMP TABLE recommendations AS
  SELECT
    cr.*,
    ar.actor,
    ar.actor_choice_1,
    ar.actor_choice_2,
    ar.actor_choice_3,
    ar.actor_msg
  FROM cust_cat_recommendations cr
    INNER JOIN cust_actor_recommendations ar ON cr.customer_id = ar.customer_id
  ORDER BY cr.customer_id;
  

SELECT * FROM recommendations
ORDER BY customer_id;

