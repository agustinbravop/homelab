#!/usr/bin/env bash

set -euo pipefail

ZONE_NAME="agusbravo.dev"

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is not installed."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is not installed."
  exit 1
fi

if ! command -v gum >/dev/null 2>&1; then
  echo "Error: gum is not installed."
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "Error: terraform is not installed."
  exit 1
fi

gum style \
  --border normal \
  --margin "1 2" \
  --padding "1 2" \
  --border-foreground 212 "This script overwrites Cloudflare A records under ${ZONE_NAME}." \
  "Every A record in ${ZONE_NAME} and its subdomains will be pointed at the Terraform public IPv4 output."

gum style --bold "Please provide your Cloudflare API token."
CLOUDFLARE_API_TOKEN=$(gum input --password --placeholder "Paste your Cloudflare API token")

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  gum style --bold --foreground 212 "No Cloudflare API token provided. Exiting."
  exit 1
fi

cf_api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local response

  if [ -n "$data" ]; then
    response=$(curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "$data")
  else
    response=$(curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      -H "Content-Type: application/json")
  fi

  if ! jq -e '.success == true' >/dev/null 2>&1 <<< "$response"; then
    echo "Cloudflare API error for ${method} ${path}:" >&2
    jq -r '.errors[]?.message // .messages[]?.message // "Unknown error"' <<< "$response" >&2
    exit 1
  fi

  printf '%s\n' "$response"
}

filter_zone_a_records() {
  jq -cr --arg zone "$ZONE_NAME" '
    .result[]
    | select(.type == "A")
    | select(.name == $zone or (.name | endswith("." + $zone)))
    | {id: .id, name: .name, proxied: .proxied, ttl: .ttl, content: .content}
  '
}

print_records_table() {
  local rows="$1"

  printf '%-35s %-15s %-7s %-5s\n' "NAME" "IPV4" "PROXY" "TTL"
  printf '%-35s %-15s %-7s %-5s\n' "----" "----" "-----" "---"

  if [ -z "$rows" ]; then
    echo "No A records found under ${ZONE_NAME}."
    return
  fi

  while IFS= read -r record_row; do
    [ -n "$record_row" ] || continue
    printf '%-35s %-15s %-7s %-5s\n' \
      "$(jq -r '.name' <<< "$record_row")" \
      "$(jq -r '.content' <<< "$record_row")" \
      "$(jq -r '.proxied' <<< "$record_row")" \
      "$(jq -r '.ttl' <<< "$record_row")"
  done <<< "$rows"
}

ZONE_ID=$(cf_api GET "/zones?name=${ZONE_NAME}" | jq -r '.result[0].id // empty')

if [ -z "$ZONE_ID" ]; then
  echo "Error: could not find Cloudflare zone '${ZONE_NAME}'."
  exit 1
fi

records_json=$(cf_api GET "/zones/${ZONE_ID}/dns_records?per_page=500")
record_rows=$(filter_zone_a_records <<< "$records_json")

echo "Current A records:"
print_records_table "$record_rows"

DEFAULT_IPV4=$(terraform output -raw ipv4_address)

gum style --bold "Please confirm the target IPv4 address."
echo "Default IPv4 comes from: terraform output -raw ipv4_address"
TARGET_IPV4=$(gum input --value "$DEFAULT_IPV4" --placeholder "Enter the target IPv4 address")

if [[ ! "$TARGET_IPV4" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Error: '$TARGET_IPV4' does not look like an IPv4 address."
  exit 1
fi

echo
echo "Updating Cloudflare A records in zone ${ZONE_NAME} to ${TARGET_IPV4}"

updated_count=0

if [ -n "$record_rows" ]; then
  while IFS= read -r record_row; do
    [ -n "$record_row" ] || continue
    record_id=$(jq -r '.id' <<< "$record_row")
    hostname=$(jq -r '.name' <<< "$record_row")
    proxied=$(jq -r '.proxied' <<< "$record_row")
    ttl=$(jq -r '.ttl' <<< "$record_row")

    payload=$(jq -n \
      --arg type "A" \
      --arg name "$hostname" \
      --arg content "$TARGET_IPV4" \
      --argjson proxied "$proxied" \
      --argjson ttl "$ttl" \
      '{type: $type, name: $name, content: $content, proxied: $proxied, ttl: $ttl}')

    echo "Updating ${hostname}"
    cf_api PUT "/zones/${ZONE_ID}/dns_records/${record_id}" "$payload" >/dev/null
    updated_count=$((updated_count + 1))
  done <<< "$record_rows"
fi

if [ "$updated_count" -eq 0 ]; then
  echo "No A records found under ${ZONE_NAME}."
  exit 0
fi

echo
echo "Updated ${updated_count} A record(s) under ${ZONE_NAME} to ${TARGET_IPV4}:"
final_records_json=$(cf_api GET "/zones/${ZONE_ID}/dns_records?per_page=500")
final_record_rows=$(filter_zone_a_records <<< "$final_records_json")
print_records_table "$final_record_rows"
