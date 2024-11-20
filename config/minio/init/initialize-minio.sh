#!/bin/bash

set -e  # Exit on any error

echo "Starting MinIO initialization..."

# Function to wait for MinIO to be ready
wait_for_minio() {
    echo "Waiting for MinIO to be ready..."
    until /usr/bin/mc config host add --api s3v4 local http://minio-proxy:9000 minio_root supersecret &>/dev/null; do
        echo "MinIO not ready yet, retrying in 5 seconds..."
        sleep 5
    done
    echo "MinIO is ready!"
}

# Function to setup aliases
setup_aliases() {
    echo "Setting up MinIO aliases..."
    # Remove any existing aliases
    /usr/bin/mc config host rm local --force &>/dev/null || true
    /usr/bin/mc alias rm myminio --force &>/dev/null || true

    # Add new aliases
    /usr/bin/mc config host add --api s3v4 local http://minio-proxy:9000 minio_root supersecret
    /usr/bin/mc alias set myminio http://minio-proxy:9000 minio_root supersecret
}

# Function to create buckets
create_buckets() {
    echo "Creating required buckets..."
    /usr/bin/mc mb --ignore-existing local/loki-data/
    /usr/bin/mc mb --ignore-existing local/mimir/
    /usr/bin/mc mb --ignore-existing local/tempo/
}

# Function to configure LDAP
configure_ldap() {
    echo "Configuring LDAP..."
    /usr/bin/mc admin config set myminio identity_ldap configuration_file=/run/secrets/ldap.json

    echo "Restarting MinIO to apply LDAP configuration..."
    /usr/bin/mc admin service restart myminio

    # Wait for restart to complete
    sleep 10
}

# Function to setup policies
setup_policies() {
    echo "Setting up policies..."
    /usr/bin/mc admin policy create myminio admin-policy /run/secrets/policies/admin-policy.json
    /usr/bin/mc admin policy create myminio readonly-policy /run/secrets/policies/readonly-policy.json
}

# Function to verify configuration
verify_config() {
    echo "Verifying configurations..."
    echo "LDAP Configuration:"
    /usr/bin/mc admin config get myminio identity_ldap
    echo "Policy List:"
    /usr/bin/mc admin policy list myminio
}

# Main execution
main() {
    wait_for_minio
    setup_aliases
    create_buckets
    configure_ldap
    setup_policies
    verify_config
    echo "MinIO initialization completed successfully!"
}

main