#!/bin/bash

set -x

EXPECTED_ISSUER="issuer=CN=rootca-internal-custom"
ISSUER_MISMATCHES=""
ALL_MATCHED=1

function extract_host_port {
    local endpoint_url=$1
    local host_port

    # Extract the hostname and port, keeping the port if specified
    host_port=$(echo "$endpoint_url" | sed -E 's|^[^:/]+://([^:/]+(:[0-9]+)?).*|\1|')

    # If no port is specified, add :443
    if [[ ! "$host_port" =~ :[0-9]+$ ]]; then
        host_port="${host_port}:443"
    fi

    echo "$host_port"
}

function check_endpoint {
    local host_port=$1

    echo "Checking $host_port ..."
    if ! echo | openssl s_client -connect "$host_port" &> /dev/null; then
        return 1
    fi

    return 0
}

# Get keystone-internal and neutron-internal URLs
keystone_url=$(openstack endpoint list -c URL -f value | grep 'keystone-internal')
neutron_url=$(openstack endpoint list -c URL -f value | grep 'neutron-internal')

# Extract host and port for keystone-internal and neutron-internal
keystone_host_port=$(extract_host_port "$keystone_url")
neutron_host_port=$(extract_host_port "$neutron_url")

# Check connections to keystone-internal and neutron-internal
if ! check_endpoint "$keystone_host_port"; then
    echo "Failed to connect to Keystone internal endpoint."
    exit 1
fi

if ! check_endpoint "$neutron_host_port"; then
    echo "Failed to connect to Neutron internal endpoint."
    exit 1
fi

# Check the rest of the internal endpoints for the expected issuer
for url in $(openstack endpoint list -c URL -f value | grep 'svc'); do
    # Extract the hostname and port
    host_port=$(extract_host_port "$url")

    echo "Checking $host_port ..."
    ISSUER=$(openssl s_client -connect $host_port < /dev/null 2>/dev/null | openssl x509 -issuer -noout -in /dev/stdin)
    if [[ "$ISSUER" != "$EXPECTED_ISSUER" ]]; then
        ISSUER_MISMATCHES+="$host_port issued by $ISSUER, expected $EXPECTED_ISSUER\n"
        ALL_MATCHED=0
    fi
done

if [ "$ALL_MATCHED" -eq 1 ]; then
    echo "All internal certificates match the custom issuer $EXPECTED_ISSUER"
    exit 0
else
    echo -e "Mismatched issuers found:\n$ISSUER_MISMATCHES"
    exit 1
fi
