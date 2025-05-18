import pandas as pd

# Загрузка Parquet-файла
df = pd.read_parquet("yellow_tripdata_2016-01.parquet")

# Сохранение в CSV
df.to_csv("yellow_tripdata_2016-01.csv", index=False)

print("✅ Конвертация завершена.")

