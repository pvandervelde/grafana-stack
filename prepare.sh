#!/bin/bash

# List of volumes to check and create if necessary
volumes=(
    "mimir1-data"
    "mimir2-data"
    "mimir3-data"
    "minio-data1-1"
    "minio-data1-2"
    "minio-data2-1"
    "minio-data2-2"
    "minio-data3-1"
    "minio-data3-2"
    "minio-data4-1"
    "minio-data4-2"
)

# List of subdomains
subdomains=(
    "grafana"
    "ingress-grafana"
    "logs"
    "s3-grafana"
    "prometheus"
    "traces"
)

# AD CS server details
AD_CS_SERVER_IP="GGLVTEST-CA.gallagher.local" # GGLVTEST-CA
AD_CS_SERVER="GGLVTEST-CA" # Adjust this to match your AD CS server name
AD_CS_PORT="443"
AD_CS_TEMPLATE="WebServer" # Adjust this to match your AD CS template name

# Certificate storage locations
CERT_DIR="./config/traefik/ingress/certs"
CHAIN_CERT_FILE="/usr/local/share/ca-certificates/ad-ca-chain.crt"

# LDAP details
LDAP_HOST="gglvdc4.gallagher.local"
LDAP_PORT="389"
LDAP_BIND_DN="cn=servicegrafana,ou=services,ou=ggl,dc=gallagher,dc=local"
LDAP_BIND_PASSWORD="not-the-actual-password"
LDAP_SEARCH_BASE="dc=gallagher,dc=local"
LDAP_SEARCH_FILTER="(sAMAccountName=%s)"
LDAP_GROUP_SEARCH_BASE="ou=NZ Groups,ou=GGLNZ,dc=gallagher,dc=local"
LDAP_GROUP_SEARCH_FILTER="(&(objectClass=groupOfNames)(member=%s))"
LDAP_ADMIN_GROUP="cn=GrafanaAdmins,ou=NZ Groups,ou=GGLNZ,dc=gallagher,dc=local"

# Config file locations
TRAEFIK_CONFIG="./config/traefik/ingress/configs/tls.yml"
GRAFANA_LDAP_FILE="config/grafana/config/ldap.toml"

MINIO_LDAP_FILE="config/minio/ldap.json"

create_env_file() {
    local base_domain=$1
    local local_network_dns_ip=$2
    local router_ip=$3

    # Validate IP addresses using regex
    local ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ ! $local_network_dns_ip =~ $ip_regex ]]; then
        echo "Error: Invalid DNS IP address format"
        return 1
    fi

    if [[ ! $router_ip =~ $ip_regex ]]; then
        echo "Error: Invalid router IP address format"
        return 1
    fi

    # Create the .env file
    cat > ".env" <<EOF
LOCAL_NETWORK_DNS_IP=$local_network_dns_ip
ROUTER_IP=$router_ip
INGRESS_DOMAIN=$base_domain
EOF

    echo ".env file created"
}

create_grafana_ldap_config() {
    # Generate LDAP configuration file
    cat > "$GRAFANA_LDAP_FILE" << EOF
# Configuration file for Grafana LDAP integration

# Set to true to log user information returned from LDAP
# verbose_logging = false


[[servers]]
# Ldap server host (specify multiple hosts space separated)
host = "$LDAP_HOST"

# Default port is 389 or 636 if use_ssl = true
port = $LDAP_PORT

# Set to true if ldap server supports TLS
use_ssl = false

# Set to true if connect ldap server with STARTTLS pattern (create connection in insecure, then upgrade to secure connection with TLS)
start_tls = false

# set to true if you want to skip ssl cert validation
ssl_skip_verify = false

# set to the path to your root CA certificate or leave unset to use system defaults
# root_ca_cert = "/path/to/certificate.crt"

# Search user bind dn
bind_dn = "$LDAP_BIND_DN"

# Search user bind password
# If the password contains # or ; you have to wrap it with triple quotes. Ex """#password;"""
bind_password = "$LDAP_BIND_PASSWORD"

# User search filter, for example "(cn=%s)" or "(sAMAccountName=%s)" or "(uid=%s)"
search_filter = "$LDAP_SEARCH_FILTER"

# An array of base dns to search through
search_base_dns = ["$LDAP_SEARCH_BASE"]

## Group search filter, to retrieve the groups of which the user is a member (only set if memberOf attribute is not available)
group_search_filter = "(member:1.2.840.113556.1.4.1941:=%s)"
group_search_filter_user_attribute = "distinguishedName"

## An array of the base DNs to search through for groups. Typically uses ou=groups
group_search_base_dns = ["$LDAP_SEARCH_BASE"]

# Specify names of the ldap attributes your ldap uses
[servers.attributes]
name = "givenName"
surname = "sn"
username = "sAMAccountName"
member_of = "distinguishedName"
email = "mail"

# Map ldap groups to grafana org roles
[[servers.group_mappings]]
group_dn = "$LDAP_ADMIN_GROUP"
org_role = "Admin"
grafana_admin = true


[[servers.group_mappings]]
group_dn = "*"
org_role = "Viewer"
EOF

    echo "Grafana LDAP configuration file has been generated at: $GRAFANA_LDAP_FILE"
}

create_minio_ldap_config() {
    # Generate LDAP configuration file
    # Generate MinIO LDAP configuration file
    cat > "$MINIO_LDAP_FILE" << EOF
{
    "version": "1",
    "accessKey": "",
    "secretKey": "",
    "user": "on",
    "server": {
        "address": "$LDAP_HOST:$LDAP_PORT",
        "starttls": false,
        "insecure": true
    },
    "lookup_bind": {
        "dn": "$LDAP_BIND_DN",
        "password": "$LDAP_BIND_PASSWORD"
    },
    "user_dn_search": {
        "base_dn": "$LDAP_SEARCH_BASE",
        "filter": "$LDAP_SEARCH_FILTER"
    },
    "group_search": {
        "base_dn": "$LDAP_GROUP_SEARCH_BASE",
        "filter": "$LDAP_GROUP_SEARCH_FILTER"
    },
    "group_name_attribute": "$GROUP_NAME_ATTRIBUTE"
}
EOF

    echo "Minio LDAP configuration file has been generated at: $MINIO_LDAP_FILE"
}

create_traefik_config() {
    local base_domain=$1

    echo "Creating Traefik dynamic configuration file"

    # Start the YAML file
    cat > "$TRAEFIK_CONFIG" <<EOF
tls:
  certificates:
EOF

    # Add each subdomain to the configuration
    for subdomain in "${subdomains[@]}"; do
        cat >> "$TRAEFIK_CONFIG" <<EOF
    - certFile: "/etc/certs/${subdomain}.${base_domain}.crt"
      keyFile: "/etc/certs/${subdomain}.${base_domain}.key"
EOF
    done

    echo "Traefik dynamic configuration file created at $TRAEFIK_CONFIG"
}

# Function to generate CSR with SANs and get it signed by AD CS
generate_and_sign_certificate() {
    local base_domain=$1

    # Loop through each subdomain
    for subdomain in "${subdomains[@]}"; do
        # Construct the full domain
        full_domain="${subdomain}.${base_domain}"

        echo "Generating CSR for $full_domain"

        # Generate a private key
        openssl genrsa -out "$CERT_DIR/$full_domain.key" 2048

        # Create a configuration file for the CSR
        cat > "$CERT_DIR/$full_domain.cnf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
C=US
ST=State
L=City
O=Organization
OU=Organizational Unit
CN=$full_domain

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $full_domain
EOF

        # Generate the CSR with the config file
        openssl req -new -key "$CERT_DIR/$full_domain.key" -out "$CERT_DIR/$full_domain.csr" -config "$CERT_DIR/$full_domain.cnf"

        echo "CSR generated for $full_domain"
        echo "------------------------"
    done


    # At the moment we don't send the CSR to the AD CS server because the code below
    # doesn't work. There are issues on the AD CS side that need to be resolved first.
    # The code below is just a placeholder for when the AD CS server is ready.
    #
    # Send CSR to AD CS and get signed certificate
    # openssl s_client -connect ${AD_CS_SERVER_IP}:${AD_CS_PORT} \
    #     -servername ${AD_CS_SERVER} \
    #     < ${csr_file} | \
    # openssl base64 -d | \
    # certtool -i -p "${AD_CS_TEMPLATE}" > ${cert_file}

    # if [ $? -eq 0 ]; then
    #     echo "Certificate for $base_domain and subdomains successfully obtained from AD CS."
    # else
    #     echo "Failed to obtain certificate for $base_domain from AD CS."
    #     return 1
    # fi

    # Clean up the temporary config file
    # rm "$config_file"
}

# Function to retrieve and store CA chain
get_ca_chain() {
    openssl s_client -connect ${AD_CS_SERVER}:${AD_CS_PORT} \
        -servername ${AD_CS_SERVER} \
        -showcerts < /dev/null | \
    awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print}' > ${CHAIN_CERT_FILE}
    update-ca-certificates

    if [ $? -eq 0 ]; then
        echo "CA chain successfully retrieved and stored."
    else
        echo "Failed to retrieve CA chain."
        return 1
    fi
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -d, --domain            Base domain name for INGRESS_DOMAIN (required)"
    echo "  -n, --dns-ip           Local network DNS IP address (required)"
    echo "  -r, --router-ip        Router IP address (required)"
    echo "  -c, --certificates     Generate SSL certificates (optional)"
    echo "  -h, --host             LDAP server hostname (default: $LDAP_HOST)"
    echo "  -p, --port             LDAP server port (default: $LDAP_PORT)"
    echo "  -b, --bind-dn          Bind DN (default: $LDAP_BIND_DN)"
    echo "  -w, --bind-password    Bind password (default: $LDAP_BIND_PASSWORD)"
    echo "  -s, --search-base      Search base (default: $LDAP_SEARCH_BASE)"
    echo "  -f, --search-filter    Search filter (default: $LDAP_SEARCH_FILTER)"
    echo "  -g, --group-base       Group search base (default: $LDAP_GROUP_SEARCH_BASE)"
    echo "  -k, --group-filter     Group search filter (default: $LDAP_GROUP_SEARCH_FILTER)"
    echo "  -a, --admin-group      Admin group (default: $LDAP_ADMIN_GROUP)"
    echo "  -o, --output           Output file (default: $OUTPUT_FILE)"
    echo "  --help                 Show this help message"
}

# Function to check if a volume exists
volume_exists() {
    docker volume inspect "$1" >/dev/null 2>&1
}

# Function to validate domain name
validate_domain() {
    if [[ $1 =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Parse command line arguments
generate_certs=false
domain_name=""
dns_ip=""
router_ip=""

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -d|--domain)
            domain_name="$2"
            shift 2
            ;;
        -n|--dns-ip)
            dns_ip="$2"
            shift 2
            ;;
        -r|--router-ip)
            router_ip="$2"
            shift 2
            ;;
        -c|--certificates)
            generate_certs=true
            shift
            ;;
        -h|--host)
            LDAP_HOST="$2"
            shift 2
            ;;
        -p|--port)
            LDAP_PORT="$2"
            shift 2
            ;;
        -b|--bind-dn)
            LDAP_BIND_DN="$2"
            shift 2
            ;;
        -w|--bind-password)
            LDAP_BIND_PASSWORD="$2"
            shift 2
            ;;
        -s|--search-base)
            LDAP_SEARCH_BASE="$2"
            shift 2
            ;;
        -f|--search-filter)
            LDAP_SEARCH_FILTER="$2"
            shift 2
            ;;
        -g|--group-base)
            LDAP_GROUP_SEARCH_BASE="$2"
            shift 2
            ;;
        -k|--group-filter)
            LDAP_GROUP_SEARCH_FILTER="$2"
            shift 2
            ;;
        -a|--admin-group)
            LDAP_ADMIN_GROUP="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$domain_name" || -z "$dns_ip" || -z "$router_ip" ]]; then
    echo "Error: Domain name, DNS IP, and router IP are required parameters"
    print_usage
    exit 1
fi

# Confirm actions with the user
echo "The following actions will be performed:"
echo "1. Check and create the following Docker volumes if they don't exist:"
for volume in "${volumes[@]}"; do
    echo "   - $volume"
done
echo "2. Create a .env file with:"
echo "   - INGRESS_DOMAIN=$domain_name"
echo "   - LOCAL_NETWORK_DNS_IP=$dns_ip"
echo "   - ROUTER_IP=$router_ip"

if [ "$generate_certs" = true ]; then
    echo "3. Generate and sign SSL certificates for the following domains:"
    for subdomain in "${subdomains[@]}"; do
        echo "   - ${subdomain}.${domain_name}"
    done
    echo "4. Retrieve and store the CA certificate chain"
fi

echo "5. Create a LDAP configuration file for Grafana"
echo "6. Create a LDAP configuration file for Minio"

read -p "Do you want to proceed? (y/n): " confirm

if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "Operation cancelled."
    exit 1
fi

# Perform actions
echo "Checking and creating Docker volumes..."
for volume in "${volumes[@]}"; do
    if volume_exists "$volume"; then
        echo "Volume $volume already exists."
    else
        echo "Creating volume $volume..."
        sudo docker volume create "$volume"
        if [ $? -eq 0 ]; then
            echo "Volume $volume created successfully."
        else
            echo "Failed to create volume $volume."
        fi
    fi
done

echo "Creating .env file..."
create_env_file "$domain_name" "$dns_ip" "$router_ip"

if [ "$generate_certs" = true ]; then
    echo "Retrieving CA certificate chain..."
    get_ca_chain

    echo "Generating certificate signing requests..."
    generate_and_sign_certificate "$domain_name"

    echo "Creating Traefik dynamic configuration file..."
    create_traefik_config "$domain_name"
fi

echo "Creating LDAP configuration file for Grafana..."
create_grafana_ldap_config

echo "Creating LDAP configuration file for Minio..."
create_minio_ldap_config

echo "Script execution completed."