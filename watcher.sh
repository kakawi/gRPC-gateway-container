#!/usr/bin/env bash

/generate_proxy_grpc.sh

proxy_grpc_script=${PROXY_EXEC_FILE}
#4. start it
echo "Starting Proxy..."
go run ${proxy_grpc_script} &
proxy_pid=$!
echo "Proxy has started"

echo ${proxy_pid}

while true; do
    RES=$(inotifywait -e modify -e create -e delete -r /proto/${START_DIR}/* | grep "\.proto")
    if [ -n "${RES}" ]
    then
        pkill -P ${proxy_pid}
        /generate_proxy_grpc.sh

        echo "Restarting Proxy..."
        go run ${proxy_grpc_script} &
        proxy_pid=$!
        echo "Proxy has restarted"
    fi
done
