.EXPORT_ALL_VARIABLES:

KUBECONFIG = $(shell pwd)/ansible-runner/runner/.kube/config
KAFKA_REMOTE_BOOTSTRAP=kafka-bootstrap.homelab.ricsanfre.com
KAFKA_SCHEMA_REGISTRY=schema-registry.homelab.ricsanfre.com
SCHEMA_REGISTRY_PASSWORD=$(shell  kubectl get secret schema-registry-auth-secret -n kafka -o jsonpath='{.data.password}' | base64 --decode)

.PHONY: kafka-external-client kafka-avro-producer kafka-avro-consumer

default: kafka-external-client

# Uncomment this block if a private CA has been used to bootstrap Kafka instead Let's Encript certificate
# It obtains Cert-Manager root CA certificate (`root-secret`) used for bootstrapping Private PKI
# remote-kafka-client:
# 	kubectl get secret root-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 --decode > certs/ca.crt
# 	kubectl get secret root-secret -n cert-manager -o jsonpath='{.data.tls\.key}' | base64 --decode > certs/ca.key
# 	openssl pkcs12 -export -out certs/ca.p12 -inkey certs/ca.key -in certs/ca.crt -name "kafka-cluster-ca" -password pass:supers1cret0
# 	chmod 644 certs/ca.p12
# 	docker compose up -d

# If Let's encrypt certificate is used for Kafka, not need to include CA in Truststore 
kafka-external-client:
	docker compose up -d


# AVRO CLIENTS

# Preparing Python VirtualEnv
venv: .venv/touchfile
.venv/touchfile: pyproject.toml
	test -d .venv || uv venv
	. .venv/bin/activate; uv sync
	touch .venv/touchfile

kafka-avro-producer: venv
	@uv run avro_producer.py \
	-b ${KAFKA_REMOTE_BOOTSTRAP}:443 \
	-s https://${KAFKA_SCHEMA_REGISTRY} \
	-su client \
	-sp ${SCHEMA_REGISTRY_PASSWORD} \
	-t test-topic-avro \
	-m SCRAM-SHA-512 \
	--tls true \
	--user producer \
	--password supers1cret0

kafka-avro-consumer: venv
	@uv run avro_consumer.py \
	-b ${KAFKA_REMOTE_BOOTSTRAP}:443 \
	-su client \
	-s https://${KAFKA_SCHEMA_REGISTRY}  \
	-sp ${SCHEMA_REGISTRY_PASSWORD} \
	-t test-topic-avro \
	-m SCRAM-SHA-512 \
	-g test-consumer-group \
	--tls true \
	--user consumer \
	--password s1cret0