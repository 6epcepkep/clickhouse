from airflow import DAG
from airflow.operators.python import PythonOperator
from clickhouse_driver import Client
from datetime import datetime, timedelta
import logging

# Функция для загрузки данных в ClickHouse
def load_to_clickhouse(**context):
    try:
        client = Client(
            host='clickhouse',
            port=9000,
            user='airflow',
            password='airflow',
            database='airflow'
        )
        data = context["ti"].xcom_pull(task_ids="transform_data")
        client.execute('INSERT INTO test_table VALUES', data)
        logging.info(f"Inserted {len(data)} rows")
    except Exception as e:
        logging.error(f"Error: {str(e)}")
        raise

# Определение DAG с обязательными параметрами
with DAG(
    'clickhouse_etl',
    default_args={
        'owner': 'airflow',
        'depends_on_past': False,
        'start_date': datetime(2025, 5, 1),  # Обязательный параметр
        'retries': 3,
        'retry_delay': timedelta(minutes=1)
    },
    schedule_interval='*/2 * * * *',  # Расписание выполнения
    catchup=False,  # Отключить выполнение пропущенных задач
    tags=['ETL', 'ClickHouse']
) as dag:

    load_task
