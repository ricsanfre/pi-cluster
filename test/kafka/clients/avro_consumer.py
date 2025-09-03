#!/usr/bin/env python

import argparse
import os

from confluent_kafka import Consumer
from confluent_kafka.serialization import SerializationContext, MessageField
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer


class User(object):
    """
    User record

    Args:
        name (str): User's name

        favorite_number (int): User's favorite number

        favorite_color (str): User's favorite color
    """

    def __init__(self, name=None, favorite_number=None, favorite_color=None):
        self.name = name
        self.favorite_number = favorite_number
        self.favorite_color = favorite_color


def dict_to_user(obj, ctx):
    """
    Converts object literal(dict) to a User instance.

    Args:
        obj (dict): Object literal(dict)

        ctx (SerializationContext): Metadata pertaining to the serialization
            operation.
    """

    if obj is None:
        return None

    return User(name=obj['name'],
                favorite_number=obj['favorite_number'],
                favorite_color=obj['favorite_color'])

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

    sr_conf = {'url': args.schema_registry}
    if 'https' in args.schema_registry and args.ca_cert is not None:
        sr_conf.update({'ssl.ca.location': args.ca_cert})
       
    schema_registry_client = SchemaRegistryClient(sr_conf)

    avro_deserializer = AvroDeserializer(schema_registry_client,
                                         schema_str,
                                         dict_to_user)

    consumer_conf = {'bootstrap.servers': args.bootstrap_servers,
                     'group.id': args.group,
                     'auto.offset.reset': "earliest"}
    consumer_conf.update(sasl_conf(args))

    consumer = Consumer(consumer_conf)
    consumer.subscribe([topic])

    while True:
        try:
            # SIGINT can't be handled when polling, limit timeout to 1 second.
            msg = consumer.poll(1.0)
            if msg is None:
                continue

            user = avro_deserializer(msg.value(), SerializationContext(msg.topic(), MessageField.VALUE))
            if user is not None:
                print("User record {}: name: {}\n"
                      "\tfavorite_number: {}\n"
                      "\tfavorite_color: {}\n"
                      .format(msg.key(), user.name,
                              user.favorite_number,
                              user.favorite_color))
        except KeyboardInterrupt:
            break

    consumer.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="AvroDeserializer example")
    parser.add_argument('-b', dest="bootstrap_servers", required=True,
                        help="Bootstrap broker(s) (host[:port])")
    parser.add_argument('-s', dest="schema_registry", required=True,
                        help="Schema Registry (http(s)://host[:port]")
    parser.add_argument('-t', dest="topic", default="example_serde_avro",
                        help="Topic name")
    parser.add_argument('-g', dest="group", default="example_serde_avro",
                        help="Consumer group")
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
