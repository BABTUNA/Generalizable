from idc_index import IDCClient
c = IDCClient()
series = [
    "1.3.6.1.4.1.5962.1.3.1174.2.1672334394.26545",
    "1.3.6.1.4.1.5962.1.3.1174.5.1672334394.26545",
]
c.download_from_selection(seriesInstanceUID=series, downloadDir="data/raw/vhp_male_ct")
print("DOWNLOAD_DONE")
