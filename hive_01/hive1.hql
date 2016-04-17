-----------------------------------------------------------
---------- Hive Homework 01 - Timofei Korostelev ----------
-----------------------------------------------------------

-- Create staging fact table as an external table
DROP TABLE IF EXISTS STG_CLICK_FACT;
CREATE EXTERNAL TABLE STG_CLICK_FACT(
    BID_ID                  VARCHAR(32),
    CLICK_DTTM             VARCHAR(30),
    IPINYOU_ID              VARCHAR(30),
    USER_AGENT              VARCHAR(2000),
    IP                      VARCHAR(16),
    REGION                  BIGINT,
    CITY                    BIGINT,
    AD_EXCHANGE             BIGINT,
    DOMAIN_ID               VARCHAR(100),
    URL                     VARCHAR(2000),
    ANONYMOUS_URL_ID        VARCHAR(2000),
    AD_SLOT_ID              VARCHAR(200),
    AD_SLOT_WIDTH           BIGINT,
    AD_SLOT_HEIGHT          BIGINT,
    AD_SLOT_VISIBILITY      BIGINT,
    AD_SLOT_FORMAT          BIGINT,
    PAYING_PRICE            BIGINT,
    CREATIVE_ID             VARCHAR(32),
    BIDDING_PRICE           BIGINT,
    ADVERTISER_ID           VARCHAR(100),
    USER_TAGS               VARCHAR(100),
    STREAM_ID               BIGINT
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
location '/dataset'
;

-- Create view to implicitly parse timestamps
DROP VIEW IF EXISTS CLICK_FACT;
CREATE VIEW CLICK_FACT AS 
SELECT
    BID_ID,
    CAST(to_date(from_unixtime(unix_timestamp(CLICK_DTTM,'yyyyMMddHHmmssSSS'))) AS DATE) AS CLICK_DT,
    CAST(from_unixtime(unix_timestamp(CLICK_DTTM,'yyyyMMddHHmmssSSS')) AS TIMESTAMP) AS CLICK_DTTM,
    IPINYOU_ID,
    USER_AGENT,
    IP,
    REGION,
    CITY,
    AD_EXCHANGE,
    DOMAIN_ID,
    URL,
    ANONYMOUS_URL_ID,
    AD_SLOT_ID,
    AD_SLOT_WIDTH,
    AD_SLOT_HEIGHT,
    AD_SLOT_VISIBILITY,
    AD_SLOT_FORMAT,
    PAYING_PRICE,
    CREATIVE_ID,
    BIDDING_PRICE,
    ADVERTISER_ID,
    USER_TAGS,
    STREAM_ID,
    INPUT__FILE__NAME AS INPUT_FILE_NAME
FROM
    STG_CLICK_FACT
WHERE
    IPINYOU_ID IS NOT NULL
    AND LENGTH(IPINYOU_ID) >= 10
    AND CLICK_DTTM IS NOT NULL
;

-- Calculate Bid Flow (point 01) report
DROP TABLE IF EXISTS BID_FLOW;
CREATE TABLE BID_FLOW AS
SELECT
    CLICK_DT,
    SUM(BIDDING_PRICE) AS BIDDING_PRICE,
    SUM(PAYING_PRICE)  AS PAYING_PRICE
FROM CLICK_FACT
WHERE
    STREAM_ID = 1
GROUP BY CLICK_DT
ORDER BY CLICK_DT
;

-- Calculate User-Date-Clicks table
DROP TABLE IF EXISTS USER_DATE_CLICKS;
CREATE TABLE USER_DATE_CLICKS AS
SELECT
    IPINYOU_ID,
    CLICK_DT,
    COUNT(*) AS CLICKS
FROM
    CLICK_FACT
WHERE
    CLICK_DT IS NOT NULL
GROUP BY
    IPINYOU_ID,
    CLICK_DT
;

-- Pull all dates from USER_DATE_CLICKS
DROP TABLE IF EXISTS ALL_DATES;
CREATE TABLE ALL_DATES AS
SELECT
    CLICK_DT AS DATE_VAL
FROM
    USER_DATE_CLICKS
WHERE
    CLICK_DT IS NOT NULL
GROUP BY
    CLICK_DT
;

-- Pull all users from USER_DATE_CLICKS
DROP TABLE IF EXISTS ALL_USERS;
CREATE TABLE ALL_USERS AS
SELECT
    IPINYOU_ID
FROM
    USER_DATE_CLICKS
GROUP BY
    IPINYOU_ID
;

-- Create ALL_USERS_ALL_DATES table as Decart product
DROP TABLE IF EXISTS ALL_USERS_ALL_DATES;
CREATE TABLE ALL_USERS_ALL_DATES AS
SELECT
    u.IPINYOU_ID,
    d.DATE_VAL
FROM
    ALL_USERS AS u
    INNER JOIN
    ALL_DATES AS d
;

DROP TABLE ALL_USERS;
DROP TABLE ALL_DATES;

-- Create User-AllDates-Clicks table
DROP TABLE IF EXISTS USER_ALLDATES_CLICKS;
CREATE TABLE USER_ALLDATES_CLICKS AS
SELECT
    aa.IPINYOU_ID,
    aa.DATE_VAL AS CLICK_DT,
    COALESCE(udc.CLICKS, 0) AS CLICKS
FROM
    ALL_USERS_ALL_DATES AS aa
    LEFT JOIN
    USER_DATE_CLICKS AS udc
    ON (
        aa.IPINYOU_ID = udc.IPINYOU_ID
        AND aa.DATE_VAL = udc.CLICK_DT
    )
;
DROP TABLE ALL_USERS_ALL_DATES;
DROP TABLE USER_DATE_CLICKS;

--SELECT * FROM USER_ALLDATES_CLICKS ORDER BY IPINYOU_ID, CLICK_DT;

-- Calculate User-Date-SEGMENT table
DROP TABLE IF EXISTS USER_DAY_SEGMENT;
CREATE TABLE USER_DAY_SEGMENT AS
SELECT
    IPINYOU_ID,
    CLICK_DT,
    CLICKS,
    CASE
        WHEN
            CLICKS > 0
            AND SUM(CLICKS) OVER (PARTITION BY IPINYOU_ID ORDER BY CLICK_DT ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) = CLICKS
        THEN 1 -- New
        WHEN
            CLICKS > 0
            AND ( LAG(CLICKS,1,0) OVER (PARTITION BY IPINYOU_ID ORDER BY CLICK_DT) ) = 1
        THEN 2 -- Current Repeat Low
        WHEN
            CLICKS > 0
            AND ( LAG(CLICKS,1,0) OVER (PARTITION BY IPINYOU_ID ORDER BY CLICK_DT) ) > 1
        THEN 3 -- Current Repeat Hight
        WHEN
            CLICKS = 0
            AND ( SUM(CLICKS) OVER (PARTITION BY IPINYOU_ID ORDER BY CLICK_DT ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) ) = 1
        THEN 4 -- Active Rolling 3D One Click
        WHEN
            CLICKS = 0
            AND ( SUM(CLICKS) OVER (PARTITION BY IPINYOU_ID ORDER BY CLICK_DT ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) ) > 1
        THEN 5 -- Active Rolling 3D Repeat
        WHEN
            CLICKS = 0
            AND LAG(CLICKS,3,0) OVER (PARTITION BY IPINYOU_ID ORDER BY CLICK_DT) > 0
        THEN 6 -- Lapsed
        ELSE 7 -- Other
    END as SEGMENT
FROM
    USER_ALLDATES_CLICKS
;

SELECT * FROM USER_DAY_SEGMENT
ORDER BY IPINYOU_ID,CLICK_DT;

-- Calculate Customers by segments report
DROP TABLE IF EXISTS CUSTOMERS_BY_SEGMENTS;
CREATE TABLE CUSTOMERS_BY_SEGMENTS AS
SELECT
    CLICK_DT AS DAY,
    SEGMENT,
    COUNT(*) AS CUSTOMERS_COUNT
FROM USER_DAY_SEGMENT
GROUP BY
    CLICK_DT,
    SEGMENT
;