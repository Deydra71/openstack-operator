#!/bin/bash

NAMESPACE="${NAMESPACE:-$1}"

declare -a services=(
    # Format: ("<secret-name>" "<label-selector>" "<container-name>" "<volume-mount-path>")
    "cert-ceilometer-internal-svc service=ceilometer proxy-httpd /etc/pki/tls/certs/tls.crt"
    "cert-galera-openstack-cell1-svc service=openstack-cell1-galera galera /etc/pki/tls/certs/galera.crt"
    "cert-galera-openstack-svc service=openstack-galera galera /etc/pki/tls/certs/galera.crt"
    "cert-memcached-svc service=memcached memcached /etc/pki/tls/certs/memcached.crt"
    "cert-neutron-ovndbs service=neutron neutron-api /etc/pki/tls/certs/ovndb.crt"
    "cert-nova-novncproxy-cell1-vencrypt service=nova-novncproxy nova-cell1-novncproxy-novncproxy /etc/pki/tls/certs/vencrypt.crt"
    "cert-ovndbcluster-nb-ovndbs service=ovsdbserver-nb ovsdbserver-nb /etc/pki/tls/certs/ovndb.crt"
    "cert-ovndbcluster-sb-ovndbs service=ovsdbserver-sb ovsdbserver-sb /etc/pki/tls/certs/ovndb.crt"
    "cert-ovnnorthd-ovndbs service=ovn-northd ovn-northd /etc/pki/tls/certs/ovndb.crt"
    "cert-rabbitmq-cell1-svc app.kubernetes.io/name=rabbitmq-cell1 rabbitmq /etc/rabbitmq-tls/tls.crt"
    "cert-rabbitmq-svc app.kubernetes.io/name=rabbitmq rabbitmq /etc/rabbitmq-tls/tls.crt"
)

for service in "${services[@]}"; do
    IFS=" " read -r secret label_selector container volume_mount <<< "$service"

    # Retrieve the pod name dynamically using the label selector and the provided namespace
    pod=$(oc get pods -n "$NAMESPACE" -l "$label_selector" -o jsonpath="{.items[0].metadata.name}" 2>&1)

    if [[ "$?" -ne 0 || -z "$pod" ]]; then
        echo "Error retrieving pod name for secret $secret with label selector $label_selector in namespace $NAMESPACE."
        echo "Error message: $pod"
        continue
    fi

    # Fetch the certificate from the pod and compare with the secret
    pod_cert=$(oc exec -n "$NAMESPACE" "$pod" --container="$container" -- cat "$volume_mount" 2>&1)
    if [[ "$?" -ne 0 ]]; then
        echo "Error reading certificate from pod $pod, container $container, path $volume_mount."
        echo "Error message: $pod_cert"
        continue
    fi

    secret_cert=$(oc get secret -n "$NAMESPACE" "$secret" -o jsonpath="{.data['tls\.crt']}" | base64 --decode 2>&1)
    if [[ "$?" -ne 0 ]]; then
        echo "Error retrieving secret $secret in namespace $NAMESPACE."
        echo "Error message: $secret_cert"
        continue
    fi

    if [[ "$pod_cert" == "$secret_cert" ]]; then
        echo "Certificates for $pod and $secret match."
    else
        echo "Certificates for $pod and $secret DO NOT match."
    fi
done
