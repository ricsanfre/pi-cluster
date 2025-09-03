.PHONY: remote-kafka-client

default: remote-kafka-client

# Uncomment this block if a private CA has been used to bootstrap Kafka instead Let's Encript certificate
# It obtains Cert-Manager root CA certificate (`root-secret`) used for bootstrapping Private PKI
# remote-kafka-client:
# 	kubectl get secret root-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 --decode > certs/ca.crt
# 	kubectl get secret root-secret -n cert-manager -o jsonpath='{.data.tls\.key}' | base64 --decode > certs/ca.key
# 	openssl pkcs12 -export -out certs/ca.p12 -inkey certs/ca.key -in certs/ca.crt -name "kafka-cluster-ca" -password pass:supers1cret0
# 	chmod 644 certs/ca.p12
# 	docker compose up -d

# If Let's encrypt certificate is used for Kafka, not need to include CA in Truststore 
remote-kafka-client:
	docker compose up -d