# Gateway for gRPC + protobuf through REST
This project is created for development/test process.
gRPC + protofuf work with binary protocol, so we can't use Postman to invoke any endpoint.
To do it we should make a proxy and run.
This application create proxies for all **.proto** files and run them.

# Example
There is **/example/my_service.proto**
```
syntax = "proto3";
package example;
message StringMessage {
  string value = 1;
}

service YourService {
  rpc Echo(StringMessage) returns (StringMessage) {}
}
```

We start
On Linux
```
docker run -d --net=host -it -e START_DIR=example -v /example:/proto/example kakawi/grpc-gateway-container
```
On Mac
```
docker run -d --publish 9031:9031 -it -e START_DIR=example -e DESTINATION_HOST=host.docker.internal -v /example:/proto/example kakawi/grpc-gateway-container
```

And after it we can make a **POST** call through Postman on endpoint
```
http://localhost:9031/YourService/Echo

{
  "value": "Hello World"
}
```

## Start container
docker run -d --net=host -it -e START_DIR=<DIR_FOR_PROTO_FILES> -v <PROTO_FILES>:/proto/ kakawi/grpc-gateway-container

P.S. if you use Mac delete `--net=host` parameter and add parameters
`--publish 9031:9031 -e DESTINATION_HOST=host.docker.internal`

### Parameters
START_DIR - [.] directory where script will look for **.proto** files

DESTINATION_HOST - [localhost]

DESTINATION_PORT - [8087]

PROXY_PORT - [9031]

FILTER - [] more specific reqex for directory where to look for **.proto** files

DEBUG_MODE - [off]

## Docker Hub: 
https://cloud.docker.com/u/kakawi/repository/docker/kakawi/grpc-gateway-container
