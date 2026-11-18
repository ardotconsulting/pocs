#!/usr/bin/env bash
# Adds, updates or removes one POC's tile on the Flame dashboard, matched by
# name. Called by terraform_data.flame_tile in pocs.tf; never prints the
# password or the session token. A POC that isn't serving yet (no 2xx) gets a
# tile hidden from visitors; `activate` makes every hidden *.poc tile public
# once its app answers (run on a schedule by .github/workflows/activate.yml).
#   flame-tile.sh add|remove|activate
# Env: FLAME_URL, FLAME_PASSWORD, and for add/remove TILE_NAME, for add
#      TILE_URL and TILE_DESCRIPTION
set -euo pipefail

# 2xx after redirects; a POC with no app yet gets a 404 from the proxy.
live() {
  local code
  code=$(curl -s -o /dev/null -L -w '%{http_code}' -m 15 "$1" || true)
  [ "$code" -ge 200 ] && [ "$code" -lt 300 ]
}

token=$(jq -n --arg p "$FLAME_PASSWORD" '{password: $p, duration: "1h"}' |
  curl -sf -m 20 -H "Content-Type: application/json" --data @- "$FLAME_URL/api/auth" |
  jq -r '.data.token')
auth="Authorization-Flame: Bearer $token"

apps=$(curl -sf -m 20 -H "$auth" "$FLAME_URL/api/apps")
id=$(jq -r --arg n "${TILE_NAME:-}" '[.data[] | select(.name == $n)][0].id // empty' <<<"$apps")

case "$1" in
add)
  public=0
  live "$TILE_URL" && public=1
  body=$(jq -n --arg n "$TILE_NAME" --arg u "$TILE_URL" --arg d "$TILE_DESCRIPTION" --argjson p "$public" \
    '{name: $n, url: $u, description: $d, icon: "flask-outline", isPublic: $p}')
  [ "$public" = 1 ] || echo "$TILE_NAME isn't serving yet: tile hidden from visitors"
  if [ -n "$id" ]; then
    curl -sf -m 20 -o /dev/null -X PUT -H "$auth" -H "Content-Type: application/json" --data "$body" "$FLAME_URL/api/apps/$id"
    echo "Updated Flame tile: $TILE_NAME"
  else
    curl -sf -m 20 -o /dev/null -X POST -H "$auth" -H "Content-Type: application/json" --data "$body" "$FLAME_URL/api/apps"
    echo "Added Flame tile: $TILE_NAME"
  fi
  ;;
activate)
  n=0
  while IFS=$'\t' read -r tid tname turl; do
    [ -n "$tid" ] || continue
    if live "$turl"; then
      curl -sf -m 20 -o /dev/null -X PUT -H "$auth" -H "Content-Type: application/json" \
        --data '{"isPublic": 1}' "$FLAME_URL/api/apps/$tid"
      echo "$tname is live: tile made public"
      n=$((n + 1))
    fi
  done < <(jq -r '.data[] | select(.isPublic == 0 and (.url | test("^https://[a-z0-9-]+\\.poc\\.ardotconsulting\\.com"))) | [.id, .name, .url] | @tsv' <<<"$apps")
  echo "Activated $n tile(s)."
  ;;
remove)
  if [ -n "$id" ]; then
    curl -sf -m 20 -o /dev/null -X DELETE -H "$auth" "$FLAME_URL/api/apps/$id"
    echo "Removed Flame tile: $TILE_NAME"
  else
    echo "No Flame tile named $TILE_NAME"
  fi
  ;;
*) echo "usage: $0 add|remove|activate" >&2; exit 2 ;;
esac
