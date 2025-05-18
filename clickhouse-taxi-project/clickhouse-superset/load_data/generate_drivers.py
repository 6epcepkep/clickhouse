import csv
import random
from clickhouse_driver import Client

client = Client('localhost')

CSV_PATH = 'yellow_tripdata_2016-01.csv'
DRIVERS_TABLE = 'drivers'

first_names = [
    "James", "John", "Robert", "Michael", "William", "David", "Richard", "Joseph",
    "Thomas", "Charles", "Daniel", "Matthew", "Anthony", "Mark", "Donald", "Steven",
    "Paul", "Andrew", "Joshua", "Kevin"
]

last_names = [
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
    "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson",
    "Thomas", "Taylor", "Moore", "Jackson", "Martin"
]

companies = [
    "AlphaCab", "CityRide", "GoExpress", "MetroTaxi", "SkyTransport",
    "YellowLine", "UrbanWay", "NextRide", "QuickCab", "GreenGo"
]

def extract_driver_ids_from_csv():
    driver_ids = set()
    with open(CSV_PATH, newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            do_loc = row.get('DOLocationID')
            if do_loc and do_loc.isdigit():
                driver_ids.add(int(do_loc))
    return sorted(driver_ids)

def generate_driver_name():
    first = random.choice(first_names)
    last = random.choice(last_names)
    return f"{first} {last}"

def generate_drivers():
    driver_ids = extract_driver_ids_from_csv()
    rows = []
    for driver_id in driver_ids:
        name = generate_driver_name()
        company = random.choice(companies)
        rows.append((driver_id, name, company))
    return rows

def insert_drivers():
    rows = generate_drivers()
    client.execute(f"TRUNCATE TABLE {DRIVERS_TABLE}")
    client.execute(f"INSERT INTO {DRIVERS_TABLE} VALUES", rows, types_check=True)
    print(f"✅ Loaded {len(rows)} drivers from CSV.")

if __name__ == "__main__":
    insert_drivers()

