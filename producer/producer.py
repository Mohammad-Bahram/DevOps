import json
import time
import uuid
from datetime import datetime, timezone
import os
from confluent_kafka import Producer


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
}

producer = Producer(config)

TOPIC = "events"


def delivery_report(error, message):
    if error:
        print(f"Message delivery failed: {error}")
    else:
        print(
            f"Message delivered: "
            f"topic={message.topic()}, "
            f"partition={message.partition()}, "
            f"offset={message.offset()}",
            flush=True,
        )


try:
    while True:
        message = {
            "id": str(uuid.uuid4()),
            "message": "Hello from Kafka Producer",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        producer.produce(
            TOPIC,
            key=message["id"],
            value=json.dumps(message),
            callback=delivery_report,
        )

        producer.poll(0)
        print(f"Produced: {message}", flush=True)

        time.sleep(5)

except KeyboardInterrupt:
    print("Producer stopped.")

finally:
    producer.flush()
