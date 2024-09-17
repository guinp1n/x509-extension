#!/usr/bin/env bash
#
# Script to generate SSL certificates for Server and Clients
#

set -e

# Default values
defaultHostnames="localhost,example1.com,example2.com"
defaultClients="client1,client2"
defaultPass="changeme"
serverValidity=1
clientValidity=1
keystoreType="JKS"

# Usage function
usage() {
    echo "Usage: $0 [-h hostnames] [-p password] [-s serverValidity] [-c clientValidity] [-n clientNames] [-k keystoreType]"
    exit 1
}

# Parse named parameters
while getopts "h:p:s:c:n:k:" opt; do
    case ${opt} in
        h) hostnames=$OPTARG ;;
        p) defaultPass=$OPTARG ;;
        s) serverValidity=$OPTARG ;;
        c) clientValidity=$OPTARG ;;
        n) clients=$OPTARG ;;
        k) keystoreType=$OPTARG ;;
        *) usage ;;
    esac
done

# Set defaults if not provided
hostnames=${hostnames:-$defaultHostnames}
clients=${clients:-$defaultClients}
keystoreType=${keystoreType:-$keystoreType}

IFS=',' read -r -a hostnamesArray <<< "$hostnames"
IFS=',' read -r -a clientsArray <<< "$clients"

declare -A keystoreMap=( ["JKS"]="jks" ["PKCS12"]="p12" )
ext=${keystoreMap[$keystoreType]}

time1=$(date '+%Y%m%d_%H%M%S')
outputDirectory="certs_${keystoreType}_${time1}"
mkdir -p "$outputDirectory"
pushd "$outputDirectory" > /dev/null

# Generate README file with parameters
cat <<EOF > readme.txt
hostnames: ${hostnames[*]}
clients: ${clients[*]}
defaultPass: ${defaultPass}
serverValidity: ${serverValidity}
clientValidity: ${clientValidity}
created: $(date +%Y-%m-%dT%H:%M:%S)
keystoreType: ${keystoreType}
EOF

# Prepare hostnames for SAN
for hostname in "${hostnamesArray[@]}"; do
  if [[ $hostname =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    modified_hostnames+=("ip:$hostname")
  else
    modified_hostnames+=("dns:$hostname")
  fi
done
IFS=','; joinedHostnames="${modified_hostnames[*]}"; unset IFS

# Generate broker certificates
echo "Generating server certificate for SAN=${joinedHostnames}, keystoreType: $keystoreType"
keytool -genkey -keyalg RSA -alias "HiveMQ Broker Certificate" \
    -keystore "broker-keystore.${ext}" -storetype "${keystoreType}" \
    -storepass "${defaultPass}" -keypass "${defaultPass}" \
    -validity "${serverValidity}" -keysize 2048 \
    -dname "CN=HiveMQ Broker, OU=Customer Services, O=HiveMQ, L=Landshut, ST=Bavaria, C=DE" \
    -ext "SAN=$joinedHostnames"

# Export and convert broker certificates
keytool -exportcert -alias "HiveMQ Broker Certificate" \
    -file "broker-cert.pem" -keystore "broker-keystore.${ext}" \
    -rfc -storepass "$defaultPass"

openssl x509 -outform der -in "broker-cert.pem" -out "broker-cert.crt"

# Import broker cert into client truststore
printf "yes\n" | keytool -import -file "broker-cert.crt" \
    -alias "${hostname}" -keystore "client-truststore.${ext}" \
    -storepass "${defaultPass}" -storetype "${keystoreType}"

# Generate a CA certificate
openssl genrsa -out alwaystrustmeCA.key 2048
openssl req -x509 -new -nodes -key alwaystrustmeCA.key -sha256 -days 1024 \
    -out alwaystrustmeCA.pem -subj "/CN=alwaystrustme"

# Generate client certificates
for clientName in "${clientsArray[@]}"; do
  clientCert="${clientName}-cert"
  clientKey="${clientName}-key"

  openssl genrsa -out "${clientKey}.pem" 2048
  openssl req -new -key "${clientKey}.pem" -out "${clientCert}.csr" -subj "/CN=${clientName}"

  openssl x509 -req -in "${clientCert}.csr" -CA alwaystrustmeCA.pem -CAkey alwaystrustmeCA.key -CAcreateserial \
      -out "${clientCert}.pem" -days "${clientValidity}" -sha256

  openssl x509 -outform der -in "${clientCert}.pem" -out "${clientCert}.crt"

  # Import client cert into broker truststore
  printf "yes\n" | keytool -import -file "${clientCert}.crt" \
      -alias "${clientName}" -keystore "broker-truststore.${ext}" \
      -storetype "${keystoreType}" -storepass "${defaultPass}"

  # Create client PKCS12 keystore
  openssl pkcs12 -export -in "${clientCert}.pem" -inkey "${clientKey}.pem" \
      -certfile "${clientCert}.pem" -out "${clientName}-keystore.p12" \
      -passin pass:"${defaultPass}" -passout pass:"${defaultPass}"

  # Add client PKCS12 keystore to the master keystore
  keytool -importkeystore -alias 1 -destalias "${clientName}" \
      -srckeystore "${clientName}-keystore.p12" -srcstoretype PKCS12 \
      -srcstorepass "${defaultPass}" -destkeystore "clients-keystore.${ext}" \
      -deststoretype "${keystoreType}" -storepass "${defaultPass}" -noprompt
done

popd > /dev/null
echo "Certificates saved to: $(pwd)/$outputDirectory"
