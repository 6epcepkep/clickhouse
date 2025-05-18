import csv
from clickhouse_driver import Client

CSV_PATH = "yellow_tripdata_2016-01.csv"
ROUTES_TABLE = "routes"

client = Client('localhost')

def extract_unique_routes():
    unique_pairs = set()
    with open(CSV_PATH, newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            try:
                from_id = int(row['PULocationID'])
                to_id = int(row['DOLocationID'])
                if from_id > 0 and to_id > 0:
                    unique_pairs.add((from_id, to_id))
            except Exception:
                continue
    return list(unique_pairs)

def generate_routes(pairs):
    values = []
    for i, (from_id, to_id) in enumerate(pairs, start=1):
        route_name = f"Zone {from_id} → Zone {to_id}"
        values.append((i, route_name, to_id))
    return values

def insert_routes():
    pairs = extract_unique_routes()
    if not pairs:
        print("⚠ No valid routes found in CSV.")
        return
    routes = generate_routes(pairs)
    client.execute(f"TRUNCATE TABLE {ROUTES_TABLE}")
    client.execute(f"INSERT INTO {ROUTES_TABLE} VALUES", routes, types_check=True)
    print(f"✅ Loaded {len(routes)} routes from CSV.")

if __name__ == "__main__":
    insert_routes()

