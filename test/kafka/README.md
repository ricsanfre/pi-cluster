# Kafka Testing

To test Kafka cluster, a set of kafka python clients can be used.

Testing clients are using [confluent-kafka-python](https://github.com/confluentinc/confluent-kafka-python). Testing code is based on the samples code provided in python repository [confluent-kafka-python - Examples](https://github.com/confluentinc/confluent-kafka-python/tree/master/examples).


## Installation Instructions

### Setup Python venv environment

To setup a venv run this commands from this kafka/clients directory

-  Create venv using `uv` package manager
    ```shell
    uv venv
    ```
-  Activate venv
    ```bash
    source .venv/bin/activate
    ```
-  Install all python dependencies
    ```uv
    uv sync
    ```

## Testing Instructions

### Kafka Setup

To create testing Kafka topics and testing users

```bash
kubectl kustomize kafka | kubectl apply -f -
```

### Test Schema Registry and AVRO consumer/producer

-   Go to `clients` directory

    ```shell
    cd clients
    ```
-   Export environment variables

    Set environment variables for Kafka bootstrap server and Schema Registry

    For example:
    ```shell
    export KAFKA_REMOTE_BOOTSTRAP=kafka-bootstrap.homelab.ricsanfre.com
    export KAFKA_SCHEMA_REGISTRY=schema-registry.homelab.ricsanfre.com
    ```

-   Start AVRO Producer

    ```shell
    python3 avro_producer.py \
        -b ${KAFKA_REMOTE_BOOTSTRAP}:443 \
        -s https://${KAFKA_SCHEMA_REGISTRY} \
        -t test-topic-avro \
        -m SCRAM-SHA-512 \
        --tls true \
        --user producer \
        --password supers1cret0
    ```

-   Start AVRO Consumer

    ```shell
    python3 avro_consumer.py \
        -b ${KAFKA_REMOTE_BOOTSTRAP}:443 \
        -s https://${KAFKA_SCHEMA_REGISTRY}  \
        -t test-topic-avro \
        -m SCRAM-SHA-512 \
        -g test-consumer-group \
        --tls true \
        --user consumer \
        --password s1cret0
    ```
