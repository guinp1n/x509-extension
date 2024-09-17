#!/usr/bin/env bash
#
# Script to generate SSL certificates for Server and Clients
#

set -e

# Default values
DEFAULT_HOSTNAMES="localhost,example1.com,example2.com"
DEFAULT_CLIENTS="client1,client2"
DEFAULT_ISSUER="alwaystrustme"
DEFAULT_PASS="changeme"
SERVER_VALIDITY=1  # Validity in days
CLIENT_VALIDITY=1  # Validity in days
KEYSTORE_TYPE="JKS"

# Usage function
usage() {
    echo "Usage: $0 [-h hostnames] [-p password] [-s serverValidity] [-c clientValidity] [-n clients] [-k keystoreType] [-i issuerName]"
    exit 1
}

# Parse named parameters
while getopts "h:p:s:c:n:k:a:" opt; do
    case ${opt} in
        h) HOSTNAMES=$OPTARG ;;
        p) PASS=$OPTARG ;;
        s) SERVER_VALIDITY=$OPTARG ;;
        c) CLIENT_VALIDITY=$OPTARG ;;
        n) CLIENTS=$OPTARG ;;
        k) KEYSTORE_TYPE=$OPTARG ;;
        i) ISSUER=$OPTARG ;;
        *) usage ;;
    esac
done

# Set defaults if not provided
HOSTNAMES=${HOSTNAMES:-$DEFAULT_HOSTNAMES}
CLIENTS=${CLIENTS:-$DEFAULT_CLIENTS}
KEYSTORE_TYPE=${KEYSTORE_TYPE:-$KEYSTORE_TYPE}
ISSUER=${ISSUER:-$DEFAULT_ISSUER}
PASS=${PASS:-$DEFAULT_PASS}

IFS=',' read -r -a HOSTNAME_ARRAY <<< "$HOSTNAMES"
IFS=',' read -r -a CLIENT_ARRAY <<< "$CLIENTS"

declare -A KEYSTORE_EXT=( ["JKS"]="jks" ["PKCS12"]="p12" )
EXT=${KEYSTORE_EXT[$KEYSTORE_TYPE]}

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
OUTPUT_DIR="certs_${KEYSTORE_TYPE}_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"
pushd "$OUTPUT_DIR" > /dev/null

# Generate README file with parameters
cat <<EOF > README.txt
hostnames: ${HOSTNAMES}
clients: ${CLIENTS}
password: ${PASS}
serverValidity: ${SERVER_VALIDITY}
clientValidity: ${CLIENT_VALIDITY}
created: $(date +%Y-%m-%dT%H:%M:%S)
keystoreType: ${KEYSTORE_TYPE}
EOF

# Prepare hostnames for SAN
SAN_LIST=()
for HOSTNAME in "${HOSTNAME_ARRAY[@]}"; do
  if [[ $HOSTNAME =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    SAN_LIST+=("ip:$HOSTNAME")
  else
    SAN_LIST+=("dns:$HOSTNAME")
  fi
done
SAN="${SAN_LIST[*]}"

# Generate server certificate
echo "Generating server certificate with SAN=${SAN} and keystoreType=${KEYSTORE_TYPE}"
keytool -genkey -keyalg RSA -alias "ServerCert" \
    -keystore "server-keystore.${EXT}" -storetype "${KEYSTORE_TYPE}" \
    -storepass "${PASS}" -keypass "${PASS}" \
    -validity "${SERVER_VALIDITY}" -keysize 2048 \
    -dname "CN=Server, OU=Services, O=Organization, L=City, ST=State, C=Country" \
    -ext "SAN=${SAN}"

# Export and convert server certificate
keytool -exportcert -alias "ServerCert" \
    -file "server-cert.pem" -keystore "server-keystore.${EXT}" \
    -rfc -storepass "${PASS}"

openssl x509 -outform der -in "server-cert.pem" -out "server-cert.crt"

# Import server cert into client truststore
keytool -import -file "server-cert.crt" \
    -alias "server" -keystore "client-truststore.${EXT}" \
    -storepass "${PASS}" -storetype "${KEYSTORE_TYPE}" -noprompt

# Generate CA certificate
openssl genrsa -out "${ISSUER}CA-key.pem" 2048
openssl req -x509 -new -nodes -key "${ISSUER}CA-key.pem" -sha256 -days 1024 \
    -out "${ISSUER}CA-cert.pem" -subj "/CN=${ISSUER}"

# Generate client certificates
for CLIENT in "${CLIENT_ARRAY[@]}"; do
  CLIENT_KEY="${CLIENT}-key.pem"
  CLIENT_CERT="${CLIENT}-cert.pem"

  openssl genrsa -out "$CLIENT_KEY" 2048
  openssl req -new -key "$CLIENT_KEY" -out "${CLIENT}-cert.csr" -subj "/CN=${CLIENT}"

  openssl x509 -req -in "${CLIENT}-cert.csr" -CA "${ISSUER}CA-cert.pem" -CAkey "${ISSUER}CA-key.pem" -CAcreateserial \
      -out "$CLIENT_CERT" -days "${CLIENT_VALIDITY}" -sha256

  openssl x509 -outform der -in "$CLIENT_CERT" -out "${CLIENT}-cert.crt"

  # Import client cert into broker truststore
  keytool -import -file "${CLIENT}-cert.crt" \
      -alias "${CLIENT}" -keystore "broker-truststore.${EXT}" \
      -storetype "${KEYSTORE_TYPE}" -storepass "${PASS}" -noprompt

  # Create client PKCS12 keystore
  openssl pkcs12 -export -in "$CLIENT_CERT" -inkey "$CLIENT_KEY" \
      -certfile "$CLIENT_CERT" -out "${CLIENT}-keystore.p12" \
      -passin pass:"${PASS}" -passout pass:"${PASS}"

  # Add client PKCS12 keystore to the master keystore
  keytool -importkeystore -alias "${CLIENT}" \
      -srckeystore "${CLIENT}-keystore.p12" -srcstoretype PKCS12 \
      -srcstorepass "${PASS}" -destkeystore "clients-keystore.${EXT}" \
      -deststoretype "${KEYSTORE_TYPE}" -storepass "${PASS}" -noprompt
done

popd > /dev/null
echo "Certificates saved to: $(pwd)/$OUTPUT_DIR"
