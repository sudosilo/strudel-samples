#!/data/data/com.termux/files/usr/bin/bash
# strudel-samples yarn word puller v3
# Usage: bash strudel-samples-v3-yarnword.sh hello
# Searches getyarn for a word or short phrase, keeps the clips where the line is
# basically just that phrase, saves each one as an mp3 in words/<phrase>/,
# rebuilds strudel.json, commits and pushes.

set -u
cd "$(dirname "$0")"
PHRASE="${*:-hello}"

for tool in curl ffmpeg python git; do
  command -v "$tool" >/dev/null 2>&1 || pkg install -y "$tool"
done

python - "$PHRASE" <<'PY'
import html, json, os, re, subprocess, sys, tempfile

phrase = sys.argv[1].strip().lower()
slug = re.sub(r"[^a-z0-9]+", "", phrase) or "word"
outdir = os.path.join("words", slug)
os.makedirs(outdir, exist_ok=True)
log = open(os.path.join(outdir, slug + "-titles.log"), "a")

UA = "Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
MAX_KEEP = 80
MAX_PAGES = 15
MAX_WORDS = len(phrase.split()) + 2

def curl(url, dest=None, ref="https://getyarn.io/"):
    args = ["curl", "-sL", "--compressed", "-A", UA,
            "-H", "Accept-Language: en-US,en;q=0.9",
            "-H", "Referer: " + ref]
    if dest:
        args += ["-H", "Range: bytes=0-", "-o", dest, url]
        subprocess.run(args)
        return None
    args += ["-H", "Accept: text/html", url]
    return subprocess.run(args, capture_output=True).stdout.decode("utf-8", "replace")

def norm(s):
    return " ".join(re.sub(r"[^a-z' ]+", " ", s.lower().replace("’", "'")).split())

have = {f.rsplit("-", 1)[-1][:-4] for f in os.listdir(outdir) if f.endswith(".mp3")}
seen, kept = set(), len(have)
q = phrase.replace(" ", "+")

for page in range(MAX_PAGES):
    if kept >= MAX_KEEP:
        break
    url = "https://getyarn.io/yarn-find?text=%s&p=%d" % (q, page)
    body = curl(url)
    open(os.path.join(outdir, "%s-search-p%d.html" % (slug, page)), "w").write(body)
    ids = [i for i in dict.fromkeys(re.findall(r"yarn-clip/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})", body)) if i not in seen]
    print("page", page, "found", len(ids), "clips")
    if not ids:
        break
    for cid in ids:
        seen.add(cid)
        short = cid[:8]
        if short in have:
            continue
        page_html = curl("https://getyarn.io/yarn-clip/" + cid)
        m = re.search(r"<title>([^<]*)", page_html)
        title = html.unescape(m.group(1)) if m else ""
        parts = [p.strip() for p in title.split("|")]
        quote = parts[1] if len(parts) > 1 else ""
        show = parts[2] if len(parts) > 2 else ""
        words = norm(quote).split()
        ok = phrase in norm(quote) and 0 < len(words) <= MAX_WORDS
        log.write("%s | %s | %s | %s\n" % ("KEEP" if ok else "skip", cid, quote, show))
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
            print("FAILED", short, quote)
            continue
        showslug = re.sub(r"[^a-z0-9]+", "", show.split("(")[0].lower())[:20] or "show"
        mp3 = os.path.join(outdir, "%s-%s-%s.mp3" % (slug, showslug, short))
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-vn", "-ac", "1",
                        "-ar", "44100", "-b:a", "128k", mp3])
        os.remove(tmp)
        kept += 1
        print("saved", kept, show, "|", quote)
        if kept >= MAX_KEEP:
            break

log.close()

base = "https://raw.githubusercontent.com/sudosilo/strudel-samples/main/"
try:
    data = json.load(open("strudel.json"))
except Exception:
    data = {}
data["_base"] = base
for f in sorted(os.listdir("yarn")):
    if f.endswith(".mp3"):
        data[f[:-4]] = ["yarn/" + f]
for w in sorted(os.listdir("words")):
    files = sorted(f for f in os.listdir(os.path.join("words", w)) if f.endswith(".mp3"))
    if files:
        data[w] = ["words/%s/%s" % (w, f) for f in files]
json.dump(data, open("strudel.json", "w"), indent=2)
print("strudel.json updated,", slug, "has", len(data.get(slug, [])), "clips")
PY

gh auth setup-git >/dev/null 2>&1
git add words strudel.json
git commit -m "Word pull: $PHRASE" >/dev/null 2>&1 && git push origin main
echo "done"
