#!/data/data/com.termux/files/usr/bin/bash
# strudel-samples yarn puller v2
# Reads strudel-samples-v1-yarnclips.txt (name then yarn clip id, one clip per line),
# downloads each clip with browser style requests, converts it to mp3,
# rebuilds strudel.json, commits and pushes.

set -u
cd "$(dirname "$0")"

LIST="strudel-samples-v1-yarnclips.txt"
OUT="yarn"
LOG="strudel-samples-v2-yarnpull.log"
UA="Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
mkdir -p "$OUT"
: > "$LOG"

for tool in curl ffmpeg python git; do
  command -v "$tool" >/dev/null 2>&1 || pkg install -y "$tool"
done
command -v yt-dlp >/dev/null 2>&1 || pip install -q yt-dlp >/dev/null 2>&1

is_mp4 () {
  [ -s "$1" ] && python -c "import sys;d=open(sys.argv[1],'rb').read(64);sys.exit(0 if b'ftyp' in d else 1)" "$1"
}

try_curl () {
  local url="$1" dest="$2" ref="$3" code
  code=$(curl -sL --compressed -o "$dest" -w "%{http_code}" \
    -A "$UA" \
    -H "Accept: */*" \
    -H "Accept-Language: en-US,en;q=0.9" \
    -H "Range: bytes=0-" \
    -H "Referer: $ref" \
    -H "Origin: https://getyarn.io" \
    -H "Sec-Fetch-Dest: video" \
    -H "Sec-Fetch-Mode: no-cors" \
    -H "Sec-Fetch-Site: cross-site" \
    -H "sec-ch-ua-mobile: ?1" \
    -H "sec-ch-ua-platform: \"Android\"" \
    "$url")
  echo "curl $code $url" >> "$LOG"
  is_mp4 "$dest"
}

fetch_mp4 () {
  local id="$1" dest="$2" host ref
  for host in y.getyarn.io y.yarn.co; do
    for ref in "https://getyarn.io/" "https://getyarn.io/yarn-clip/$id" "https://yarn.co/"; do
      rm -f "$dest"
      try_curl "https://$host/$id.mp4" "$dest" "$ref" && return 0
    done
  done
  if command -v yt-dlp >/dev/null 2>&1; then
    for url in "https://y.yarn.co/$id.mp4" "https://getyarn.io/yarn-clip/$id" "https://yarn.co/yarn-clip/$id"; do
      rm -f "$dest"
      yt-dlp -q --no-warnings --referer "https://getyarn.io/" --user-agent "$UA" -o "$dest" "$url" >> "$LOG" 2>&1
      echo "yt-dlp $url" >> "$LOG"
      is_mp4 "$dest" && return 0
    done
  fi
  return 1
}

TMP=$(mktemp -d)
while read -r name id; do
  [ -z "${name:-}" ] && continue
  case "$name" in \#*) continue ;; esac
  if [ -s "$OUT/$name.mp3" ]; then echo "have $name"; continue; fi
  echo "pulling $name"
  title=$(curl -sL -A "$UA" -H "Accept: text/html" "https://getyarn.io/yarn-clip/$id" | grep -o '<title>[^<]*' | head -n 1 | sed 's/<title>//')
  echo "$name | $id | $title" >> strudel-samples-v2-titles.log
  if fetch_mp4 "$id" "$TMP/$name.mp4"; then
    ffmpeg -loglevel error -y -i "$TMP/$name.mp4" -vn -ac 1 -ar 44100 -b:a 128k "$OUT/$name.mp3" && echo "saved $name"
  else
    echo "FAILED $name"
  fi
done < "$LIST"
rm -rf "$TMP"

python - <<'PY'
import json, os
base = "https://raw.githubusercontent.com/sudosilo/strudel-samples/main/"
try:
    data = json.load(open("strudel.json"))
except Exception:
    data = {}
data["_base"] = base
for f in sorted(os.listdir("yarn")):
    if f.endswith(".mp3"):
        data[f[:-4]] = ["yarn/" + f]
json.dump(data, open("strudel.json", "w"), indent=2)
print("strudel.json now maps", ", ".join(k for k in data if k != "_base"))
PY

gh auth setup-git >/dev/null 2>&1
git add yarn strudel.json "$LOG" strudel-samples-v2-titles.log
git commit -m "Yarn clips pull run" >/dev/null 2>&1 && git push origin main
echo "done"
