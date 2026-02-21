#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") -s SERVER -u USER -p PASS <command> [args]

Commands:
  install <login> <password> <email>                 # Create initial admin user (no auth needed)
  listserv                                           # List server certificates
  listclient                                         # List client certificates
  addserv <domains> <validity_days>                  # Add server certificate
  addclient <server_domain> <client> <validity_days> # Add client certificate
  listuser                                           # List users
  adduser <login> <password> <email> <role>          # Add user (role numeric)
  revokecert <id>                                    # Revoke certificate
  deleteuser <id>                                    # Delete user
  edituser <id> <login> <password> <role>            # Edit user
  certdetail <id>                                    # Cert detail
  rootdetail                                         # Root cert detail
  help                                               # Show this help

Options:
  -s SERVER   Base URL of the API (default: http://127.0.0.1:4567)
  -u USER     Username for authentication
  -p PASS     Password for authentication
EOF
}

# Parse global options
SERVER="http://127.0.0.1:4567"
USERNAME=""
PASSWORD=""

while getopts ":s:u:p:h" opt; do
    case $opt in
    s) SERVER="$OPTARG" ;;
    u) USERNAME="$OPTARG" ;;
    p) PASSWORD="$OPTARG" ;;
    h)
        usage
        exit 0
        ;;
    *)
        echo "Unknown option -$OPTARG"
        usage
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

COMMAND="$1"
shift

# Helper: get token
get_token() {
    local login="$1"
    local pass="$2"
    local resp
    resp=$(curl -s -X POST "$SERVER/api/v1/login" \
        -H "Content-Type: application/json" \
        -d "{\"login\":\"$login\",\"password\":\"$pass\"}")
    local err
    err=$(echo "$resp" | jq -r '.error')
    if [[ "$err" != "null" && -n "$err" ]]; then
        echo "Login error: $err" >&2
        exit 1
    fi
    echo "$resp" | jq -r '.content.token'
}

# Helper: perform request
do_req() {
    local method="$1"
    local url="$2"
    local data="$3"
    local token="$4"
    local json_data
    if [[ -n "$token" ]]; then
        json_data=$(echo "$data" | jq --arg token "$token" '. + {token: $token}')
    else
        json_data="$data"
    fi
    local resp
    resp=$(curl -s -X "$method" "$url" \
        -H "Content-Type: application/json" \
        -d "$json_data")
    local err
    err=$(echo "$resp" | jq -r '.error')
    if [[ "$err" != "null" && -n "$err" ]]; then
        echo "Error: $err" >&2
        exit 1
    fi
    echo "$resp" | jq -r '.content'
}

# Commands requiring authentication
auth_required_commands=("listserv" "listclient" "addserv" "addclient" "listuser" "adduser" "revokecert" "deleteuser" "edituser" "certdetail" "rootdetail")
needs_auth=false
for cmd in "${auth_required_commands[@]}"; do
    if [[ "$COMMAND" == "$cmd" ]]; then
        needs_auth=true
        break
    fi
done

if $needs_auth; then
    if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
        echo "Username and password required for command '$COMMAND'" >&2
        exit 1
    fi
    TOKEN=$(get_token "$USERNAME" "$PASSWORD")
    if [[ -z "$TOKEN" ]]; then
        echo "Failed to obtain token" >&2
        exit 1
    fi
fi

case "$COMMAND" in
install)
    if [[ $# -ne 3 ]]; then
        echo "install requires <login> <password> <email>" >&2
        exit 1
    fi
    login="$1"
    pw="$2"
    email="$3"
    do_req POST "$SERVER/api/v1/adduser" "{\"login\":\"$login\",\"password\":\"$pw\",\"email\":\"$email\",\"role\":1}" ""
    ;;
listserv)
    do_req POST "$SERVER/api/v1/servers" "{}" "$TOKEN"
    ;;
listclient)
    do_req POST "$SERVER/api/v1/clients" "{}" "$TOKEN"
    ;;
addserv)
    if [[ $# -ne 2 ]]; then
        echo "addserv requires <domains> <validity_days>" >&2
        exit 1
    fi
    domains="$1"
    days="$2"
    do_req POST "$SERVER/api/v1/addserver" "{\"domains\":\"$domains\",\"validity_days\":$days}" "$TOKEN"
    ;;
addclient)
    if [[ $# -ne 3 ]]; then
        echo "addclient requires <server_domain> <client> <validity_days>" >&2
        exit 1
    fi
    server_domain="$1"
    client="$2"
    validity_days="$3"
    do_req POST "$SERVER/api/v1/addclient" "{\"server_domain\":\"$server_domain\",\"client\":\"$client\",\"validity_days\":\"$validity_days\"}" "$TOKEN"
    ;;
listuser)
    do_req POST "$SERVER/api/v1/ulist" "{}" "$TOKEN"
    ;;
adduser)
    if [[ $# -ne 4 ]]; then
        echo "adduser requires <login> <password> <email> <role:user|creator|admin>" >&2
        exit 1
    fi
    login="$1"
    pw="$2"
    email="$3"
    role="$4"
    case "$role" in
    user) role=0 ;;
    creator) role=1 ;;
    admin) role=2 ;;
    *) role=0 ;;
    esac
    do_req POST "$SERVER/api/v1/adduser" "{\"login\":\"$login\",\"password\":\"$pw\",\"email\":\"$email\",\"role\":$role}" "$TOKEN"
    ;;
revokecert)
    if [[ $# -ne 1 ]]; then
        echo "revokecert requires <id>" >&2
        exit 1
    fi
    id="$1"
    do_req POST "$SERVER/api/v1/revoke/$id" "{}" "$TOKEN"
    ;;
deleteuser)
    if [[ $# -ne 1 ]]; then
        echo "deleteuser requires <id>" >&2
        exit 1
    fi
    id="$1"
    do_req POST "$SERVER/api/v1/deleteuser/$id" "{}" "$TOKEN"
    ;;
edituser)
    if [[ $# -ne 5 ]]; then
        echo "edituser requires <id> <login> <password> <email> <role: user|creator|admin>" >&2
        exit 1
    fi
    id="$1"
    login="$2"
    pw="$3"
    role="$5"
    email="$4"
    case "$role" in
    user) role=0 ;;
    creator) role=1 ;;
    admin) role=2 ;;
    *) role=0 ;;
    esac
    do_req POST "$SERVER/api/v1/edituser/$id" "{\"login\":\"$login\",\"password\":\"$pw\",\"role\":$role,\"email\":\"$email\"}" "$TOKEN"
    ;;
certdetail)
    if [[ $# -ne 1 ]]; then
        echo "certdetail requires <id>" >&2
        exit 1
    fi
    id="$1"
    do_req POST "$SERVER/api/v1/certinfo/$id" "{}" "$TOKEN"
    ;;
rootdetail)
    do_req POST "$SERVER/api/v1/root" "{}" "$TOKEN"
    ;;
help | --help | -h)
    usage
    ;;
*)
    echo "Unknown command: $COMMAND" >&2
    usage
    exit 1
    ;;
esac
