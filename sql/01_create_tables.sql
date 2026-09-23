-- ============================================================================
-- 01_create_tables.sql
-- Marketplace Performance & Seller Health Analysis (Olist)
-- ============================================================================
-- Purpose
--   Create staging tables that mirror the Olist Kaggle CSV files one-to-one:
--   same columns, same order, sensible PostgreSQL types. Nothing more.
--
-- Why no PRIMARY KEY / FOREIGN KEY constraints here
--   This is real, public data we haven't inspected yet. If we declare PKs/FKs
--   before we know whether the raw files actually respect them, a single bad
--   row (a duplicate, an orphaned reference) would make the whole CSV import
--   fail instead of letting us measure how bad it is. So the load step here
--   is deliberately unconstrained; 02_data_quality_checks.sql is where we
--   test for duplicates and orphan keys and quantify them. If you want to add
--   constraints afterwards for a stricter build, each table's intended grain
--   (its natural key) is noted in a comment above it.
-- ============================================================================

DROP TABLE IF EXISTS order_reviews CASCADE;
DROP TABLE IF EXISTS order_payments CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS product_category_name_translation CASCADE;
DROP TABLE IF EXISTS sellers CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

-- ----------------------------------------------------------------------------
-- 1. customers  (source file: olist_customers_dataset.csv)
-- Intended grain: one row per customer_id.
-- IMPORTANT: customer_id is generated PER ORDER, not per person -- the same
-- shopper gets a new customer_id every time they order. customer_unique_id
-- is the column that actually identifies a returning person. See the
-- granularity checks in 02_data_quality_checks.sql before using either
-- column to count "customers".
-- ----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id               VARCHAR(32),
    customer_unique_id        VARCHAR(32),
    customer_zip_code_prefix  INT,        -- first digits of the Brazilian CEP; not a full postcode
    customer_city              VARCHAR(100),
    customer_state              CHAR(2)
);

-- ----------------------------------------------------------------------------
-- 2. sellers  (source file: olist_sellers_dataset.csv)
-- Intended grain: one row per seller_id.
-- ----------------------------------------------------------------------------
CREATE TABLE sellers (
    seller_id               VARCHAR(32),
    seller_zip_code_prefix  INT,
    seller_city               VARCHAR(100),
    seller_state               CHAR(2)
);

-- ----------------------------------------------------------------------------
-- 3. product_category_name_translation  (source file: product_category_name_translation.csv)
-- Intended grain: one row per product_category_name (Portuguese -> English).
-- ----------------------------------------------------------------------------
CREATE TABLE product_category_name_translation (
    product_category_name          VARCHAR(100),
    product_category_name_english  VARCHAR(100)
);

-- ----------------------------------------------------------------------------
-- 4. products  (source file: olist_products_dataset.csv)
-- Intended grain: one row per product_id.
-- Note: "product_name_lenght" / "product_description_lenght" are misspelled
-- in the original Kaggle file (missing the 'g'). Kept as-is here so the
-- column names line up exactly with the CSV header for import.
-- ----------------------------------------------------------------------------
CREATE TABLE products (
    product_id                   VARCHAR(32),
    product_category_name        VARCHAR(100),
    product_name_lenght          INT,
    product_description_lenght   INT,
    product_photos_qty            INT,
    product_weight_g               INT,
    product_length_cm              INT,
    product_height_cm              INT,
    product_width_cm               INT
);

-- ----------------------------------------------------------------------------
-- 5. orders  (source file: olist_orders_dataset.csv)
-- Intended grain: one row per order_id. This is the anchor table everything
-- else hangs off.
-- ----------------------------------------------------------------------------
CREATE TABLE orders (
    order_id                        VARCHAR(32),
    customer_id                     VARCHAR(32),
    order_status                    VARCHAR(20),
    order_purchase_timestamp        TIMESTAMP,
    order_approved_at               TIMESTAMP,
    order_delivered_carrier_date    TIMESTAMP,
    order_delivered_customer_date   TIMESTAMP,
    order_estimated_delivery_date   TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- 6. order_items  (source file: olist_order_items_dataset.csv)
-- Intended grain: one row per ITEM within an order, not per order. A single
-- order_id will appear multiple times here whenever the order has more than
-- one line item. Never join this straight into an order-level analysis
-- without aggregating first (see 03_fact_orders.sql).
-- ----------------------------------------------------------------------------
CREATE TABLE order_items (
    order_id              VARCHAR(32),
    order_item_id          INT,             -- 1, 2, 3... position of the item within the order
    product_id              VARCHAR(32),
    seller_id                VARCHAR(32),
    shipping_limit_date      TIMESTAMP,
    price                     NUMERIC(10,2),
    freight_value             NUMERIC(10,2)
);

-- ----------------------------------------------------------------------------
-- 7. order_payments  (source file: olist_order_payments_dataset.csv)
-- Intended grain: one row per payment "leg" within an order. An order paid
-- with a voucher + a credit card, for example, gets two rows here with
-- different payment_sequential values. Never SUM(payment_value) into an
-- order-level GMV figure -- that double-counts split payments; GMV comes
-- from order_items instead (price + freight), see 03_fact_orders.sql.
-- ----------------------------------------------------------------------------
CREATE TABLE order_payments (
    order_id                VARCHAR(32),
    payment_sequential        INT,
    payment_type                VARCHAR(20),
    payment_installments        INT,
    payment_value                 NUMERIC(10,2)
);

-- ----------------------------------------------------------------------------
-- 8. order_reviews  (source file: olist_order_reviews_dataset.csv)
-- Intended grain: one row per review. The vast majority of orders have
-- exactly one review, but 02_data_quality_checks.sql tests for the small
-- number that have more than one (e.g. a customer who was re-surveyed).
-- review_id is NOT guaranteed unique in the raw file.
-- ----------------------------------------------------------------------------
CREATE TABLE order_reviews (
    review_id                  VARCHAR(32),
    order_id                     VARCHAR(32),
    review_score                  SMALLINT,
    review_comment_title           TEXT,
    review_comment_message          TEXT,
    review_creation_date              TIMESTAMP,
    review_answer_timestamp           TIMESTAMP
);


-- ============================================================================
-- Importing the CSVs in pgAdmin
-- ============================================================================
-- Do this once you've downloaded the "Brazilian E-Commerce Public Dataset by
-- Olist" from Kaggle and unzipped it. You should have these files (the
-- geolocation file is not used in this project -- ignore it):
--   olist_customers_dataset.csv
--   olist_sellers_dataset.csv
--   product_category_name_translation.csv
--   olist_products_dataset.csv
--   olist_orders_dataset.csv
--   olist_order_items_dataset.csv
--   olist_order_payments_dataset.csv
--   olist_order_reviews_dataset.csv
--
-- Steps:
--   1. In pgAdmin, create (or pick) a database, e.g. "olist_marketplace".
--   2. Open a Query Tool on that database and run this entire file once.
--      All 8 tables above are created empty.
--   3. Before importing, open each CSV in a text editor or Excel and check
--      its header row matches the column order in this file. The Olist
--      dataset has been stable for years, but always verify -- this is
--      exactly the kind of assumption a data-quality mindset doesn't skip.
--   4. In the pgAdmin object browser, expand olist_marketplace > Schemas >
--      public > Tables. Right-click a table -> Import/Export Data...
--   5. In the dialog:
--        - Toggle to "Import"
--        - Filename: browse to the matching CSV
--        - Format: csv
--        - Encoding: UTF8
--        - Header: Yes (the "Options" tab)
--        - Delimiter: , (comma, the Olist default)
--      Leave the Columns tab at its default (all columns, in table order) --
--      this only works because each CREATE TABLE above matches its CSV's
--      column order exactly.
--   6. Click OK. Repeat for all 8 tables. Import customers, sellers, products
--      and product_category_name_translation first, then orders, then
--      order_items / order_payments / order_reviews last -- not required
--      since there are no FK constraints yet, but it keeps the order logical
--      if you're following along table by table.
--   7. Move on to 02_data_quality_checks.sql before building anything else.
-- ============================================================================
