#!/usr/bin/env python

import argparse
import os
from uuid import uuid4

from six.moves import input

from confluent_kafka import Producer
from confluent_kafka.serialization import StringSerializer, SerializationContext, MessageField
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer


class User(object):
    """
    User record

    Args:
        name (str): User's name

        favorite_number (int): User's favorite number

        favorite_color (str): User's favorite color

        address(str): User's address; confidential
    """

    def __init__(self, name, address, favorite_number, favorite_color):
        self.name = name
        self.favorite_number = favorite_number
        self.favorite_color = favorite_color
        # address should not be serialized, see user_to_dict()
        self._address = address


def user_to_dict(user, ctx):
    """
    Returns a dict representation of a User instance for serialization.

    Args:
        user (User): User instance.

        ctx (SerializationContext): Metadata pertaining to the serialization
            operation.

    Returns:
        dict: Dict populated with user attributes to be serialized.
    """

    # User._address must not be serialized; omit from dict
    return dict(name=user.name,
                favorite_number=user.favorite_number,
                favorite_color=user.favorite_color)


def delivery_report(err, msg):
    """
    Reports the failure or success of a message delivery.

    Args:
        err (KafkaError): The error that occurred on None on success.

        msg (Message): The message that was produced or failed.

    Note:
        In the delivery report callback the Message.key() and Message.value()
        will be the binary format as encoded by any configured Serializers and
        not the same object that was passed to produce().
        If you wish to pass the original object(s) for key and value to delivery
        report callback we recommend a bound callback or lambda where you pass
        the objects along.
    """

    if err is not None:
        print("Delivery failed for User record {}: {}".format(msg.key(), err))
        return
    print('User record {} successfully produced to {} [{}] at offset {}'.format(
        msg.key(), msg.topic(), msg.partition(), msg.offset()))

def sasl_conf(args):
    sasl_mechanism = args.sasl_mechanism.upper()

    sasl_conf = {'sasl.mechanism': sasl_mechanism}

    if args.enab_tls:
        sasl_conf.update({'security.protocol': 'SASL_SSL'})
        if args.ca_cert is not None:
            sasl_conf.update({'ssl.ca.location': args.ca_cert})    
    else:    
        sasl_conf.update({'security.protocol': 'SASL_PLAINTEXT'})


    if sasl_mechanism != 'GSSAPI':
        sasl_conf.update({'sasl.username': args.user_principal,
                          'sasl.password': args.user_secret})

    if sasl_mechanism == 'GSSAPI':
        sasl_conf.update({'sasl.kerberos.service.name', args.broker_principal,
                          # Keytabs are not supported on Windows. Instead the
                          # the logged on user's credentials are used to
                          # authenticate.
                          'sasl.kerberos.principal', args.user_principal,
                          'sasl.kerberos.keytab', args.user_secret})
    return sasl_conf



def main(args):
    topic = args.topic
    is_specific = args.specific == "true"

    if is_specific:
        schema = "user_specific.avsc"
    else:
        schema = "user_generic.avsc"

    path = os.path.realpath(os.path.dirname(__file__))
    with open(f"{path}/avro/{schema}") as f:
        schema_str = f.read()

    schema_registry_conf = {'url': args.schema_registry}

    #Adding SchemaRegistry credentials
    if args.registry_password is not None and args.registry_password is not None:
        schema_registry_conf.update({'basic.auth.user.info': f"{args.registry_user}:{args.registry_password}"})

    if 'https' in args.schema_registry and args.ca_cert is not None:
        print("Using CA cert at {} to connect to schema registry".format(args.ca_cert))
        schema_registry_conf.update({'ssl.ca.location': args.ca_cert})
    schema_registry_client = SchemaRegistryClient(schema_registry_conf)

    avro_serializer = AvroSerializer(schema_registry_client,
                                     schema_str,
                                     user_to_dict)

    string_serializer = StringSerializer('utf_8')

    producer_conf = {'bootstrap.servers': args.bootstrap_servers}
    producer_conf.update(sasl_conf(args))

    producer = Producer(producer_conf)

    print("Producing user records to topic {}. ^C to exit.".format(topic))
    while True:
        # Serve on_delivery callbacks from previous calls to produce()
        producer.poll(0.0)
        try:
            user_name = input("Enter name: ")
            user_address = input("Enter address: ")
            user_favorite_number = int(input("Enter favorite number: "))
            user_favorite_color = input("Enter favorite color: ")
            user = User(name=user_name,
                        address=user_address,
                        favorite_color=user_favorite_color,
                        favorite_number=user_favorite_number)
            producer.produce(topic=topic,
                             key=string_serializer(str(uuid4())),
                             value=avro_serializer(user, SerializationContext(topic, MessageField.VALUE)),
                             on_delivery=delivery_report)
        except KeyboardInterrupt:
            break
        except ValueError:
            print("Invalid input, discarding record...")
            continue

    print("\nFlushing records...")
    producer.flush()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="AvroSerializer example")
    parser.add_argument('-b', dest="bootstrap_servers", required=True,
                        help="Bootstrap broker(s) (host[:port])")
    parser.add_argument('-s', dest="schema_registry", required=True,
                        help="Schema Registry (http(s)://host[:port]"),
    parser.add_argument('-su', dest="registry_user", default=None,
                        help="Schema Registry user")
    parser.add_argument('-sp', dest="registry_password", default=None,
                        help="Schema Registry password")
    parser.add_argument('-t', dest="topic", default="example_serde_avro",
                        help="Topic name")
    parser.add_argument('-p', dest="specific", default="true",
                        help="Avro specific record")
    parser.add_argument('-m', dest="sasl_mechanism", default='PLAIN',
                        choices=['GSSAPI', 'PLAIN',
                                 'SCRAM-SHA-512', 'SCRAM-SHA-256'],
                        help="SASL mechanism to use for authentication."
                             "Defaults to PLAIN")
    parser.add_argument('--tls', dest="enab_tls", default=False)
    parser.add_argument('--cacert',dest="ca_cert", default=None, 
                        help="Path to CA certificate for TLS authentication")
    parser.add_argument('--user', dest="user_principal", required=True,
                        help="Username")
    parser.add_argument('--password', dest="user_secret", required=True,
                        help="Password for PLAIN and SCRAM, or path to"
                             " keytab (ignored on Windows) if GSSAPI.")

    main(parser.parse_args())
