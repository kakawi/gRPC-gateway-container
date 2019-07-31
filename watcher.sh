#!/usr/bin/env bash

proxy_grpc_script=/proxy_grpc_generated.go

while true; do
    if [[ -n ${proxy_pid} ]]; then
        echo "Stopping proxy..."
        pkill -P ${proxy_pid}
        echo "Proxy stopped"
    fi

    echo "Generate proxy script"
    /generate_proxy_grpc.sh ${proxy_grpc_script}
    echo "Proxy script generated"

    echo "Starting Proxy..."
    go run ${proxy_grpc_script} &
    proxy_pid=$!
    echo "Proxy has started"

    echo "PID: "${proxy_pid}

    # Loop until any *.proto file not changed
    while true; do
        RES=$(inotifywait -e modify -e create -e delete -r /proto/${START_DIR}/* | grep "\.proto")
        # If the `inotifywait` was terminated by a signal, then break the loop
        test $? -gt 128 && exit
        if [ -n "${RES}" ]
        then
            break
        fi
    done

done
