CREATE DATABASE IF NOT EXISTS app;

CREATE TABLE app.test_data
(
    id Int32,
    message String,
    timestamp DateTime
)
ENGINE = MergeTree
ORDER BY (id, timestamp);

CREATE TABLE app.kafka_stream
(
    id Int32,
    message String,
    timestamp DateTime
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'test_topic',
    kafka_group_name = 'clickhouse_consumer',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1;

CREATE MATERIALIZED VIEW app.kafka_mv TO app.test_data AS
SELECT * FROM app.kafka_stream;
