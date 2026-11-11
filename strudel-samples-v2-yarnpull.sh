#!/data/data/com.termux/files/usr/bin/bash
# strudel-samples yarn clip puller v2
# Reads strudel-samples-v1-yarnclips.txt (Strudel name, a space, then the yarn clip id),
# downloads each new clip into yarn/ named <words said>_<show>_<episode>_<yarn id>.mp3,
# records it in strudel-samples-v1-catalog.csv, rebuilds strudel.json, commits and pushes.

set -u
cd "$(dirname "$0")"

for tool in curl ffmpeg python git; do
  command -v "$tool" >/dev/null 2>&1 || pkg install -y "$tool"
done

python - <<'PY'
import html, importlib.util, os, re, subprocess, tempfile

spec = importlib.util.spec_from_file_location("cat", "strudel-samples-v1-catalog.py")
cat = importlib.util.module_from_spec(spec); spec.loader.exec_module(cat)

UA = "Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
os.makedirs("yarn", exist_ok=True)
log = open("strudel-samples-v2-titles.log", "a", encoding="utf-8")

def curl(url, dest=None, ref="https://getyarn.io/"):
    args = ["curl", "-sL", "--compressed", "-A", UA,
            "-H", "Accept-Language: en-US,en;q=0.9", "-H", "Referer: " + ref]
    if dest:
        subprocess.run(args + ["-H", "Range: bytes=0-", "-o", dest, url])
        return None
    return subprocess.run(args + ["-H", "Accept: text/html", url], capture_output=True).stdout.decode("utf-8", "replace")

have = {r["strudel_name"] for r in cat.read()}
added = []
for line in open("strudel-samples-v1-yarnclips.txt"):
    bits = line.split()
    if len(bits) < 2 or bits[0].startswith("#"):
        continue
    name, cid = bits[0], bits[1]
    if name in have:
        print("have", name)
        continue
    print("pulling", name)
    m = re.search(r"<title>([^<]*)", curl("https://getyarn.io/yarn-clip/" + cid))
    parts = [p.strip() for p in html.unescape(m.group(1) if m else "").split("|")]
    quote = parts[1] if len(parts) > 1 else name
    full = parts[2] if len(parts) > 2 else ""
    log.write("%s | %s | %s | %s\n" % (name, cid, quote, full))
    tmp = tempfile.mktemp(suffix=".mp4")
    good = False
    for host in ("y.getyarn.io", "y.yarn.co"):
        curl("https://%s/%s.mp4" % (host, cid), tmp, "https://getyarn.io/yarn-clip/" + cid)
        if os.path.exists(tmp) and b"ftyp" in open(tmp, "rb").read(64):
            good = True
            break
    if not good:
        print("FAILED", name)
        continue
    show, year, ep, title = cat.parse_show(full)
    words = re.sub(r"\(.*?\)", "", quote).strip(" -") or name
    path = os.path.join("yarn", cat.file_name(words, show, ep, cid))
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-vn", "-ac", "1",
                    "-ar", "44100", "-b:a", "128k", path])
    os.remove(tmp)
    cat.add(dict(file=path, strudel_name=name, kind="clip", words=words.lower(), quote=quote, show=show,
                 year=year, episode=ep, episode_title=title, yarn_id=cid,
                 yarn_url="https://getyarn.io/yarn-clip/" + cid, notes="untrimmed"))
    added.append("%s (%s %s)" % (name, show, ep))
    print("saved", path)

log.close()
cat.build_strudel_json()
open(".strudel-samples-commit-msg", "w").write(
    "Clip pull: added %d clips\n\n%s\n" % (len(added), "\n".join(added) or "none"))
PY

gh auth setup-git >/dev/null 2>&1
git add yarn strudel.json strudel-samples-v1-catalog.csv strudel-samples-v2-titles.log
git commit -F .strudel-samples-commit-msg >/dev/null 2>&1 && git push origin main
rm -f .strudel-samples-commit-msg
echo "done"
