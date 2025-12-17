#!/bin/bash
# Generate Ansible inventory from Terraform output

TERRAFORM_DIR="$HOME/Projects/platform/kafka-platform/1-infrastructure/envs/dev"
INVENTORY_FILE="$HOME/Projects/platform/kafka-platform/2-configuration/inventory/hosts.yml"

cd "$TERRAFORM_DIR"

# Get ansible_inventory output and convert to YAML
terraform output -raw ansible_inventory | python3 -c "
import sys, json, yaml

data = json.load(sys.stdin)

# Fix host names that match group names
if 'kafka_connect' in data and 'hosts' in data['kafka_connect']:
    if 'kafka_connect' in data['kafka_connect']['hosts']:
        data['kafka_connect']['hosts']['connect-1'] = data['kafka_connect']['hosts'].pop('kafka_connect')

if 'platform' in data and 'hosts' in data['platform']:
    if 'platform' in data['platform']['hosts']:
        data['platform']['hosts']['platform-1'] = data['platform']['hosts'].pop('platform')

# Add controller_id offset (9990) for KRaft
for host, props in data.get('kafka_controller', {}).get('hosts', {}).items():
    if 'controller_id' in props:
        props['controller_id'] = props['controller_id'] + 9990

inventory = {'all': {'children': data}}
print(yaml.dump(inventory, default_flow_style=False, sort_keys=False))
" > "$INVENTORY_FILE"

echo "Inventory generated at: $INVENTORY_FILE"
cat "$INVENTORY_FILE"
