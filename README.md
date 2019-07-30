https://cloud.docker.com/u/kakawi/repository/docker/kakawi/grpc-gateway-container

docker run -d --publish 9031:9031 -it -e START_DIR=<DIR_FOR_PROTO_FILES> -v <PROTO_FILES>:/proto/<DIR_FOR_PROTO_FILES> kakawi/grpc-gateway-container

if you use on Mac add parameter
`-e DESTINATION_HOST=host.docker.internal`

## Parameters
START_DIR - [.]

DESTINATION_HOST - [localhost]

DESTINATION_PORT - [8087]

PROXY_PORT - [9031]
