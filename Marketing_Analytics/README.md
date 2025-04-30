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

![alt text](dvd_rental.png)

The table below summarises our observations on each insight.

| Insight | Description   | Remark     |
| --------| --------------------------------------- | ----------- |
| 1 and 4 | Top (most watched) 2 categories.     |   -         |
| 2 and 5 | Some statistics based on the categories identified in (1) & (4) | - |
| 3 and 6 | Film recommendations based on the categories identified in (1) & (4) | - The recommended films should not have been watched by the customer and no film in (3) should repeat in (6).<br>- Flag customer if no recommendation for either (3) or (6) |
| 7 | Favourite actor | Choose in alphabetic order if there are ties  |
| 8 | Some statistics related to the favourite actor identified in (7) | - |
| 9 | Film recommendations based on the favourite actor identified in (7) | - No film in (3) or (6) should be found here.<br>- Flag customer if there's no film recommendation|
 
 ## 2. The Data

The data for this problem is available in the DVD Rental Co database and the tables needed are shown in the entity relationship diagram (ERD) below.

![DVD Rental Co ERD](er-1.png)

We observe that all these tables are linked by foreign keys, though not directly. 

| Tables  | Preferred Join | Remark      |
| --------| -------------- | ----------- |
| 1 and 2 | Inner join     |  We need each record to be in both tables because:<br>- If a rental operation is done in (1) without a matching inventory in (2), it must be an accident and we can't use that data.<br>- An inventory (2) not rented (1) is not useful for our analysis |
| 2 and 3 | Inner join    |  |
| 3 and 4 | Inner join    |  |
| 4 and 5 | Inner join    |  |
| 3 and 6 | Inner join    |  |
| 6 and 7 | Inner join    |  |