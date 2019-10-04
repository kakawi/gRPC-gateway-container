#!/usr/bin/env bash

proxy_grpc_script=$1 # result file
start_dir=${START_DIR}
filter=${FILTER}
destination_host=${DESTINATION_HOST}
destination_port=${DESTINATION_PORT}
proxy_port=${PROXY_PORT}
debug_mode=${DEBUG_MODE}

# Does debug mode turn on ?
case "$debug_mode" in
1|true|yes|on)
    verbose=1
esac

# Create additional descriptors
if [ "$verbose" = 1 ]; then
    echo "DEBUG mode is turned ON"
    exec 4>&2 3>&1
else
    exec 4>/dev/null 3>/dev/null
fi

# Functions for verbose output
to_stdout() {
    echo >&3 $1
}

to_stderr() {
    echo >&4 $1
}

# In this file will be collected information from first part and use it in second part
tmp_registration_file=$(mktemp)

# `protoc` can't handle relatives path correctly, so we should start from a proper folder
# all our *.proto files should be under `/proto` folder
cd /proto

to_stdout "Filter - "${filter}
# `protoc` can't pass recursively through folders to find all *.proto files,
# so we do it instead of it
for current_dir in $(find ./${start_dir} -type d); do
  to_stdout "Current Directory - "${current_dir}
  # Filter
  if [[ ! -z ${filter} ]] && [[ $(expr "${current_dir}" : ${filter}) -eq 0 ]]; then
    continue
  fi
  to_stdout "Filtered Directory - "${current_dir}
  # handle only *.proto files in current folder (-maxdepth 1)
  if [[ -n $(find "${current_dir}" -maxdepth 1 -name "*.proto") ]]; then
    for current_proto_file in $(find ${current_dir} -maxdepth 1 -name "*.proto"); do
    to_stdout "Current Proto File - "${current_proto_file}
      # 1. compile `*.proto` file in *.go file and put in `${GOPATH}/src` folder
      protoc -I. \
        -I${GOPATH}/src \
        -I${GOPATH}/src/github.com/grpc-ecosystem/grpc-gateway/third_party/googleapis \
        --go_out=plugins=grpc:${GOPATH}/src \
        ${current_proto_file}

      # 2. if this `*.proto` file contains a work `service`, so we should also create
      # proxy (gateway) for this service
      # Ref: https://github.com/grpc-ecosystem/grpc-gateway#usage
      if [[ -n $(grep "service.*{" ${current_proto_file}) ]]; then
        to_stdout "File with SERVICE - "${current_proto_file}
        #2.1 - Generate Proxy
        # To generate proxy we should add `google.api.http` annotation, but we don't want to add them
        # in proto files, so we can create gRPC Service Configuration file
        # Ref: https://cloud.google.com/endpoints/docs/grpc/grpc-service-config
        grpc_service_configuration_file=$(mktemp)

        # Gather names to generate gRPC Service Configuration file
        # Every service will be have such http rules
        # /<SERVICE_NAME>/<METHOD_NAME>
        #2.1.1 Get package name
        package_name=$(grep -Eo "^package .*;" ${current_proto_file} | cut -d" " -f2 | cut -d";" -f1)
        to_stdout "Package Name - "${package_name}
        #2.1.2 Get service name
        service_name=$(grep -Eo "service .* \{" ${current_proto_file} | cut -d" " -f2)
        #2.1.3 Get method names
        methods=($(grep -Eo "rpc .*\(" ${current_proto_file} | cut -d" " -f2 | cut -d"(" -f1))

        #2.1.4 Write the head of file
        cat <<-EOF >${grpc_service_configuration_file}
type: google.api.Service
config_version: 3

http:
  rules:
EOF
        #2.1.5 Add http rules
        for method_name in "${methods[@]}"; do
          cat <<-EOF >>${grpc_service_configuration_file}
    - selector: ${package_name}.${service_name}.${method_name}
      post: /${service_name}/${method_name}
      body: "*"
EOF
        done

        #2.2 Use this gRPC Service Configuration to generate Proxy (*.gw.go file) and put it under `${GOPATH}/src`
        protoc -I. \
          -I${GOPATH}/src \
          -I${GOPATH}/src/github.com/grpc-ecosystem/grpc-gateway/third_party/googleapis \
          --grpc-gateway_out=logtostderr=true,grpc_api_configuration=${grpc_service_configuration_file}:${GOPATH}/src \
          ${current_proto_file}

        #2.3 Save `dirname of proto file`|`service name` in separate file to use it in next Go file
        # which will start all proxies altogether
        service_package=$(dirname ${current_proto_file} | cut -c 3-)
        to_stdout "Service Package temp - "${service_package}
        echo "${service_package}|${service_name}" >>${tmp_registration_file}

        echo "Service ${service_name} generated"
      fi
    done
  fi
done

echo "All Proto files converted in Go"

# 3. Generate Go script which will start all Proxies altogether
# 3.1 Add head of file
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

# 3.2 Add imports as template `gateway<INDEX> <SERVICE_DIR>`
index=0
for service_row in $(cat ${tmp_registration_file}); do
  service_package=$(echo ${service_row} | cut -d"|" -f1)
  echo "gateway${index} \"${service_package}\"" >> ${proxy_grpc_script}
  index=$((index+1))
done

# 3.3 Add second part with `destination_host` and `destination_port`
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

# 3.4 Register all proxies like:
# gateway<INDEX>.<SERVICE_NAME>HandlerFromEndpoint(ctx, mux,  *grpcServerEndpoint, opts)
index=0
for service_row in $(cat ${tmp_registration_file}); do
  service_name=$(echo ${service_row} | cut -d"|" -f2)
  service_registration_name=Register${service_name}HandlerFromEndpoint
  echo "gateway${index}.${service_registration_name}(ctx, mux,  *grpcServerEndpoint, opts)" >> ${proxy_grpc_script}
  index=$((index+1))
done

# 3.5 Add final part with `proxy_port`
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
