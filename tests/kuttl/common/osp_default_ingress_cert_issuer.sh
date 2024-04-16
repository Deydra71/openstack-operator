#!/bin/bash

set -x

EXPECTED_ISSUER="rootca-public"
ISSUER_MISMATCHES=""
ALL_MATCHED=1

function extract_host_port {
    local endpoint_url=$1
    local host_port

    # Extract the hostname and port
    host_port=$(echo "$endpoint_url" | sed -E 's|^[^:/]+://([^:/]+).*|\1|')

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

keystone_url=$(openstack endpoint list -c URL -f value | grep 'keystone-public')
neutron_url=$(openstack endpoint list -c URL -f value | grep 'neutron-public')

keystone_host_port=$(extract_host_port "$keystone_url")
neutron_host_port=$(extract_host_port "$neutron_url")

# Check connections to keystone-public and neutron-public
if ! check_endpoint "$keystone_host_port"; then
    echo "Failed to connect to Keystone public endpoint."
    exit 1
fi

if ! check_endpoint "$neutron_host_port"; then
    echo "Failed to connect to Neutron public endpoint."
    exit 1
fi

# Check endpoints for the expected issuer
for url in $(openstack endpoint list -c URL -f value | grep 'public'); do
    host_port=$(extract_host_port "$url")

    echo "Checking $host_port ..."
    ISSUER=$(echo | openssl s_client -connect "$host_port" 2>/dev/null | openssl x509 -noout -issuer | sed -n 's/^.*CN=\([^,]*\).*$/\1/p')

    if [[ "$ISSUER" != "$EXPECTED_ISSUER" ]]; then
        ISSUER_MISMATCHES+="$host_port issued by $ISSUER, expected $EXPECTED_ISSUER\n"
        ALL_MATCHED=0
    fi
done

if [ "$ALL_MATCHED" -eq 1 ]; then
    echo "All public certificates match the custom issuer $EXPECTED_ISSUER"
    exit 0
else
    echo -e "Mismatched issuers found:\n$ISSUER_MISMATCHES"
    exit 1
fi
