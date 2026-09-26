import zipfile
from pathlib import Path

zpath = "data/raw/seg_cq500/Seg-CQ500.zip"
with zipfile.ZipFile(zpath) as z:
    names = z.namelist()
print("total entries:", len(names))
for n in names[:40]:
    print(n)
print("...")
# guess structure: look for directories / unique top-level case ids
tops = sorted(set(n.split("/")[0] for n in names))
print("top-level entries (first 20):", tops[:20], "... total", len(tops))
