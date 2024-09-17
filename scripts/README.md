# SSL Certificate Generation Script

This Bash script automates the generation of SSL certificates for a server and multiple clients. It supports the creation of certificates in both JKS and PKCS12 keystore formats. The script generates:

- A server certificate with Subject Alternative Names (SAN)
- A client truststore containing the server certificate
- A CA certificate
- Client certificates signed by the CA
- Client keystores in PKCS12 format

The script also outputs a `readme.txt` with the key parameters used during execution.

## Prerequisites

- `keytool` (part of JDK)
- `openssl`
- Bash (tested with bash 5.x)
- Ensure `keytool` and `openssl` are installed and accessible via your `PATH`.

## Usage

```bash
./generate-certs.sh [-h hostnames] [-p password] [-s serverValidity] [-c clientValidity] [-n clientNames] [-k keystoreType]
```

### Options
- `-h` Hostnames for the server certificate's SAN field (comma-separated list). Defaults to `localhost,example1.com,example2.com`.
- `-p` Password for keystore and truststore. Defaults to `changeme`.
- `-s` Validity period (in days) for the server certificate. Defaults to `1` day.
- `-c` Validity period (in days) for client certificates. Defaults to `1` day.
- `-n` Client names (comma-separated list). Defaults to `client1,client2`.
- `-k` Keystore type (JKS or PKCS12). Defaults to `JKS`.

## Examples

```bash
./generate-certs.sh
```

```bash
./generate-certs.sh -k "JKS" -p "newpassword"
```

```bash
./generate-certs.sh -k "PKCS12" -s 365 -c 365
```
```bash
./generate-certs.sh -s 730 -c 90
```

```bash
./generate-certs.sh -h "mydomain.com,sub.mydomain.com" -n "clientA,clientB" -p "strongpassword"
```

```bash
./generate-certs.sh -n "client1,client2,client3,client4,client5,client6"
```

### Output
The generated certificates and keystores are saved in a directory named `certs_{keystoreType}_{timestamp}`.
The directory contains:
* Server keystore
* Server certificate in PEM and CRT formats
* Client keystores and truststore
* CA certificate
* A readme.txt file summarizing the parameters used.

