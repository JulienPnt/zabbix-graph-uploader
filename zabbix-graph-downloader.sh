#!/bin/bash

##########
# Logs
COLOR_RESET="\033[0m"
COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
_echo(){
  local msg_type=${1}
  shift
  local color=${1}
  shift
  local file=$(basename ${0})
  echo -e "${color}[$(date)][${file}] ${msg_type}: ${@}${COLOR_RESET}"
}

echo_dbg(){
  local msg_type="DBG"
  local color=${COLOR_RESET}
  _echo ${msg_type} ${color} ${@}
}

echo_warning(){
  local msg_type="WARNING"
  local color=${COLOR_YELLOW}
  _echo ${msg_type} ${color} ${@}
}

echo_err(){
  local msg_type="ERR"
  local color=${COLOR_RED}
  _echo ${msg_type} ${color} ${@}
}

##########
# Usage

USAGE="""
Usage: $(basename $0) <hostname> <start_date> <duration>

Downloads Zabbix monitoring graphs for a given host.

Arguments:
    hostname    - Hostname (e.g., ec2-preprod)
    start_date  - Start date in the format YYYY-MM-DD HH:MM:SS
    duration    - Duration in seconds

Required environment variables:
    ZABBIX_USER     - Zabbix username
    ZABBIX_PASSWORD - Zabbix password
    ZABBIX_URL      - Zabbix API URL (e.g., https://zabbix.example.com/api_jsonrpc.php)

Example:
    export ZABBIX_URL=https://zabbix.example.com/api_jsonrpc.php
    export ZABBIX_TOKEN=token
    export ZABBIX_USER=USERNAME
    export ZABBIX_PASSWORD=PASSWORD
    $(basename $0) ec2-preprod '2025-01-31 15:36:00' 3600
"""

usage(){
  echo -e "${USAGE}"
}



############
# Zabbix API
#
validate_url() {
    if [[ ! "$ZABBIX_URL" =~ ^https?:// ]]; then
      echo_err "URL must be http or https"
      return 1
    elif [[ ! "$ZABBIX_URL" =~ api_jsonrpc.php ]]; then
      echo_err "URL must target api_jsonrpc.php service"
      return 2
    fi
    return 0
}

check_curl_response() {
    local response=$1
    local curl_status=$2
    local action=${FUNCNAME[1]}
    
    echo_dbg "Response for $action:\n${response}"
    
    if [[ $curl_status -ne 0 ]]; then
        echo_err "Curl request failed on: $action"
        return 1
    elif echo_dbg "$response" | jq -e '.error' > /dev/null; then
        echo_err "API issue on $action: $(echo_dbg "$response" | jq -r '.error.message')"
        return 2
    fi
}

get_host_id() {
    local curl_status=0
    local request="{\"jsonrpc\": \"2.0\",\"method\": \"host.get\",\"params\": {\"filter\": {\"host\": \"${hostname}\"}, \"output\": [\"hostid\",\"host\"],\"selectInterfaces\": [\"interfaceid\",\"ip\"]},\"id\": \"2\"}"
    local response=$(curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${ZABBIX_TOKEN}" \
      -d "${request}" \
      ${ZABBIX_URL}; curl_status=${?})
    check_curl_response "${response}" "${curl_status}"
    if [[ ${?} -ne 0 ]]; then
      return 1
    fi
    
    host_id=$(echo "$response" | jq -r '.result[0].hostid')
    if [[ -z "$host_id" ]] || [[ "$host_id" == "null" ]]; then
        echo_err "Host not found"
        return 2
    fi
}

get_graphs() {
    local host_id=$1
    local curl_status=0
    local request="{\"jsonrpc\": \"2.0\",\"method\": \"graph.get\",\"params\": {\"hostids\": [\"${host_id}\"],\"output\": [\"graphid\",\"name\"]},\"id\": \"3\"}"
    local response=$(curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${ZABBIX_TOKEN}" \
        -d "${request}" \
        $ZABBIX_URL; curl_status=${?})
    
    check_curl_response "${response}" "${curl_status}"
    if [[ ${?} -ne 0 ]]; then
      return 1
    elif ! echo "$response" | jq -e '.result | length > 0' > /dev/null; then
        echo_err "No graph retrieved"
        exit 0
    fi

    while IFS= read -r line; do
        local id=$(echo "$line" | cut -d' ' -f1)
        local name=$(echo "$line" | cut -d' ' -f2-)
        graphs_list[$id]="$name"
    done < <(echo "$response" | jq -r '.result[] | "\(.graphid) \(.name)"')
    
}

get_auth_cookie() {
    local login_url="${ZABBIX_URL%/api_jsonrpc.php}/index.php"
    curl -s -c "${cookie_file}" -d "name=${ZABBIX_USER}&password=${ZABBIX_PASSWORD}&autologin=1&enter=Sign in" \
         -H 'Content-Type: application/x-www-form-urlencoded' \
         "${login_url}" > /dev/null
    cookie=$(cat "${cookie_file}" | grep zbx_session | awk '{print $7}')
    if [[ -z "$cookie" ]]; then
        echo_err "❌ Failed to retrieve session cookie!"
        return 1
    fi
    return 0
}

cast_date_for_zabbix_url(){
  local my_date=${1}
  echo ${my_date} | sed 's/ /%20/g' | sed 's/:/%3A/g'
}

download_graph() {
    local graph_id=${1}
    local graph_title=${2}
    local from=${3}
    local to=${4}
    local dest_dir=${5}
    local width=${6:-1200}
    local height=${7:-600}

    local cookie
    local cookie_file="/tmp/zabbix_cookie_$$"
    get_auth_cookie || return 1
      
    local graph_url="${ZABBIX_URL%/api_jsonrpc.php}/chart2.php"
    local params=(
        "graphid=${graph_id}"
        "from=$(cast_date_for_zabbix_url "${from}")"
        "to=$(cast_date_for_zabbix_url "${to}")"
        "width=${width}"
        "height=${height}"
        "profileIdx=web.graphs.filter"
    )
    local url_params=$(IFS="&"; echo "${params[*]}")
    local output_file="${graph_title}.png"

    echo_dbg "Downloading graph: ${graph_url}?${url_params}..."
    curl -b "${cookie_file}" -o "${dest_dir}/${output_file}" "${graph_url}?${url_params}"
    # Curl status is always 1 for unsupported protocol but it is wortking
    if [[ $? -eq 0 || $? -eq 1 ]] && [[ -f "${dest_dir}/${output_file}" && -s "${dest_dir}/${output_file}" ]]; then
      echo_dbg "✅ Graph successfully downloaded: ${output_file}"
    else
      echo_err "❌ Failed to download graph: ${output_file}, curl error code: $?"
      rm -f "${output_file}"
    fi

    rm -f "${cookie_file}"
}

main() {
  if [[ "${@}" =~ *"--help"* ]] || [[ "${@}}" =~ *"-h"* ]]; then
    usage
    return 0
  elif [[ $# -ne 3 ]]; then
    echo_err "Expected 3 arguments: hostname, start_date, and end_date"
    return 1
  elif [[ -z "${ZABBIX_TOKEN}" ]] || 
    [[ -z "${ZABBIX_URL}" ]] || 
    [[ -z "${ZABBIX_USER}" ]] ||
    [[ -z "${ZABBIX_PASSWORD}" ]]; then
    echo_err "Environment variable issue"
    return 2
  fi
  validate_url || return 3

  local hostname="${1}"
  local from="${2}"
  local to="${3}"

  echo_dbg "STEP 1: Get host ID"
  local host_id=""
  get_host_id
  if [[ ${?} -ne 0 ]]; then
    echo_err "Failed to get host ID"
    return 2
  fi
  echo_dbg "Host ID: ${host_id}"

  echo_dbg "STEP 2: Get graph list"
  local declare -A graphs_list
  get_graphs "$host_id"
  if [[ ${?} -ne 0 ]]; then
    echo_err "Failed to get graph list"
    return 2
  fi

  echo_dbg "Graph list: ${graphs_list}"
  echo_dbg "Graphs dictionary content:"
  local dest_dir="${HOME}/Images/${hostname}_${from// /_}_${to// /_}"
  if [[ -d ${dest_dir} ]]; then
    rm -rf ${dest_dir}
  fi
  mkdir -p ${dest_dir}
  echo_dbg "${dest_dir}"
  for id in "${!graphs_list[@]}"; do
    echo_dbg "\tGraph ID: $id -> Name: ${graphs_list[$id]}"
    download_graph "${id}" "${graphs_list[$id]}" "${from}" "${to}" "${dest_dir}"
  done
}

main "${@}" || usage
exit ${?}
