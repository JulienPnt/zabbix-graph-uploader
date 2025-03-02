# 📊 Zabbix Graph Downloader

## 📝 Description

This Bash script allows you to download monitoring graphs from a Zabbix server. It retrieves **all graphs available for a given host**, from a **specified date**, and for a **defined duration**.

### 🔥 Features

- ✅ URL validation for Zabbix API
- ✅ Authentication with session cookies
- ✅ Retrieval of host ID
- ✅ Fetching available graphs
- ✅ Downloading graphs to a local directory

## 📌 Requirements

Before running this script, ensure you have the following prerequisites:
1. curl installed
2. jq installed (to parse JSON responses from the Zabbix API)
3. A Zabbix user account with access to the graphs
4. A Zabbix admin token
5. A valid Zabbix API URL

## 🚀 Usage

### 🔹 Arguments
- Usage: ./script.sh <hostname> <start_date> <duration>
- hostname : Hostname (e.g., ec2-preprod)
- start_date : Start date in the format YYYY-MM-DD HH:MM:SS
- duration : Duration in seconds

### 🔑 Required Environment Variables

Before running the script, set the following environment variables:
```
export ZABBIX_URL=https://zabbix.example.com/api_jsonrpc.php
export ZABBIX_TOKEN=token
export ZABBIX_USER=USERNAME
export ZABBIX_PASSWORD=PASSWORD
```

### 📌 Example Execution

`./zabbix-graph-downloader.sh ec2-preprod '2025-01-31 15:36:00' 3600`

The downloaded graphs will be stored in `~/Images/<hostname>_<start_date>_<end_date>`.

## 📜 Script Workflow

1. Validate Zabbix API URL
2. Retrieve host ID
3. Fetch list of available graphs
4. Authenticate and obtain session cookie
5. Download graphs

## 🛠 Dependencies
- curl
- jq
