
#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Kafka Topic Viewer
# ============================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONTAINER_SERVICE="kafka-1"
KAFKA_BIN="/opt/kafka/bin"
BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-kafka-1:9092,kafka-2:9092}"

CLIENT_CONFIG_LOCAL=""
CLIENT_CONFIG_REMOTE=""

# ============================================================
# Cleanup
# ============================================================

cleanup() {
    if [[ -n "$CLIENT_CONFIG_REMOTE" ]]; then
        docker compose exec -T "$CONTAINER_SERVICE" \
            rm -f "$CLIENT_CONFIG_REMOTE" >/dev/null 2>&1 || true
    fi

    if [[ -n "$CLIENT_CONFIG_LOCAL" ]]; then
        rm -f "$CLIENT_CONFIG_LOCAL"
    fi
}

trap cleanup EXIT

# ============================================================
# Helper functions
# ============================================================

error() {
    echo "ERROR: $*" >&2
    exit 1
}

jaas_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"

    printf '%s' "$value"
}

# ============================================================
# Header
# ============================================================

echo "=========================================="
echo "          Kafka Topic Viewer"
echo "=========================================="

# ============================================================
# Load environment variables
# ============================================================

if [[ ! -f .env ]]; then
    error ".env file not found!"
fi

set -a
source .env
set +a

: "${KAFKA_USERNAME:?KAFKA_USERNAME is required in .env}"
: "${KAFKA_PASSWORD:?KAFKA_PASSWORD is required in .env}"
: "${KEYSTORE_PASSWORD:?KEYSTORE_PASSWORD is required in .env}"

if [[ "$KAFKA_PASSWORD" == *$'\n'* ||
      "$KAFKA_PASSWORD" == *$'\r'* ]]; then
    error "Invalid KAFKA_PASSWORD."
fi

if [[ "$KEYSTORE_PASSWORD" == *$'\n'* ||
      "$KEYSTORE_PASSWORD" == *$'\r'* ]]; then
    error "Invalid KEYSTORE_PASSWORD."
fi

echo "Environment loaded successfully."

# ============================================================
# Check dependencies
# ============================================================

command -v docker >/dev/null 2>&1 ||
    error "Docker is not installed."

docker compose ps --status running -q "$CONTAINER_SERVICE" |
    grep -q . ||
    error "Kafka container is not running."

docker compose exec -T "$CONTAINER_SERVICE" \
    test -r /etc/kafka/secrets/truststore.p12 ||
    error "Truststore not found."

echo "Kafka container is running."

# ============================================================
# Create client configuration
# ============================================================

CLIENT_CONFIG_LOCAL="$(mktemp)"
chmod 600 "$CLIENT_CONFIG_LOCAL"

KAFKA_PASSWORD_JAAS="$(jaas_escape "$KAFKA_PASSWORD")"
KAFKA_USERNAME_JAAS="$(jaas_escape "$KAFKA_USERNAME")"

cat > "$CLIENT_CONFIG_LOCAL" <<EOF
security.protocol=SASL_SSL

ssl.truststore.location=/etc/kafka/secrets/truststore.p12
ssl.truststore.password=${KEYSTORE_PASSWORD}
ssl.truststore.type=PKCS12

sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_USERNAME_JAAS}" password="${KAFKA_PASSWORD_JAAS}";
EOF

CLIENT_CONFIG_REMOTE="/tmp/kafka-client-viewer-$$.properties"

docker compose exec -T "$CONTAINER_SERVICE" sh -c \
    "umask 077; cat > '$CLIENT_CONFIG_REMOTE'" \
    < "$CLIENT_CONFIG_LOCAL"

echo "Kafka client configuration created."

# ============================================================
# List topics
# ============================================================

echo
echo "Fetching topics..."

TOPICS_OUTPUT="$(
    docker compose exec -T "$CONTAINER_SERVICE" \
        "$KAFKA_BIN/kafka-topics.sh" \
        --bootstrap-server "$BOOTSTRAP_SERVERS" \
        --command-config "$CLIENT_CONFIG_REMOTE" \
        --list
)" || error "Failed to fetch topics."

mapfile -t TOPICS < <(
    printf '%s\n' "$TOPICS_OUTPUT" |
        sed '/^[[:space:]]*$/d'
)

if [[ ${#TOPICS[@]} -eq 0 ]]; then
    echo "No topics found."
    exit 0
fi

# ============================================================
# Display topics
# ============================================================

echo
echo "Available topics:"
echo "------------------------------------------"

for i in "${!TOPICS[@]}"; do
    printf "  %d) %s\n" "$((i + 1))" "${TOPICS[$i]}"
done

echo "------------------------------------------"

# ============================================================
# Select topic
# ============================================================

echo
read -r -p "Select a topic number (or q to quit): " SELECTION

if [[ "$SELECTION" == "q" || "$SELECTION" == "Q" ]]; then
    exit 0
fi

if [[ ! "$SELECTION" =~ ^[0-9]+$ ]]; then
    error "Invalid topic number."
fi

if (( SELECTION < 1 || SELECTION > ${#TOPICS[@]} )); then
    error "Topic number out of range."
fi

SELECTED_TOPIC="${TOPICS[$((SELECTION - 1))]}"

echo
echo "Selected topic: $SELECTED_TOPIC"

# ============================================================
# Select consumption mode
# ============================================================

echo
echo "Choose consumption mode:"
echo "------------------------------------------"
echo "1) Read all messages from the beginning"
echo "2) Read a limited number of messages"
echo "3) Read only new messages"
echo "------------------------------------------"

read -r -p "Choose an option: " MODE

CONSUMER_ARGS=(
    --bootstrap-server "$BOOTSTRAP_SERVERS"
    --consumer.config "$CLIENT_CONFIG_REMOTE"
    --topic "$SELECTED_TOPIC"
)

case "$MODE" in
    1)
        CONSUMER_ARGS+=(--from-beginning)
        ;;

    2)
        read -r -p "How many messages? " MESSAGE_COUNT

        if [[ ! "$MESSAGE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
            error "Invalid message count."
        fi

        CONSUMER_ARGS+=(
            --from-beginning
            --max-messages "$MESSAGE_COUNT"
        )
        ;;

    3)
        # Default behavior: consume only new messages.
        ;;

    *)
        error "Invalid option."
        ;;
esac

# ============================================================
# Consume messages
# ============================================================

echo
echo "=========================================="
echo "Reading topic: $SELECTED_TOPIC"
echo "Press Ctrl+C to stop."
echo "=========================================="
echo

docker compose exec -T "$CONTAINER_SERVICE" \
    "$KAFKA_BIN/kafka-console-consumer.sh" \
    "${CONSUMER_ARGS[@]}"
