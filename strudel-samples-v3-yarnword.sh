#!/data/data/com.termux/files/usr/bin/bash
# strudel-samples yarn word puller v3
# Usage: bash strudel-samples-v3-yarnword.sh hello
# Searches getyarn for a word or short phrase, keeps the clips where the line is
# basically just that phrase, saves each one in words/<phrase>/ named
# <words>_<show>_<episode>_<yarn id>.mp3, records every clip in
# strudel-samples-v1-catalog.csv, rebuilds strudel.json, commits and pushes.

set -u
cd "$(dirname "$0")"
PHRASE="${*:-hello}"

for tool in curl ffmpeg python git; do
  command -v "$tool" >/dev/null 2>&1 || pkg install -y "$tool"
done

python - "$PHRASE" <<'PY'
import html, importlib.util, os, re, subprocess, sys, tempfile

spec = importlib.util.spec_from_file_location("cat", "strudel-samples-v1-catalog.py")
cat = importlib.util.module_from_spec(spec); spec.loader.exec_module(cat)

phrase = sys.argv[1].strip().lower()
name = re.sub(r"[^a-z0-9]+", "", phrase) or "word"
outdir = os.path.join("words", name)
os.makedirs(outdir, exist_ok=True)
log = open(os.path.join(outdir, name + "-titles.log"), "a", encoding="utf-8")

UA = "Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
MAX_KEEP = 80
MAX_PAGES = 15
MAX_WORDS = len(phrase.split()) + 2

def curl(url, dest=None, ref="https://getyarn.io/"):
    args = ["curl", "-sL", "--compressed", "-A", UA,
            "-H", "Accept-Language: en-US,en;q=0.9", "-H", "Referer: " + ref]
    if dest:
        subprocess.run(args + ["-H", "Range: bytes=0-", "-o", dest, url])
        return None
    return subprocess.run(args + ["-H", "Accept: text/html", url], capture_output=True).stdout.decode("utf-8", "replace")

def norm(s):
    return " ".join(re.sub(r"[^a-z' ]+", " ", html.unescape(s).lower().replace("’", "'")).split())

have = {r["yarn_id"][:8] for r in cat.read() if r["strudel_name"] == name}
dropfile = os.path.join(outdir, name + "-dropped.txt")
if os.path.exists(dropfile):
    have |= {l.strip() for l in open(dropfile) if l.strip()}
kept = len([r for r in cat.read() if r["strudel_name"] == name])
added = []
seen = set()
q = phrase.replace(" ", "+")

for page in range(MAX_PAGES):
    if kept >= MAX_KEEP:
        break
    body = curl("https://getyarn.io/yarn-find?text=%s&p=%d" % (q, page))
    ids = [i for i in dict.fromkeys(re.findall(r"yarn-clip/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})", body)) if i not in seen]
    print("page", page, "found", len(ids), "clips")
    if not ids:
        break
    for cid in ids:
        seen.add(cid)
        if cid[:8] in have:
            continue
        m = re.search(r"<title>([^<]*)", curl("https://getyarn.io/yarn-clip/" + cid))
        parts = [p.strip() for p in html.unescape(m.group(1) if m else "").split("|")]
        quote = parts[1] if len(parts) > 1 else ""
        full = parts[2] if len(parts) > 2 else ""
        words = norm(quote).split()
        ok = phrase in norm(quote) and 0 < len(words) <= MAX_WORDS
        log.write("%s | %s | %s | %s\n" % ("KEEP" if ok else "skip", cid, quote, full))
        if not ok:
            continue
        tmp = tempfile.mktemp(suffix=".mp4")
        good = False
        for host in ("y.getyarn.io", "y.yarn.co"):
            curl("https://%s/%s.mp4" % (host, cid), tmp, "https://getyarn.io/yarn-clip/" + cid)
            if os.path.exists(tmp) and b"ftyp" in open(tmp, "rb").read(64):
                good = True
                break
        if not good:
            print("FAILED", cid[:8], quote)
            continue
        show, year, ep, title = cat.parse_show(full)
        path = os.path.join(outdir, cat.file_name(phrase, show, ep, cid))
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-vn", "-ac", "1",
                        "-ar", "44100", "-b:a", "128k", path])
        os.remove(tmp)
        cat.add(dict(file=path, strudel_name=name, kind="word", words=phrase, quote=quote, show=show,
                     year=year, episode=ep, episode_title=title, yarn_id=cid,
                     yarn_url="https://getyarn.io/yarn-clip/" + cid, notes="untrimmed"))
        kept += 1
        added.append(show)
        print("saved", path)
        if kept >= MAX_KEEP:
            break

log.close()
cat.build_strudel_json()
shows = sorted(set(added))
open(".strudel-samples-commit-msg", "w").write(
    "Word pull: %s, added %d clips\n\nShows: %s\n" % (phrase, len(added), ", ".join(shows) or "none"))
print("catalog and strudel.json updated, added", len(added), "clips under", name)
PY

gh auth setup-git >/dev/null 2>&1
git add words strudel.json strudel-samples-v1-catalog.csv
git commit -F .strudel-samples-commit-msg >/dev/null 2>&1 && git push origin main
rm -f .strudel-samples-commit-msg
echo "done"
