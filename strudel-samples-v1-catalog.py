"""strudel-samples catalog v1

The catalog CSV is the record of every sound file in this repo: where it came from
(show, year, episode, yarn clip), what it says, and the Strudel name that plays it.

Every file is named   <words said>_<show>_<episode>_<yarn id>.mp3
for example           hello_the-office_s08e02_083c96f3.mp3

Run   python strudel-samples-v1-catalog.py   to rebuild strudel.json from the catalog.
The pullers import this file to name new clips and add catalog rows.
"""
import csv, datetime, html, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOG = os.path.join(HERE, "strudel-samples-v1-catalog.csv")
STRUDEL_JSON = os.path.join(HERE, "strudel.json")
BASE = "https://raw.githubusercontent.com/sudosilo/strudel-samples/main/"
FIELDS = ["file", "strudel_name", "kind", "words", "quote", "show", "year",
          "episode", "episode_title", "yarn_id", "yarn_url", "made_from", "pulled", "notes"]


def slug(text, sep="-"):
    text = html.unescape(text or "").lower().replace("’", "'").replace("'", "").replace("&", "and")
    return sep.join(re.findall(r"[a-z0-9]+", text))


def parse_show(full):
    """'Ozark (2017) - S01E02 Blue Cat' -> show, year, episode, episode title."""
    full = html.unescape(full or "").strip()
    m = re.match(r"^(.*?)\s*\((\d{4})\)\s*(?:-\s*(S\d+E\d+)\s*(.*))?$", full)
    if not m:
        return full, "", "", ""
    return m.group(1).strip(), m.group(2), (m.group(3) or "").lower(), (m.group(4) or "").strip()


def file_name(words, show, episode, yarn_id):
    ep = episode.lower() if episode else "movie"
    return "%s_%s_%s_%s.mp3" % (slug(words), slug(show) or "unknown", ep, (yarn_id or "")[:8])


def read():
    if not os.path.exists(CATALOG):
        return []
    with open(CATALOG, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def write(rows):
    rows = sorted(rows, key=lambda r: (r["strudel_name"], r["file"]))
    with open(CATALOG, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in FIELDS})


def add(row):
    rows = [r for r in read() if r["file"] != row["file"]]
    row.setdefault("pulled", datetime.date.today().isoformat())
    rows.append(row)
    write(rows)


def build_strudel_json():
    groups = {}
    for r in read():
        if os.path.exists(os.path.join(HERE, r["file"])):
            groups.setdefault(r["strudel_name"], []).append(r["file"])
    data = {"_base": BASE}
    for name in sorted(groups):
        data[name] = sorted(groups[name])
    with open(STRUDEL_JSON, "w") as fh:
        json.dump(data, fh, indent=2)
    return data


if __name__ == "__main__":
    d = build_strudel_json()
    print("strudel.json rebuilt with", len(d) - 1, "names")
