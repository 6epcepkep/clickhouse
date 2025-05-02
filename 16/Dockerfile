FROM apache/airflow:2.8.1

USER root

RUN apt-get update && \
    apt-get install -y python3-dev gcc unixodbc-dev

USER airflow

RUN pip install --no-cache-dir clickhouse-driver==0.2.6
