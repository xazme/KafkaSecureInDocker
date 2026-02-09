# #!/usr/bin/env bash
# set -euo pipefail

# PASS="VeryStrongPass123"
# CN="kafka"

# rm -rf secrets/kafka
# mkdir -p secrets/kafka
# cd secrets/kafka

# echo "[*] CA..."
# openssl req -new -x509 -keyout ca-key -out ca-cert -days 365 \
#   -subj "/C=BY/ST=Grodno/L=Grodnenskaya Oblast/O=Volosatie-yaica-ltd/OU=non/CN=ca/emailAddress=juriii155@gmail.com" \
#   -passout pass:${PASS}

# cat > broker-openssl.cnf <<EOF
# [ req ]
# default_bits       = 2048
# prompt             = no
# default_md         = sha256
# distinguished_name = dn
# req_extensions     = v3_req

# [ dn ]
# C  = BY
# ST = Grodno
# L  = Grodnenskaya Oblast
# O  = Volosatie-yaica-ltd
# OU = non
# CN = ${CN}

# [ v3_req ]
# subjectAltName = @alt_names

# [ alt_names ]
# DNS.1 = ${CN}
# DNS.2 = localhost
# EOF

# echo "[*] CSR брокера с SAN..."
# openssl req -new -newkey rsa:2048 \
#   -keyout broker-key.pem -out broker-csr.pem \
#   -config broker-openssl.cnf \
#   -passout pass:${PASS}

# echo "[*] Подписываю брокера CA (с SAN)..."
# openssl x509 -req -in broker-csr.pem -out broker-cert.pem \
#   -CA ca-cert -CAkey ca-key -CAcreateserial \
#   -days 365 -passin pass:${PASS} \
#   -extfile broker-openssl.cnf -extensions v3_req

# echo "[*] Собираю PKCS12 с цепочкой..."
# cat broker-cert.pem ca-cert > broker-fullchain.pem

# openssl pkcs12 -export \
#   -in broker-fullchain.pem -inkey broker-key.pem \
#   -out broker.p12 -name kafka-broker \
#   -passin pass:${PASS} -passout pass:${PASS}

# echo "[*] Делаю JKS keystore..."
# keytool -importkeystore \
#   -srckeystore broker.p12 -srcstoretype PKCS12 -srcstorepass ${PASS} \
#   -destkeystore kafka.keystore.jks -deststoretype JKS -deststorepass ${PASS} \
#   -noprompt

# echo "[*] Truststore с CA..."
# keytool -import -file ca-cert \
#   -keystore kafka.truststore.jks \
#   -alias CARoot -storepass ${PASS} -noprompt

# echo "[*] Проверка содержимого keystore:"
# keytool -list -v -keystore kafka.keystore.jks -storepass ${PASS} | grep -E "Entry type|Certificate chain length|DNS:"

#!/usr/bin/env bash
set -euo pipefail

PASS="VeryStrongPass123"
CN="kafka"

rm -rf secrets/kafka
mkdir -p secrets/kafka
cd secrets/kafka

############################################
# 1. Создаём CA с корректными расширениями
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

echo "[*] Генерирую CA..."
openssl req -new -x509 \
  -keyout ca-key.pem -out ca-cert.pem \
  -days 365 -config ca.cnf \
  -passout pass:${PASS}

############################################
# 2. CSR брокера с SAN
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

echo "[*] Генерирую ключ и CSR брокера..."
openssl req -new -newkey rsa:2048 \
  -keyout broker-key.pem -out broker-csr.pem \
  -config broker.cnf -passout pass:${PASS}

############################################
# 3. Подписываем брокера CA
############################################
echo "[*] Подписываю сертификат брокера..."
openssl x509 -req -in broker-csr.pem -out broker-cert.pem \
  -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
  -days 365 -passin pass:${PASS} \
  -extfile broker.cnf -extensions v3_req

############################################
# 4. PKCS12 → JKS (для Kafka)
############################################
echo "[*] Собираю PKCS12..."
cat broker-cert.pem ca-cert.pem > broker-fullchain.pem

openssl pkcs12 -export \
  -in broker-fullchain.pem -inkey broker-key.pem \
  -out broker.p12 -name kafka-broker \
  -passin pass:${PASS} -passout pass:${PASS}

echo "[*] Создаю keystore..."
keytool -importkeystore \
  -srckeystore broker.p12 -srcstoretype PKCS12 -srcstorepass ${PASS} \
  -destkeystore kafka.keystore.jks -deststoretype JKS -deststorepass ${PASS} \
  -noprompt

echo "[*] Создаю truststore..."
keytool -import -file ca-cert.pem \
  -keystore kafka.truststore.jks \
  -alias CARoot -storepass ${PASS} -noprompt

echo "[*] Готово!"
