#!/usr/bin/env bash

cd /proto
start_dir=${START_DIR}
destination_host=${DESTINATION_HOST}
destination_port=${DESTINATION_PORT}
proxy_port=${PROXY_PORT}

tmp_registration_file=$(mktemp /tmp/registration_file-XXXXX)

# 1. compile all proto files
for current_dir in $(find ${start_dir} -type d); do
  if [[ -n $(find "${current_dir}" -maxdepth 1 -name "*.proto") ]]; then
    for current_proto_file in $(find ${current_dir} -maxdepth 1 -name "*.proto"); do
      protoc -I. \
        -I${GOPATH}/src \
        -I${GOPATH}/src/github.com/grpc-ecosystem/grpc-gateway/third_party/googleapis \
        --go_out=plugins=grpc:${GOPATH}/src \
        ${current_proto_file}

      #2. compile all gateways + yaml settings
      if [[ -n $(grep "service" ${current_proto_file}) ]]; then

        #2.1 Generate yaml file
        tmpfile=$(mktemp /tmp/http_rules-XXXX.yaml)

        #2.1.1 Get package name
        package_name=$(grep -Eo "^package .*;" ${current_proto_file} | cut -d" " -f2 | cut -d";" -f1)
        #2.1.2 Get service name
        service_name=$(grep -Eo "service .* \{" ${current_proto_file} | cut -d" " -f2)
        #2.1.3 Get method names
        methods=($(grep -Eo "rpc .*\(" ${current_proto_file} | cut -d" " -f2 | cut -d"(" -f1))

        #2.2 Write the head of file
        cat <<-EOF >${tmpfile}
type: google.api.Service
config_version: 3

http:
  rules:
EOF
        for method_name in "${methods[@]}"; do
          cat <<-EOF >>${tmpfile}
    - selector: ${package_name}.${service_name}.${method_name}
      post: /${service_name}/${method_name}
      body: "*"
EOF
        done

        #2.2 Use this file to generate Gateway
        protoc -I. \
          -I${GOPATH}/src \
          -I${GOPATH}/src/github.com/grpc-ecosystem/grpc-gateway/third_party/googleapis \
          --grpc-gateway_out=logtostderr=true,grpc_api_configuration=${tmpfile}:${GOPATH}/src \
          ${current_proto_file}

        #2.3 Add Registation in proxy file

        echo "$(dirname ${current_proto_file})|${service_name}" >>${tmp_registration_file}

        #rm "${tmpfile}"
        #echo "Service generated"
      fi
    done
  fi
done

echo "All Proto files converted in Go"

#3. make a proxy with all gateways
proxy_grpc_script=${PROXY_EXEC_FILE}
# First part
cat <<-EOF >${proxy_grpc_script}
package main

import (
  "context"
  "flag"
  "net/http"

  "github.com/golang/glog"
  "github.com/grpc-ecosystem/grpc-gateway/runtime"
  "google.golang.org/grpc"
EOF

# Imports
index=0
for service_row in $(cat ${tmp_registration_file}); do
  service_package=$(echo ${service_row} | cut -d"|" -f1)
  echo "gateway${index} \"${service_package}\"" >> ${proxy_grpc_script}
  index=$((index+1))
done

# Second part
cat <<-EOF >>${proxy_grpc_script}
)

var (
  // command-line options:
  // gRPC server endpoint
  grpcServerEndpoint = flag.String("grpc-server-endpoint",  "${destination_host}:${destination_port}", "gRPC server endpoint")
)

func run() error {
  ctx := context.Background()
  ctx, cancel := context.WithCancel(ctx)
  defer cancel()

  // Register gRPC server endpoint
  // Note: Make sure the gRPC server is running properly and accessible
  mux := runtime.NewServeMux()
  opts := []grpc.DialOption{grpc.WithInsecure()}
EOF

# Registation part
index=0
for service_row in $(cat ${tmp_registration_file}); do
  service_name=$(echo ${service_row} | cut -d"|" -f2)
  service_registration_name=Register${service_name}HandlerFromEndpoint
  echo "gateway${index}.${service_registration_name}(ctx, mux,  *grpcServerEndpoint, opts)" >> ${proxy_grpc_script}
  index=$((index+1))
done

# Last Part
cat <<-EOF >>${proxy_grpc_script}
// Start HTTP server (and proxy calls to gRPC server endpoint)
  return http.ListenAndServe(":${proxy_port}", mux)
}

func main() {
  flag.Parse()
  defer glog.Flush()

  if err := run(); err != nil {
    glog.Fatal(err)
  }
}
EOF

rm ${tmp_registration_file}
