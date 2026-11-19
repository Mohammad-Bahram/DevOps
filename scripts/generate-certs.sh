
#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Project configuration
# ============================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CA_DIR="certs/ca"
CLIENT_DIR="certs/client"

NODES=(kafka-1 kafka-2)

# Temporary directory for validation
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=========================================="
echo " Kafka Certificate Management"
echo "=========================================="

# ============================================================
# Load environment variables
# ============================================================

if [[ ! -f .env ]]; then
    echo "ERROR: .env file not found!"
    exit 1
fi

set -a
source .env
set +a

# ============================================================
# Validate environment variables
# ============================================================

: "${KAFKA_USERNAME:?KAFKA_USERNAME is required in .env}"
: "${KAFKA_PASSWORD:?KAFKA_PASSWORD is required in .env}"
: "${BROKER_PASSWORD:?BROKER_PASSWORD is required in .env}"
: "${KEYSTORE_PASSWORD:?KEYSTORE_PASSWORD is required in .env}"
: "${KEY_PASSWORD:?KEY_PASSWORD is required in .env}"

if [[ ! "$KAFKA_USERNAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "ERROR: Invalid KAFKA_USERNAME."
    exit 1
fi

if [[ "$KEYSTORE_PASSWORD" != "$KEY_PASSWORD" ]]; then
    echo "ERROR: KEYSTORE_PASSWORD and KEY_PASSWORD must be identical."
    exit 1
fi

# JAAS values cannot contain newline characters.
for VALUE in "$KAFKA_PASSWORD" "$BROKER_PASSWORD"; do
    if [[ "$VALUE" == *$'\n'* || "$VALUE" == *$'\r'* ]]; then
        echo "ERROR: JAAS passwords cannot contain newline characters."
        exit 1
    fi
done

echo "Environment validation successful."

# ============================================================
# Create required directories
# ============================================================

mkdir -p "$CA_DIR" "$CLIENT_DIR"

for NODE in "${NODES[@]}"; do
    mkdir -p "$NODE/certs" "$NODE/secrets"
done

# ============================================================
# Helper functions
# ============================================================

get_key_fingerprint() {
    openssl pkey -in "$1" -pubout -outform DER |
        openssl dgst -sha256 |
        awk '{print $NF}'
}

get_cert_fingerprint() {
    openssl x509 -in "$1" -pubkey -noout |
        openssl pkey -pubin -outform DER |
        openssl dgst -sha256 |
        awk '{print $NF}'
}

get_pkcs12_key_fingerprint() {
    openssl pkcs12 \
        -in "$1" \
        -nocerts \
        -nodes \
        -passin "pass:$KEYSTORE_PASSWORD" |
        openssl pkey -pubout -outform DER |
        openssl dgst -sha256 |
        awk '{print $NF}'
}

get_pkcs12_cert_fingerprint() {
    openssl pkcs12 \
        -in "$1" \
        -clcerts \
        -nokeys \
        -passin "pass:$KEYSTORE_PASSWORD" |
        openssl x509 -pubkey -noout |
        openssl pkey -pubin -outform DER |
        openssl dgst -sha256 |
        awk '{print $NF}'
}

get_ca_fingerprint() {
    openssl x509 -in "$1" -noout -fingerprint -sha256 |
        cut -d= -f2
}

jaas_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"

    printf '%s' "$value"
}

# ============================================================
# Verify or generate Certificate Authority
# ============================================================

echo
echo "Checking Certificate Authority..."

CA_KEY="$CA_DIR/ca.key"
CA_CERT="$CA_DIR/ca.crt"

if [[ -f "$CA_KEY" && -f "$CA_CERT" ]]; then

    echo "Existing CA found. Validating..."

    CA_KEY_FP="$(get_key_fingerprint "$CA_KEY")"
    CA_CERT_FP="$(get_cert_fingerprint "$CA_CERT")"

    if [[ "$CA_KEY_FP" != "$CA_CERT_FP" ]]; then
        echo "ERROR: CA private key does not match CA certificate."
        exit 1
    fi

    echo "Existing CA is valid. Reusing it."

elif [[ -e "$CA_KEY" || -e "$CA_CERT" ]]; then

    echo "ERROR: Incomplete CA detected."
    echo "Both ca.key and ca.crt must exist."
    exit 1

else

    echo "No CA found. Generating a new CA..."

    openssl genrsa -out "$CA_KEY" 4096

    openssl req -x509 -new -nodes \
        -key "$CA_KEY" \
        -sha256 \
        -days 3650 \
        -out "$CA_CERT" \
        -subj "/CN=Kafka-CA"

    chmod 600 "$CA_KEY"

    echo "New CA generated successfully."

fi

chmod 600 "$CA_KEY"

# ============================================================
# Copy CA certificate
# ============================================================

cp "$CA_CERT" "$CLIENT_DIR/ca.crt"

# ============================================================
# Verify or generate broker certificates
# ============================================================

for NODE in "${NODES[@]}"; do

    echo
    echo "Checking certificate for $NODE..."

    NODE_KEY="certs/$NODE.key"
    NODE_CERT="certs/$NODE.crt"
    NODE_CSR="certs/$NODE.csr"
    NODE_EXT="certs/$NODE.ext"

    if [[ -f "$NODE_KEY" && -f "$NODE_CERT" ]]; then

        echo "Existing certificate found. Validating..."

    elif [[ -e "$NODE_KEY" || -e "$NODE_CERT" ]]; then

        echo "ERROR: Incomplete certificate pair for $NODE."
        echo "Both private key and certificate must exist."
        exit 1

    else

        echo "Generating certificate for $NODE..."

        openssl genrsa -out "$NODE_KEY" 2048

        openssl req -new \
            -key "$NODE_KEY" \
            -out "$NODE_CSR" \
            -subj "/CN=$NODE"

        cat > "$NODE_EXT" <<EOF
subjectAltName=DNS:$NODE,DNS:localhost
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EOF

        openssl x509 -req \
            -in "$NODE_CSR" \
            -CA "$CA_CERT" \
            -CAkey "$CA_KEY" \
            -CAcreateserial \
            -out "$NODE_CERT" \
            -days 825 \
            -sha256 \
            -extfile "$NODE_EXT"

    fi

    chmod 600 "$NODE_KEY"

    # Validate private key and certificate match

    KEY_FP="$(get_key_fingerprint "$NODE_KEY")"
    CERT_FP="$(get_cert_fingerprint "$NODE_CERT")"

    if [[ "$KEY_FP" != "$CERT_FP" ]]; then
        echo "ERROR: Private key mismatch for $NODE."
        exit 1
    fi

    # Validate certificate chain

    openssl verify \
        -CAfile "$CA_CERT" \
        "$NODE_CERT"

    # Validate hostname

    openssl x509 -in "$NODE_CERT" -checkhost "$NODE" -noout
    openssl x509 -in "$NODE_CERT" -checkhost localhost -noout

    # Copy broker certificates and private keys

    cp "$NODE_CERT" "$NODE/certs/$NODE.crt"
    cp "$NODE_KEY" "$NODE/certs/$NODE.key"
    cp "$CA_CERT" "$NODE/certs/ca.crt"

    chmod 600 "$NODE/certs/$NODE.key"

    # ========================================================
    # Create or validate PKCS12 keystore
    # ========================================================

    P12_FILE="$NODE/certs/$NODE.p12"

    if [[ -f "$P12_FILE" ]]; then

        echo "Existing PKCS12 found. Validating..."

        openssl pkcs12 \
            -in "$P12_FILE" \
            -info \
            -noout \
            -passin "pass:$KEYSTORE_PASSWORD"

        P12_CERT_FP="$(get_pkcs12_cert_fingerprint "$P12_FILE")"
        P12_KEY_FP="$(get_pkcs12_key_fingerprint "$P12_FILE")"

        if [[ "$P12_CERT_FP" != "$CERT_FP" ||
              "$P12_KEY_FP" != "$KEY_FP" ]]; then
            echo "ERROR: PKCS12 content does not match $NODE certificate."
            exit 1
        fi

    else

        echo "Creating PKCS12 keystore for $NODE..."

        openssl pkcs12 -export \
            -in "$NODE_CERT" \
            -inkey "$NODE_KEY" \
            -certfile "$CA_CERT" \
            -name "$NODE" \
            -out "$P12_FILE" \
            -passout "pass:$KEYSTORE_PASSWORD"

    fi

    # ========================================================
    # Create or validate truststore
    # ========================================================

    TRUSTSTORE="$NODE/certs/truststore.p12"

    if [[ -f "$TRUSTSTORE" ]]; then

        echo "Existing truststore found. Validating..."

        keytool -list \
            -keystore "$TRUSTSTORE" \
            -storetype PKCS12 \
            -storepass "$KEYSTORE_PASSWORD" >/dev/null

        CA_FP="$(get_ca_fingerprint "$CA_CERT")"
        TRUSTSTORE_CA_FOUND=false

        while IFS= read -r ALIAS; do

            [[ -z "$ALIAS" ]] && continue

            EXPORTED_CERT="$TMP_DIR/truststore-cert.der"

            if keytool -exportcert \
                -alias "$ALIAS" \
                -keystore "$TRUSTSTORE" \
                -storetype PKCS12 \
                -storepass "$KEYSTORE_PASSWORD" \
                -file "$EXPORTED_CERT" >/dev/null 2>&1; then

                EXPORTED_FP="$(
                    openssl x509 \
                        -inform DER \
                        -in "$EXPORTED_CERT" \
                        -noout \
                        -fingerprint \
                        -sha256 |
                    cut -d= -f2
                )"

                if [[ "$EXPORTED_FP" == "$CA_FP" ]]; then
                    TRUSTSTORE_CA_FOUND=true
                    break
                fi
            fi

        done < <(
            keytool -list \
                -keystore "$TRUSTSTORE" \
                -storetype PKCS12 \
                -storepass "$KEYSTORE_PASSWORD" |
            awk -F, '/trustedCertEntry/ {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1);
                print $1
            }'
        )

        if [[ "$TRUSTSTORE_CA_FOUND" != true ]]; then
            echo "ERROR: Current CA not found in $TRUSTSTORE."
            exit 1
        fi

    else

        echo "Creating truststore for $NODE..."

        keytool -importcert \
            -noprompt \
            -alias kafka-ca \
            -file "$CA_CERT" \
            -keystore "$TRUSTSTORE" \
            -storetype PKCS12 \
            -storepass "$KEYSTORE_PASSWORD"

    fi

    # ========================================================
    # Password files
    # ========================================================

    printf '%s' "$KEYSTORE_PASSWORD" > "$NODE/secrets/keystore-password"
    printf '%s' "$KEY_PASSWORD" > "$NODE/secrets/key-password"

    chmod 600 \
        "$NODE/certs/$NODE.p12" \
        "$NODE/certs/truststore.p12" \
        "$NODE/secrets/keystore-password" \
        "$NODE/secrets/key-password"

    echo "$NODE certificate configuration is valid."

done

# ============================================================
# Generate JAAS configurations
# ============================================================

echo
echo "Generating JAAS configurations..."

KAFKA_PASSWORD_JAAS="$(jaas_escape "$KAFKA_PASSWORD")"
BROKER_PASSWORD_JAAS="$(jaas_escape "$BROKER_PASSWORD")"

for NODE in "${NODES[@]}"; do

    cat > "$NODE/secrets/broker_jaas.conf" <<EOF
KafkaServer {
    org.apache.kafka.common.security.plain.PlainLoginModule required
    username="broker"
    password="${BROKER_PASSWORD_JAAS}"
    user_broker="${BROKER_PASSWORD_JAAS}"
    user_${KAFKA_USERNAME}="${KAFKA_PASSWORD_JAAS}";
};

KafkaClient {
    org.apache.kafka.common.security.plain.PlainLoginModule required
    username="broker"
    password="${BROKER_PASSWORD_JAAS}";
};
EOF

    chmod 600 "$NODE/secrets/broker_jaas.conf"

done

echo "JAAS configurations generated successfully."

# ============================================================
# Final verification
# ============================================================

echo
echo "=========================================="
echo " Final Certificate Verification"
echo "=========================================="

for NODE in "${NODES[@]}"; do

    openssl verify \
        -CAfile "$CA_CERT" \
        "certs/$NODE.crt"

    echo "$NODE: OK"

done

echo
echo "All Kafka certificates and configurations are valid."
