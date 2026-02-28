#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# if an unset variable is used, or if a pipe fails.
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
PASS="VeryStrongPass123"
CN="kafka"
OUTPUT_DIR="secrets/kafka"

echo "---------------------------------------------------------"
echo " Kafka SSL Certificate Generator"
echo "---------------------------------------------------------"

# Prepare workspace
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

############################################
# 1. Create Certificate Authority (CA)
############################################
cat > ca.cnf <<EOF
[ req ]
default_bits       = 4096
prompt             = no
default_md         = sha256
distinguished_name = dn
x509_extensions    = v3_ca

[ dn ]
C  = BY
ST = Grodno
L  = Grodnenskaya Oblast
O  = Volosatie-yaica-ltd
OU = non
CN = ca

[ v3_ca ]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF

echo "[*] Generating CA Private Key and Certificate..."
openssl req -new -x509 \
  -keyout ca-key.pem -out ca-cert.pem \
  -days 365 -config ca.cnf \
  -passout pass:${PASS}

############################################
# 2. Generate Broker CSR with SAN
############################################
cat > broker.cnf <<EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = v3_req

[ dn ]
C  = BY
ST = Grodno
L  = Grodnenskaya Oblast
O  = Volosatie-yaica-ltd
OU = non
CN = ${CN}

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = ${CN}
DNS.2 = localhost
IP.1  = 127.0.0.1
EOF

echo "[*] Generating Broker Private Key and CSR..."
openssl req -new -newkey rsa:2048 \
  -keyout broker-key.pem -out broker-csr.pem \
  -config broker.cnf -passout pass:${PASS}

############################################
# 3. Sign Broker Certificate with CA
############################################
echo "[*] Signing Broker Certificate with CA..."
openssl x509 -req -in broker-csr.pem -out broker-cert.pem \
  -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
  -days 365 -passin pass:${PASS} \
  -extfile broker.cnf -extensions v3_req

############################################
# 4. Export to PKCS12 and JKS (Java KeyStore)
############################################
echo "[*] Building fullchain and exporting to PKCS12..."
cat broker-cert.pem ca-cert.pem > broker-fullchain.pem

openssl pkcs12 -export \
  -in broker-fullchain.pem -inkey broker-key.pem \
  -out broker.p12 -name kafka-broker \
  -passin pass:${PASS} -passout pass:${PASS}

echo "[*] Importing into Kafka Keystore (JKS)..."
keytool -importkeystore \
  -srckeystore broker.p12 -srcstoretype PKCS12 -srcstorepass ${PASS} \
  -destkeystore kafka.keystore.jks -deststoretype JKS -deststorepass ${PASS} \
  -noprompt

echo "[*] Creating Kafka Truststore (JKS)..."
keytool -import -file ca-cert.pem \
  -keystore kafka.truststore.jks \
  -alias CARoot -storepass ${PASS} -noprompt

echo "---------------------------------------------------------"
echo " SUCCESS: Certificates generated in $OUTPUT_DIR"
echo "---------------------------------------------------------"
ls -1