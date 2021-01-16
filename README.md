# Golang RabbitMQ to Kafka pipeline with zero lines of Golang!

I think that for a big percentage of cases, ETL pipelines are a solved problem. Unless you have very special needs, there are many tools in the market that can remove the hassle of setting up irrelevant minutia, and let you focus on the business logic instead, because anyone can create a function that connects to a Rabbit MQ exchange, but only you can work on the task of how your business logic should handle the received messages. However, I am aware of the value that "reinventing the wheel" might have in some business aspects, when the off the shelf tools won't cut it. But in the event that off the shelf tools are good for you, let me introduce you to [Benthos](https://www.benthos.dev/).

![Captura de pantalla 2021-01-16 a las 19.40.18](https://dev-to-uploads.s3.amazonaws.com/i/t70wz42de323klyv34ov.png)
 
## What is Benthos

Benthos it's a tool that can perform streaming ETL tasks, so to speak, it can grab your stream source (Extract), apply some transformations (Transform) and send it to your desired sink/destination (Load). It's written in Go, and sorry for the clickbait title, sure it has a lot of Golang lines of code! But the whole point of this exercise is that it doesn't require you to write any in order to set your pipelines. It uses a yaml config file which is executed by the main binary. 

Benthos handles for you some boring stuff such as parallelism, or creation of metrics in Prometheus, Influx, Cloudwatch, etc.. We are going to see how it behaves with the following task:

- Getting a message from a Rabbit queue
- Manipulating the payload
- Sending the new payload to a Kafka topic

## Getting started

For this exercise I have needed a docker-compose file so I could test Rabbit and Kafka in my local environment. If you were to deploy a Benthos job in an environment with an already existing instance of Rabbit and Kafka, you wouldn't worry about this, but let me share my `docker-compose.yml` file just in case

```yml
version: "3.6"
services:
  
  rabbitmq:
    image: 'rabbitmq:3.7-management-alpine'
    hostname: rabbitmq
    expose:
      - 5672
      - 15672
    ports:
      - "5672:5672"
      - "15672:15672"
    environment:
      RABBITMQ_DEFAULT_USER: "guest"
      RABBITMQ_DEFAULT_PASS: "guest"
   

  zoo1:
    image: zookeeper:3.4.9
    hostname: zoo1
    ports:
      - "2181:2181"
    environment:
        ZOO_MY_ID: 1
        ZOO_PORT: 2181
        ZOO_SERVERS: server.1=zoo1:2888:3888
    

  kafka1:
    image: confluentinc/cp-kafka:5.5.1
    hostname: kafka1
    ports:
      - "9091:9091"
    environment:
      KAFKA_ADVERTISED_LISTENERS: LISTENER_DOCKER_INTERNAL://kafka1:19091,LISTENER_DOCKER_EXTERNAL://${DOCKER_HOST_IP:-127.0.0.1}:9091
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: LISTENER_DOCKER_INTERNAL:PLAINTEXT,LISTENER_DOCKER_EXTERNAL:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: LISTENER_DOCKER_INTERNAL
      KAFKA_ZOOKEEPER_CONNECT: "zoo1:2181"
      KAFKA_BROKER_ID: 1
      KAFKA_LOG4J_LOGGERS: "kafka.controller=INFO,kafka.producer.async.DefaultEventHandler=INFO,state.change.logger=INFO"
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
    depends_on:
      - zoo1

  kafdrop:
    image: obsidiandynamics/kafdrop
    restart: "no"
    ports:
      - "9000:9000"
    environment:
      KAFKA_BROKERCONNECT: "kafka1:19091"
    depends_on:
      - kafka1

  benthos:
    image: jeffail/benthos
    expose:
      - 4195
    ports:
      - "4195:4195"
    volumes:
      - ./pipeline:/pipeline
```

Let it start as long as needed, Rabbit is notoriously slow starting off. In the meantime let's create our Benthos pipeline. 

## The pipeline

You might have seen how in the previous docker compose file we mounted `./pipeline:/pipeline` in the Benthos image. This is just because that's where I am going to store my pipeline file. Feel free to mount a different directory if you need. 

So here are the contents of `pipeline/benthos.yml`

```yml
input:
  amqp_0_9:
    url: amqp://guest:guest@rabbitmq:5672
    queue: "ruben"

pipeline:
  processors:
    - sleep:
        duration: 500ms
    - bloblang: |
        root.original_event = this
        root.new_attr = "abc"
        root.new_attr2 = 123

output:
  kafka:
    addresses:
      - kafka1:19091
    topic: ruben
    client_id: benthos_kafka_output
    key: ""
    partitioner: fnv1a_hash
    compression: none
    static_headers: {}
    max_in_flight: 1
    batching:
      count: 0
      byte_size: 0
      period: ""
      check: ""
```

The input and output sections are self explanatory, they just define the configuration of the brokers we are using. The middle section (`pipeline`) is a bit more involved, because it requires the usage of the custom Benthos components to manipulate messages. See [all the available processors here](https://www.benthos.dev/docs/components/processors/about)

In my case, I am using the `bloblang` processor. You can see the details [here.](https://www.benthos.dev/docs/guides/bloblang/about) I am getting the input messages and applying a manipulation to their payload. 

So that's it, that's the pipeline. I understand this is a toy example, but if you look at the documentation you can see how Benthos seems to be ready to tackle pretty serious cases. 

## Running the example

Let's start with Rabbit. I didn't really add a custom json configuration to this docker compose stack, so there are no custom queues when initializing. We can simply go to http://0.0.0.0:15672/#/queues and create one (in my example, it's called `ruben`, as you can see in the `benthos.yml` file)

![Captura de pantalla 2021-01-16 a las 19.43.12](https://dev-to-uploads.s3.amazonaws.com/i/rffqcqtnsw51kmaawvnl.png)
 

Now we can do the same in Kafka. Open Kafdrop at http://0.0.0.0:9000/topic/create and create a topic (I also named it `ruben`)

![Captura de pantalla 2021-01-16 a las 19.44.17](https://dev-to-uploads.s3.amazonaws.com/i/9qsmn3znjd6fifqfenaf.png)
 
Now we can now run Benthos with our config file:

```shell
docker-compose run benthos -c ./pipeline/benthos.yml
```

If everything goes well, Benthos will start listening. Now, 
send a message (or as many as you want) via the Rabbit interface. Remember that your processor in Benthos is now ready to handle json objects. 

![Captura de pantalla 2021-01-16 a las 19.47.47](https://dev-to-uploads.s3.amazonaws.com/i/o4d8601lkoimixs4lrck.png)
 

Go to the Kafdrop interface and observe your messages arriving. Indeed, you have the original message, plus the two extra attributes that we have defined in our pipeline. 

![Captura de pantalla 2021-01-16 a las 19.48.51](https://dev-to-uploads.s3.amazonaws.com/i/lscpd6rj0k11jts8e0jw.png)
 

## Conclusion

While perhaps it doesn't match everyone's use case, Benthos looks like a pretty nice and easy to use alternative to create ETL pipelines in the Golang universe. 



