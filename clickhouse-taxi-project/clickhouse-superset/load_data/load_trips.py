import csv
from datetime import datetime, timedelta
from clickhouse_driver import Client

client = Client('localhost')

# Загружаем справочники
vendors = dict(client.execute("SELECT vendor_id, vendor FROM vendors"))
payments = dict(client.execute("SELECT payment_type, payment_method FROM payment_types"))
driver_rows = client.execute("SELECT driver_id, driver_name, company FROM drivers")
drivers = {row[0]: (row[1], row[2]) for row in driver_rows}
route_rows = client.execute("SELECT route_id, route_name, to_id FROM routes")
routes = {row[0]: (row[1], row[2]) for row in route_rows}

csv_file = 'yellow_tripdata_2016-01.csv'
max_rows = 500_000
batch = []
inserted_total = 0
processed_rows = 0

# ШАГ 1. Определим минимальное значение времени в CSV
with open(csv_file, newline='') as f:
    reader = csv.DictReader(f)
    pickup_times = [
        datetime.strptime(row['tpep_pickup_datetime'], '%Y-%m-%d %H:%M:%S')
        for row in reader if row['tpep_pickup_datetime']
    ]
    min_original_pickup = min(pickup_times)

# ШАГ 2. Установим точку отсчета: 7 дней назад от текущего времени
reference_time = datetime.today().replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=7)

# ШАГ 3. Сдвигаем все поездки относительно этой точки
with open(csv_file, newline='') as f:
    reader = csv.DictReader(f)

    for row in reader:
        if processed_rows >= max_rows:
            break

        try:
            pickup_raw = row.get('tpep_pickup_datetime')
            dropoff_raw = row.get('tpep_dropoff_datetime')
            fare = row.get('fare_amount')
            pu_loc = row.get('PULocationID')
            do_loc = row.get('DOLocationID')

            if not pickup_raw or not dropoff_raw or not fare or not pu_loc or not do_loc:
                continue

            original_pickup = datetime.strptime(pickup_raw, '%Y-%m-%d %H:%M:%S')
            original_dropoff = datetime.strptime(dropoff_raw, '%Y-%m-%d %H:%M:%S')
            duration_seconds = (original_dropoff - original_pickup).total_seconds()

            if duration_seconds <= 0 or duration_seconds > 60 * 60 * 3:
                continue

            trip_duration = round(duration_seconds / 60.0)

            # Смещаем дату
            pickup = reference_time + (original_pickup - min_original_pickup)

            pu = int(pu_loc)
            do = int(do_loc)
            route_id = 100 * pu + do
            driver_id = do

            if driver_id not in drivers:
                continue

            route_name = routes.get(route_id, (f"Zone {pu} → Zone {do}", None))[0]
            driver_name, company = drivers.get(driver_id)
            vendor_id = int(row.get('VendorID', 0))
            payment_type = int(row.get('payment_type', 0))

            batch.append((
                pickup,
                route_id,
                route_name,
                driver_id,
                driver_name,
                company,
                float(fare),
                payment_type,
                payments.get(payment_type, 'Unknown'),
                vendor_id,
                vendors.get(vendor_id, 'Unknown'),
                float(row.get('trip_distance', 0)),
                trip_duration,
                float(row.get('tip_amount', 0)),
                float(row.get('total_amount', 0))
            ))
            processed_rows += 1

        except Exception as e:
            print(f"Ошибка в строке: {row}\n{e}")

    if batch:
        client.execute("TRUNCATE TABLE trips_raw")
        client.execute("INSERT INTO trips_raw VALUES", batch, types_check=True)
        inserted_total += len(batch)

print(f"✅ Загружено строк: {inserted_total} из {max_rows}")

