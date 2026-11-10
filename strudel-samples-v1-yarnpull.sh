#!/data/data/com.termux/files/usr/bin/bash
# strudel-samples yarn puller v1
# Reads strudel-samples-v1-yarnclips.txt (name then yarn clip id, one clip per line),
# downloads each clip, converts it to mp3, rebuilds strudel.json, commits and pushes.

set -u
cd "$(dirname "$0")"

LIST="strudel-samples-v1-yarnclips.txt"
OUT="yarn"
UA="Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36"
mkdir -p "$OUT"

for tool in curl ffmpeg python git; do
  command -v "$tool" >/dev/null 2>&1 || pkg install -y "$tool"
done

fetch_mp4 () {
  local id="$1" dest="$2"
  for url in "https://y.yarn.co/$id.mp4" "https://y.yarn.co/$id.mp4?v=1"; do
    curl -sL -A "$UA" -e "https://getyarn.io/yarn-clip/$id" -o "$dest" "$url"
    if [ -s "$dest" ] && head -c 12 "$dest" | grep -q ftyp; then return 0; fi
  done
  local page src
  page=$(curl -sL -A "$UA" "https://getyarn.io/yarn-clip/$id")
  src=$(printf '%s' "$page" | grep -oE 'https://[a-z0-9.]*yarn\.co/[^"'"'"' ]+\.mp4' | head -n 1)
  if [ -n "$src" ]; then
    curl -sL -A "$UA" -e "https://getyarn.io/" -o "$dest" "$src"
    if [ -s "$dest" ] && head -c 12 "$dest" | grep -q ftyp; then return 0; fi
  fi
  return 1
}

TMP=$(mktemp -d)
while read -r name id; do
  [ -z "${name:-}" ] && continue
  case "$name" in \#*) continue ;; esac
  if [ -s "$OUT/$name.mp3" ]; then echo "have $name"; continue; fi
  echo "pulling $name"
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
git add yarn strudel.json
git commit -m "Add yarn clips as Strudel samples" >/dev/null 2>&1 && git push origin main
echo "done"
