#!/bin/sh
set -eu

server_info_path="${SERVER_INFO_PATH:-/usr/share/nginx/html/server-info.json}"

cat > "$server_info_path" <<EOF
{
  "web_server": "${WEB_SERVER_NAME:-unknown}",
  "generated_at": "$(date -Iseconds)"
}
EOF
