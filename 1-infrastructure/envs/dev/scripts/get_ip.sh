#!/bin/sh
if ip=$(curl -s ifconfig.me); then
  echo "{\"ip\":\"$ip\"}"
else
  echo "Error fetching IP address" >&2
  exit 1
fi