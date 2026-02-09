import asyncio
import ssl

from faststream import AckPolicy
from faststream.kafka import KafkaBroker, KafkaMessage
from faststream.security import BaseSecurity

ssl_context = ssl.create_default_context(
    purpose=ssl.Purpose.SERVER_AUTH,
    cafile="secrets/kafka/ca-cert.pem",
)
security = BaseSecurity(
    ssl_context=ssl_context,
    use_ssl=True,
)

broker = KafkaBroker(
    bootstrap_servers="localhost:19092",
    acks="all",
    enable_idempotence=True,
    client_id="Secure Kafka Broker",
    security=security,
)

publisher = broker.publisher("")


@broker.subscriber(
    "test-topic",
    group_id="Secure Kafka Broker",
    ack_policy=AckPolicy.MANUAL,
    auto_offset_reset="earliest",
)
async def what(message: KafkaMessage):
    print("RECEIVED:", message.body)
    await message.ack()


async def main():
    await broker.start()

    await asyncio.sleep(2)

    await publisher.publish("kafka hello", topic="test-topic")

    await asyncio.sleep(5)
    await broker.stop()


asyncio.run(main())
