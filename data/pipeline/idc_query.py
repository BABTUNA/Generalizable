from idc_index import IDCClient
c = IDCClient()
df = c.sql_query("""
  SELECT PatientID, Modality, SeriesInstanceUID, SeriesDescription, series_size_MB
  FROM index WHERE collection_id = 'nlm_visible_human_project'
""")
import pandas as pd
pd.set_option('display.max_rows', 200)
pd.set_option('display.width', 200)
print(df.to_string())
df.to_csv('data/work/vhp_series.csv', index=False)
