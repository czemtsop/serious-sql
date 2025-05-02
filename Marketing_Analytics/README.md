# Marketing Analytics Case Study

## 1. 📚️ Introduction
This Case Study focuses on leveraging SQL to prepare data for a marketing campaign and derive actionable insights. The goal is to help a DVD rental business engage customers on an individual level, based on their past behavior.

### 1.1 🗝️ Key Features

- **Data Exploration**: Analyze customer demographics, rent patterns, and engagement metrics.
- **Communication**: Prepare data for email to present insights effectively.


### 1.2 Outcomes

- Improved understanding of customer behavior.
- Customised marketing emails based on data insights.
- Optimized campaign performance and ROI.

### 1.3 Requirements Analysis

The DVD Rental Co marketing department has requested for help getting the data needed to fuel their first ever customer email campaign. They shared a template of the email they will send to each customer and after analysing it, we have a broad idea of what data we need to provide. We have split these main requirements into 9 major insights, for each customer.

![DVD RENTAL CO email template](dvd_rental.png)

The table below summarises our observations on each insight.

| Insight | Description   | Remark     |
| --------| --------------------------------------- | ----------- |
| 1 and 4 | Top (most watched) 2 categories.     |   -         |
| 2 and 5 | Some statistics based on the categories identified in (1) & (4) | - |
| 3 and 6 | Film recommendations based on the categories identified in (1) & (4) | - The recommended films should not have been watched by the customer.<br>- Flag customer if no recommendation for either (3) or (6) |
| 7 | Favourite actor | Choose in alphabetic order if there are ties  |
| 8 | Some statistics related to the favourite actor identified in (7) | - |
| 9 | Film recommendations based on the favourite actor identified in (7) | - No film in (3) or (6) should be found here.<br>- Flag customer if there's no film recommendation|
 
 ## 2. The Data

The data for this problem is available in the DVD Rental Co database and the tables needed are shown in the entity relationship diagram (ERD) below.

![DVD Rental Co ERD](er-1.png)

We observe that all these tables are linked by foreign keys, though not directly. To decide what type of joins to use to link our tables, we start by thinking about the data practically:

| Tables  | Purpose of Join | Points to Consider | Things to verify | Preferred Join |
| --------| ----------------| ------------------ | ---------- | ---------- |
| 1 and 2 | These two tables need to be joined because from the ERD, we see that the only way of associating a rental to a film is via the inventory table and we need to know which films were rented. | - Every rental operation (in table 1) has to be based on an inventory item (in table 2). So, an entry in table 1 without a matching inventory in table 2 must be an accident and we can't use that data without correcting it. Hence a left join won't be appropriate.<br>- An inventory not rented is not useful for our analysis so we don't need any record in table 2 that has no corresponding record in table 1. Hence we can't use a right join. | | Inner join |
| 2 and 3 | We need to join the inventory table to films so that we can know the titles of the films that were rented. |- Every inventory record (in table 2) should correspond to a film (in table 3). So an inventory record not associated to a film could only be an error, making it useless for any analysis. As a result, we can't use a left join.<br>- A film cannot be rented without a corresponding inventory record so a record in table 3 with no matching entry in table 2 is not helpful to our analysis This means a right join isn't an option here. | | Inner join    |
| 3 and 4 | To provide insights 1 and 4 from our requirements analysis ([Section 1.3](###1.3-requirements-analysis)), we need to know the category each film falls in. | - Every film should belong to only one category.<br>- A film without a category won't be useful in this join. This implies that we can't use a left join here.<br>- A category without films can't provide information for our insight hence it wouldn't be useful. This means we can't use a right join. | - Are there films which fall in more than one category? | Inner join    |
| 4 and 5 | This join is necessary to get the category names. | - An entry in table 4 with no corresponding entry in table 5 will be a nameless category, something we can't use in our campaign. Hence a left join can't be used here.<br>- An entry in table 5 without a corresponding enty in table 4 cannot be associated to a film, making it useless for our analysis. So, we can't use a right join here. | | Inner join    |
| 3 and 6 | To provide insights 7, 8 and 9 from our requirements analysis ([Section 1.3](###1.3-requirements-analysis)), we need to know the the actors who feature in each film. | - A film without actors won't be useful in this join. This implies that we can't use a left join here.<br>- An actor who doesn't feature in any film can't be used in our insights hence they wouldn't be useful. This means we can't use a right join. | | Inner join    |
| 6 and 7 | This join is necessary to get the names of actors. | - An entry in table 6 with no corresponding entry in table 7 represents an actor with no name, something we can't use in our campaign. Hence a left join can't be used here.<br>- An entry in table 7 without a corresponding enty in table 6 cannot be associated to a film, making it useless for our analysis. So, we can't use a right join here. | | Inner join    |

We run an sql query to verify if any films fall in more than one category.
```sql
SELECT
  film_id,
  COUNT(*) categories
FROM dvd_rentals.film_category
GROUP BY film_id
HAVING COUNT(*) > 1;
```
![Film-category investigation](query-2.png)

With no film in more than one category, we need not be concerned about double counting.

## 3. Solution

### 3.1 Strategy

**Generally, to minimize compute operations and memory usage, we perform joins and add columns to our queries only when needed.**

Given our problem and the data, our strategy for getting the required information for each customer is outlined in the table.

| Id | Insights | Plan | Tables involved | Expected results |
|----|----------|------|-----------------|------------------|
| a  | 1, 2, 4 and 5  | - Identify the 2 most watched categories.<br> Calculate:<br>- number of films customer watched in category 1 and category 2<br>- number of films customer watched in category 1, compared to the average number of films each customer watched in same category<br>- percentile customer falls in when compared to other viewers of category 1<br>- number of films watched in category 2 compared with total number of films watched by the customer. | - rental<br>- inventory<br>- film_category | - Category 1<br>- Category 2<br> - cust_cat_rental_count<br>- cat_avg_comparison<br>- cust_cat_percentile<br>- cust_cat_percentage |
| b  | 3 and 6 | Make 3 film recommendations based on category 1 and 3 film recommendations based on category 2 | Temp tables from (a) +<br>- film<br>- category | - cat1_film1<br>- cat1_film2<br>- cat1_film3<br>-- cat2_film1<br>- cat2_film2<br>- cat2_film3 |
| c  | 7 | Identify the most watched actor | rental, inventory, film_actor | - fav_actor |
| d  | 8 and 9 | - Count the number of films customer watched, featuring fav_actor.<br>- Make 3 film recommendations based on fav_actor | - |  - actor_film_count<br>- film1<br>- film2<br>- film3 |

### 3.2 Code

The SQL code used in this step can be found in the script [here](marketing.sql)
#### a. Identify the 2 most watched categories and get statistics on them

1. Create *joint_tables* to consolidate the data needed to associate film categories with customers via rentals
2. Remove film duplicates from *joint_tables*
3. Use *joint_tables* to identify top two categories for each customer. While at it, compute other statistics.
> When we run a simple query to see the records in the ranked_cust_categpries table, we get the below.

```sql
SELECT * FROM ranked_cust_categories;
```

![Insights 1, 2, 4 and 5](query-3.2a.png)

#### b. Movie recommendations based on Category 1 and Category 2

1. Identify all films a customer has already watched so we don't recommend them to the customer.
2. Identify the most watched films in each category.
3. Select the top 3 recommendations for each customer's top 2 categories, filtering out the films they have already watched.
4. Flatten the recommendations so there's only one record per customer.

> We run a simple query to see what we have so far ...
```sql  
  SELECT * FROM cust_cat_recommendations
  ORDER BY customer_id;
```
![Insights 3 and 6](query-3.2b.png)

#### c. Identify the most watched actor

1. Create *actor_stats* to consolidate the data needed to associate actors with customers via rentals
2. Identify each customer's favourite actor.

#### d. Movie recommendations based on most watched actor

1. Use *actor_stats* to identify the most watched films for each actor.
2. Select the top 3 recommendations for each customer's favourite actor, filtering out the films they have already watched and those already recommended in the categories recommendations.
3. Flatten the recommendations so there's only one record per customer.

## Final Output

We consolidate the category and actor recommendations to come up with the final data for the marketing campaign.

![Final output](final.png)