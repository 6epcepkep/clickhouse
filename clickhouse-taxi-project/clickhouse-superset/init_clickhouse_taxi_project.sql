-- ========================================================================================
-- Инициализация схемы ClickHouse для проекта анализа поездок такси (NYC Taxi, 2016 год)
-- Содержит справочники, основную таблицу, представления, MV и live-аналитику (15 мин)
-- ========================================================================================

-- Очистка старых таблиц, если они существуют
DROP TABLE IF EXISTS routes;
DROP TABLE IF EXISTS drivers;
DROP TABLE IF EXISTS vendors;
DROP TABLE IF EXISTS payment_types;
DROP TABLE IF EXISTS trips_raw;
DROP TABLE IF EXISTS trip_duration_distribution_data;
DROP TABLE IF EXISTS trip_duration_distribution;

-- Очистка live-представлений (обновляются в пределах 15 минут)
DROP TABLE IF EXISTS revenue_by_vendor_last_15m;
DROP TABLE IF EXISTS trips_by_payment_type_last_15m;
DROP TABLE IF EXISTS avg_fare_by_route_last_15m;
DROP TABLE IF EXISTS trips_by_driver_last_15m;
DROP TABLE IF EXISTS trip_duration_distribution_last_15m;

-- ========================================================================================
-- Справочные таблицы: маршруты, водители, поставщики (таксопарки), типы оплаты
-- ========================================================================================

DROP TABLE IF EXISTS routes SYNC;
CREATE TABLE routes (
    route_id UInt32,
    route_name String,
    to_id UInt32
) ENGINE = MergeTree
ORDER BY route_name;

DROP TABLE IF EXISTS drivers SYNC;
CREATE TABLE drivers (
    driver_id UInt32,
    driver_name String,
    company String
) ENGINE = MergeTree
ORDER BY driver_name;

DROP TABLE IF EXISTS vendors SYNC;
CREATE TABLE vendors (
    vendor_id UInt8,
    vendor String
) ENGINE = TinyLog;

DROP TABLE IF EXISTS payment_types SYNC;
CREATE TABLE payment_types (
    payment_type UInt8,
    payment_method String
) ENGINE = TinyLog;

-- ========================================================================================
-- Основная таблица: trips_raw — содержит все события поездок
-- ========================================================================================

DROP TABLE IF EXISTS trips_raw SYNC;
CREATE TABLE trips_raw (
    event_time DateTime,
    route_id UInt32,
    route_name String,
    driver_id UInt32,
    driver_name String,
    company String,
    fare_amount Float32,
    payment_type UInt8,
    payment_method String,
    vendor_id UInt8,
    vendor String,
    trip_distance Float32,
    trip_duration UInt32,
    tip_amount Float32,
    total_amount Float32
) ENGINE = MergeTree
ORDER BY event_time;

-- Очищаем и заполняем справочники vendors и payment_types
TRUNCATE TABLE vendors;
TRUNCATE TABLE payment_types;

INSERT INTO vendors VALUES
    (1, 'Alpha Cabs'),
    (2, 'Metro Taxi'),
    (3, 'City Express'),
    (4, 'GoGreen Mobility');

INSERT INTO payment_types VALUES
    (1, 'Credit Card'),
    (2, 'Cash'),
    (3, 'Prepaid'),
    (4, 'Dispute'),
    (5, 'Other'),
    (6, 'Cancelled');

-- ========================================================================================
-- Представления (VIEW): агрегации без хранения, используют trips_raw напрямую
-- ========================================================================================

-- Средний чек по маршрутам
DROP VIEW IF EXISTS avg_fare_by_route;
CREATE VIEW avg_fare_by_route AS
SELECT
    route_name,
    avg(fare_amount) AS avg_fare
FROM trips_raw
GROUP BY route_name;

-- Топ маршрутов за последнюю неделю по количеству поездок
DROP VIEW IF EXISTS top_routes_last_week;
CREATE VIEW top_routes_last_week AS
SELECT
    route_name,
    count() AS trip_count
FROM trips_raw
WHERE event_time >= now() - INTERVAL 7 DAY
GROUP BY route_name
ORDER BY trip_count DESC
LIMIT 10;

-- ========================================================================================
-- Таблица для хранения распределения длительности поездок (используется MV)
-- ========================================================================================

DROP TABLE IF EXISTS trip_duration_distribution_data SYNC;
CREATE TABLE trip_duration_distribution_data
(
    trip_duration Float32
)
ENGINE = MergeTree
ORDER BY trip_duration;

-- ========================================================================================
-- Материализованные представления (MV): агрегации с хранением
-- ========================================================================================

-- Поездки по часу и маршрутам/водителям
CREATE MATERIALIZED VIEW trips_by_hour
ENGINE = SummingMergeTree
PARTITION BY toYYYYMMDD(hour)
ORDER BY (route_name, driver_name, hour)
AS
SELECT
    toStartOfHour(event_time) AS hour,
    route_name,
    driver_name,
    count() AS trip_count,
    sum(fare_amount) AS total_revenue
FROM trips_raw
GROUP BY hour, route_name, driver_name;

-- Сводка по водителям
CREATE MATERIALIZED VIEW trips_by_driver_name
ENGINE = SummingMergeTree
PARTITION BY toYYYYMMDD(hour)
ORDER BY (driver_name, hour)
AS
SELECT
    toStartOfHour(event_time) AS hour,
    driver_name,
    count() AS trip_count,
    sum(fare_amount) AS total_revenue
FROM trips_raw
GROUP BY hour, driver_name;

-- Сводка по типам оплаты
CREATE MATERIALIZED VIEW trips_by_payment_type
ENGINE = SummingMergeTree
PARTITION BY toYYYYMMDD(hour)
ORDER BY (payment_method, hour)
AS
SELECT
    toStartOfHour(event_time) AS hour,
    payment_method,
    count() AS trip_count,
    sum(fare_amount) AS total_revenue
FROM trips_raw
GROUP BY hour, payment_method;

-- Сводка по поставщикам машин
CREATE MATERIALIZED VIEW revenue_by_vendor
ENGINE = SummingMergeTree
PARTITION BY toYYYYMMDD(hour)
ORDER BY (vendor, hour)
AS
SELECT
    toStartOfHour(event_time) AS hour,
    vendor,
    count() AS trip_count,
    sum(fare_amount) AS total_revenue
FROM trips_raw
GROUP BY hour, vendor;

-- ========================================================================================
-- LIVE аналитика — материализованные представления с TTL (хранят только последние 15 минут)
-- ========================================================================================

CREATE MATERIALIZED VIEW revenue_by_vendor_last_15m
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMMDD(event_time)
ORDER BY (vendor, event_time)
TTL event_time + INTERVAL 15 MINUTE DELETE
AS
SELECT
    vendor,
    event_time,
    toStartOfMinute(event_time) AS minute,
    countState() AS trip_count,
    sumState(fare_amount) AS total_revenue
FROM trips_raw
GROUP BY vendor, minute, event_time;

CREATE MATERIALIZED VIEW trips_by_payment_type_last_15m
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMMDD(event_time)
ORDER BY (payment_method, event_time)
TTL event_time + INTERVAL 15 MINUTE DELETE
AS
SELECT
    payment_method,
    event_time,
    toStartOfMinute(event_time) AS minute,
    countState() AS trip_count,
    sumState(fare_amount) AS total_revenue
FROM trips_raw
GROUP BY payment_method, minute, event_time;

CREATE MATERIALIZED VIEW avg_fare_by_route_last_15m
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMMDD(event_time)
ORDER BY (route_name, event_time)
TTL event_time + INTERVAL 15 MINUTE DELETE
AS
SELECT
    route_name,
    event_time,
    toStartOfMinute(event_time) AS minute,
    avgState(fare_amount) AS avg_fare
FROM trips_raw
GROUP BY route_name, minute, event_time;

CREATE MATERIALIZED VIEW trips_by_driver_last_15m
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMMDD(event_time)
ORDER BY (driver_name, event_time)
TTL event_time + INTERVAL 15 MINUTE DELETE
AS
SELECT
    driver_name,
    event_time,
    toStartOfMinute(event_time) AS minute,
    countState() AS trip_count,
    sumState(fare_amount) AS total_revenue
FROM trips_raw
GROUP BY driver_name, minute, event_time;

-- ========================================================================================
-- MV для записи в trip_duration_distribution_data (не TTL)
-- ========================================================================================

CREATE MATERIALIZED VIEW trip_duration_distribution
TO trip_duration_distribution_data
AS
SELECT
    trip_duration * 1.0 AS trip_duration
FROM trips_raw
WHERE trip_duration IS NOT NULL;

-- ========================================================================================
-- MV с TTL для анализа распределения длительности за последние 15 минут
-- ========================================================================================

CREATE MATERIALIZED VIEW trip_duration_distribution_last_15m
ENGINE = SummingMergeTree
PARTITION BY toYYYYMMDD(event_time)
ORDER BY duration_bin
TTL event_time + toIntervalMinute(15)
AS
SELECT
    toStartOfMinute(event_time) AS event_time,
    trip_duration AS duration_bin,
    count() AS trip_count
FROM trips_raw
WHERE trip_duration > 0
GROUP BY trip_duration, event_time;