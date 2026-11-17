#!/usr/bin/env bash
# Adds, updates or removes one POC's tile on the Flame dashboard, matched by
# name. Called by terraform_data.flame_tile in pocs.tf; never prints the
# password or the session token.
#   flame-tile.sh add|remove
# Env: FLAME_URL, FLAME_PASSWORD, TILE_NAME, and for add: TILE_URL, TILE_DESCRIPTION
set -euo pipefail

token=$(jq -n --arg p "$FLAME_PASSWORD" '{password: $p, duration: "1h"}' |
  curl -sf -m 20 -H "Content-Type: application/json" --data @- "$FLAME_URL/api/auth" |
  jq -r '.data.token')
auth="Authorization-Flame: Bearer $token"

id=$(curl -sf -m 20 -H "$auth" "$FLAME_URL/api/apps" |
  jq -r --arg n "$TILE_NAME" '[.data[] | select(.name == $n)][0].id // empty')

case "$1" in
add)
  body=$(jq -n --arg n "$TILE_NAME" --arg u "$TILE_URL" --arg d "$TILE_DESCRIPTION" \
    '{name: $n, url: $u, description: $d, icon: "flask-outline", isPublic: 1}')
  if [ -n "$id" ]; then
    curl -sf -m 20 -o /dev/null -X PUT -H "$auth" -H "Content-Type: application/json" --data "$body" "$FLAME_URL/api/apps/$id"
    echo "Updated Flame tile: $TILE_NAME"
  else
    curl -sf -m 20 -o /dev/null -X POST -H "$auth" -H "Content-Type: application/json" --data "$body" "$FLAME_URL/api/apps"
    echo "Added Flame tile: $TILE_NAME"
  fi
  ;;
remove)
  if [ -n "$id" ]; then
    curl -sf -m 20 -o /dev/null -X DELETE -H "$auth" "$FLAME_URL/api/apps/$id"
    echo "Removed Flame tile: $TILE_NAME"
  else
    echo "No Flame tile named $TILE_NAME"
  fi
  ;;
*) echo "usage: $0 add|remove" >&2; exit 2 ;;
esac
