import json
import os

from confluent_kafka import Consumer


config = {
    "bootstrap.servers": os.getenv(
            "KAFKA_BOOTSTRAP_SERVERS",
            "kafka-1:9092,kafka-2:9092"
        ),
    "security.protocol": "SASL_SSL",
    "sasl.mechanism": "PLAIN",
    "sasl.username": os.getenv("KAFKA_USERNAME"),
    "sasl.password": os.getenv("KAFKA_PASSWORD"),
    "ssl.ca.location": "/certs/ca.crt",
    "group.id": "message-consumer-group",
    "auto.offset.reset": "earliest",
}

consumer = Consumer(config)

TOPIC = "events"

consumer.subscribe([TOPIC])

print("Consumer started. Waiting for messages...", flush=True)

try:
    while True:
        message = consumer.poll(1.0)

        if message is None:
            continue

        if message.error():
            print(f"Consumer error: {message.error()}", flush=True)
            continue

        data = json.loads(message.value().decode("utf-8"))

        print(
            f"Received message: {json.dumps(data, indent=2)}",
            flush=True,
        )

except KeyboardInterrupt:
    print("Consumer stopped.")

finally:
    consumer.close()
