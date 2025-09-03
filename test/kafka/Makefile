.EXPORT_ALL_VARIABLES:

KAFKA_REMOTE_BOOTSTRAP=kafka-bootstrap.homelab.ricsanfre.com
KAFKA_SCHEMA_REGISTRY=schema-registry.homelab.ricsanfre.com

.PHONY: kafka-setup kafka-k8s-clients kafka-k8s-producer kafka-k8s-consumer kafka-external-client kafka-external-producer kafka-external-consumer kafka-avro-clients kafka-avro-producer

default:
	kafka-setup


kafka-setup:
	kubectl kustomize kubernetes | kubectl apply -f -


kafka-k8s-client:
	kubectl run kafka-clients --restart='Never' --image quay.io/strimzi/kafka:0.47.0-kafka-4.0.0 --namespace kafka --command -- sleep infinity
	kubectl cp clients/properties/producer_plain.properties kafka/kafka-clients:/tmp/producer.properties
	kubectl cp clients/properties/consumer_plain.properties kafka/kafka-clients:/tmp/consumer.properties

kafka-k8s-producer:
	kubectl exec -it kafka-clients --namespace kafka -- bin/kafka-console-producer.sh \
	--producer.config clients/tmp/producer.properties \
	--bootstrap-server cluster-kafka-bootstrap:9092 \
	--topic test-topic

kafka-k8s-consumer:
	kubectl exec -it kafka-clients --namespace kafka -- bin/kafka-console-consumer.sh \
	--consumer.config clients/tmp/consumer.properties \
	--bootstrap-server cluster-kafka-bootstrap:9092 \
	--topic test-topic \
	--group test-consumer-group --from-beginning

kafka-external-client:
	cd clients && $(MAKE) $@

kafka-external-producer:
	docker exec -it kafka-client bin/kafka-console-producer.sh \
	--producer.config /tmp/properties/producer_ssl.properties \
	--bootstrap-server ${KAFKA_REMOTE_BOOTSTRAP}:443 \
	--topic test-topic

kafka-external-consumer:
	docker exec -it kafka-client bin/kafka-console-consumer.sh \
	--consumer.config /tmp/properties/consumer_ssl.properties \
	--bootstrap-server ${KAFKA_REMOTE_BOOTSTRAP}:443 \
	--topic test-topic \
	--group test-consumer-group --from-beginning

remote-kafka-command:
	docker exec -it kafka-client bin/command.sh \
	--config /tmp/properties/admin_ssl.properties \
	--bootstrap-server ${KAFKA_REMOTE_BOOTSTRAP}:443 \

show-kafka-acls:
	docker exec -it kafka-client bin/kafka-acls.sh \
	--command-config /tmp/properties/admin_ssl.properties \
	--bootstrap-server ${KAFKA_REMOTE_BOOTSTRAP}:443 \
	--list	

show-kafka-topics:
	docker exec -it kafka-client bin/kafka-topics.sh \
	--command-config /tmp/properties/admin_ssl.properties \
	--bootstrap-server ${KAFKA_REMOTE_BOOTSTRAP}:443 \
	--list

kafka-avro-producer:
	docker exec -it kafka-client-avro python3 avro_producer.py \
	-b kafka-bootstrap.local.test:443 \
	-s http://apicurio-app.local.test/apis/ccompat/v7 \
	-t test-topic-avro \
	-m SCRAM-SHA-512 \
	--tls true \
	--cacert /tmp/certs/ca.crt \
	--user producer \
	--password supers1cret0

kafka-avro-consumer:
	docker exec -it kafka-client-avro python3 avro_consumer.py \
	-b kafka-bootstrap.local.test:443 \
	-s http://apicurio-app.local.test/apis/ccompat/v7 \
	-t test-topic-avro \
	-m SCRAM-SHA-512 \
	-g test-consumer-group \
	--tls true \
	--cacert /tmp/certs/ca.crt \
	--user consumer \
	--password s1cret0

kafka-avro-producer-2:
	docker exec -it kafka-client-avro python3 avro_producer.py \
	-b ${KAFKA_REMOTE_BOOTSTRAP}:443 \
	-s https://${KAFKA_SCHEMA_REGISTRY} \
	-t test-topic-avro \
	-m SCRAM-SHA-512 \
	--tls true \
	--user producer \
	--password supers1cret0

kafka-avro-consumer-2:
	docker exec -it kafka-client-avro python3 avro_consumer.py \
	-b ${KAFKA_REMOTE_BOOTSTRAP}:443 \
	-s https://${KAFKA_SCHEMA_REGISTRY}  \
	-t test-topic-avro \
	-m SCRAM-SHA-512 \
	-g test-consumer-group \
	--tls true \
	--user consumer \
	--password s1cret0