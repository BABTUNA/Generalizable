from idc_index import IDCClient
c = IDCClient()
df = c.sql_query("""
  SELECT SeriesInstanceUID, StudyInstanceUID, Modality, SeriesDescription, series_size_MB,
         instanceCount, StudyDescription, BodyPartExamined
  FROM index WHERE collection_id = 'nlm_visible_human_project' AND PatientID='VHP-M' AND Modality='CT'
  ORDER BY series_size_MB DESC
""")
import pandas as pd
pd.set_option('display.max_colwidth', None)
pd.set_option('display.width', 250)
print(df.to_string())
df.to_csv('data/work/vhp_male_ct_series.csv', index=False)
