#!/bin/sh
# Wait for MinIO to be ready
until /usr/bin/mc config host add --api s3v4 local http://minio-proxy:9000 minio_root supersecret; do
    echo 'Waiting for MinIO to be ready...'
    sleep 5
done

# Remove any existing alias to avoid conflicts
/usr/bin/mc config host rm local --force;
/usr/bin/mc alias rm myminio --force;

# Add the MinIO host
/usr/bin/mc config host add --api s3v4 local http://minio-proxy:9000 minio_root supersecret;
/usr/bin/mc alias set myminio http://minio-proxy:9000 minio_root supersecret;

# Create required buckets
/usr/bin/mc mb --ignore-existing local/loki-data/;
/usr/bin/mc mb --ignore-existing local/mimir/;
/usr/bin/mc mb --ignore-existing local/tempo/;

# Set LDAP configuration
# We need to ensure the JSON is properly read and set
echo 'Setting LDAP configuration...'
/usr/bin/mc admin config set myminio identity_ldap configuration_file=/run/secrets/ldap-identity.json;
/usr/bin/mc admin service restart myminio;

# Wait for MinIO to restart
sleep 10

# Set policies
echo 'Setting policies...'
/usr/bin/mc admin policy create myminio admin-policy /run/secrets/policies/admin-policy.json;
/usr/bin/mc admin policy create myminio readonly-policy /run/secrets/policies/readonly-policy.json;

# Verify configurations
echo 'Verifying configurations...'
/usr/bin/mc admin config get myminio identity_ldap;
/usr/bin/mc admin policy list myminio;
