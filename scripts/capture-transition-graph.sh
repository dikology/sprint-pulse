#!/usr/bin/env bash
# Capture the Operator's real Jira transition graph while live responses are available.
#
# The graph behind `fixtures/m2-transition-graph.json` can only come from a live instance, and it
# goes stale the moment the workflow changes — so it is worth re-running before M2 builds the
# confirmation rule ("an Intent needs confirmation exactly when no transition returns") on it.
#
# Configuration comes from the app's own preferences and the credential from the app's own
# Keychain item, so nothing about a particular instance is written into this repository. Raw
# responses land in `captures/`, which `.gitignore` keeps local: they carry real Issue keys, real
# users, and instance-authored text. The committed fixture is always the anonymised one.
#
# Usage: scripts/capture-transition-graph.sh [sprint-id]
#   With no argument, the sprint currently named as tracked is used.
set -euo pipefail

DOMAIN=SprintPulse            # an SPM executable writes its preferences under the executable name
SERVICE=dev.dikology.sprintpulse.jira
ACCOUNT=personal-access-token

base_url=$(defaults read "$DOMAIN" jira-base-url 2>/dev/null || true)
sprint_id=${1:-$(defaults read "$DOMAIN" jira-tracked-sprint-id 2>/dev/null || true)}
token=$(security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w || true)

if [[ -z "$base_url" || -z "$sprint_id" || -z "$token" ]]; then
  echo "Need a base URL, a tracked sprint, and a stored credential, all from the app." >&2
  echo "Got: base-url='$base_url' sprint='$sprint_id' token-length=${#token}" >&2
  exit 1
fi
base_url=${base_url%/}
auth="Authorization: Bearer $token"

# Anchored on the repository, not the working directory: raw responses from a live instance are
# only ever safe to leave where .gitignore can not see them, and a relative path would put them
# under whatever directory this happened to be run from.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out="$root/captures/$(date +%F)"
mkdir -p "$out/transitions"

# Every page of the sprint's Issues. The graph is only complete over the whole sprint, and the
# statuses nothing is sitting in tonight are exactly the ones whose return path stays unknown.
for ((start = 0; start < 2000; start += 50)); do
  file="$out/sprint-$sprint_id-issues-$start.json"
  curl -sS --fail -o "$file" -H "$auth" \
    "$base_url/rest/agile/1.0/sprint/$sprint_id/issue?maxResults=50&startAt=$start"
  count=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['issues']))" "$file")
  if ((count == 0)); then
    break
  fi
done

python3 - "$out" "$sprint_id" "$out/issue-keys.txt" <<'PY'
import glob, json, os, sys
keys = []
for path in sorted(glob.glob(os.path.join(sys.argv[1], f"sprint-{sys.argv[2]}-issues-*.json"))):
    for issue in json.load(open(path)).get("issues", []):
        keys.append(issue["key"])
open(sys.argv[3], "w").write("".join(k + "\n" for k in keys))
PY

if [[ ! -s "$out/issue-keys.txt" ]]; then
  echo "Sprint $sprint_id returned no Issues." >&2
  exit 1
fi

while IFS= read -r key; do
  curl -sS --fail -o "$out/transitions/$key.json" -H "$auth" \
    "$base_url/rest/api/2/issue/$key/transitions"
done < "$out/issue-keys.txt"

echo "Captured $(wc -l < "$out/issue-keys.txt" | tr -d ' ') Issues into $out/transitions."
echo "Anonymise before anything is committed — the raw files name real Issues and real people."
