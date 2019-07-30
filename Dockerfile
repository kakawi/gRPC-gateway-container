from ubuntu

RUN apt-get update
RUN apt-get -y install wget git curl autoconf libtool g++ make

ENV GRPC_VERSION=1.16.0 \
        GRPC_JAVA_VERSION=1.16.1 \
        GRPC_WEB_VERSION=1.0.0 \
        PROTOBUF_VERSION=3.6.1 \
        PROTOBUF_C_VERSION=1.3.1 \
        PROTOC_GEN_DOC_VERSION=1.1.0 \
        OUTDIR=/out
RUN mkdir -p /protobuf && \
        curl -L https://github.com/google/protobuf/archive/v${PROTOBUF_VERSION}.tar.gz | tar xvz --strip-components=1 -C /protobuf
RUN git clone --depth 1 --recursive -b v${GRPC_VERSION} https://github.com/grpc/grpc.git /grpc && \
        rm -rf grpc/third_party/protobuf && \
        ln -s /protobuf /grpc/third_party/protobuf
RUN mkdir -p /grpc-java && \
        curl -L https://github.com/grpc/grpc-java/archive/v${GRPC_JAVA_VERSION}.tar.gz | tar xvz --strip-components=1 -C /grpc-java
RUN mkdir -p /grpc-web && \
        curl -L https://github.com/grpc/grpc-web/archive/${GRPC_WEB_VERSION}.tar.gz | tar xvz --strip-components=1 -C /grpc-web
RUN mkdir -p /protobuf-c && \
        curl -L https://github.com/protobuf-c/protobuf-c/releases/download/v${PROTOBUF_C_VERSION}/protobuf-c-${PROTOBUF_C_VERSION}.tar.gz | tar xvz --strip-components=1 -C /protobuf-c
RUN cd /protobuf && \
        autoreconf -f -i -Wall,no-obsolete && \
        ./configure --prefix=/usr --enable-static=no && \
        make -j2 && make install
RUN cd grpc && \
        make -j2 plugins
RUN cd /grpc-java/compiler/src/java_plugin/cpp && \
        g++ \
        -I. -I/protobuf/src \
        *.cpp \
        -L/protobuf/src/.libs \
        -lprotoc -lprotobuf -lpthread --std=c++0x -s \
        -o protoc-gen-grpc-java
RUN cd /protobuf && \
        make install DESTDIR=${OUTDIR}
RUN cd /grpc && \
        make install-plugins prefix=${OUTDIR}/usr
RUN cd /grpc-java/compiler/src/java_plugin/cpp && \
        install -c protoc-gen-grpc-java ${OUTDIR}/usr/bin/
RUN cd /grpc-web/javascript/net/grpc/web && \
        make && \
        install protoc-gen-grpc-web ${OUTDIR}/usr/bin/
RUN find ${OUTDIR} -name "*.a" -delete -or -name "*.la" -delete

RUN mkdir -p /protobuf/google/protobuf && \
        for f in any duration descriptor empty struct timestamp wrappers; do \
        curl -L -o /protobuf/google/protobuf/${f}.proto https://raw.githubusercontent.com/google/protobuf/master/src/google/protobuf/${f}.proto; \
        done && \
        mkdir -p /protobuf/google/api && \
        for f in annotations http; do \
        curl -L -o /protobuf/google/api/${f}.proto https://raw.githubusercontent.com/grpc-ecosystem/grpc-gateway/master/third_party/googleapis/google/api/${f}.proto; \
        done && \
        mkdir -p /protobuf/github.com/gogo/protobuf/gogoproto && \
        curl -L -o /protobuf/github.com/gogo/protobuf/gogoproto/gogo.proto https://raw.githubusercontent.com/gogo/protobuf/master/gogoproto/gogo.proto && \
        mkdir -p /protobuf/github.com/mwitkow/go-proto-validators && \
        curl -L -o /protobuf/github.com/mwitkow/go-proto-validators/validator.proto https://raw.githubusercontent.com/mwitkow/go-proto-validators/master/validator.proto && \
        mkdir -p /protobuf/github.com/lyft/protoc-gen-validate/gogoproto && \
        mkdir -p /protobuf/github.com/lyft/protoc-gen-validate/validate && \
        curl -L -o /protobuf/github.com/lyft/protoc-gen-validate/gogoproto/gogo.proto https://raw.githubusercontent.com/lyft/protoc-gen-validate/master/gogoproto/gogo.proto && \
        curl -L -o /protobuf/github.com/lyft/protoc-gen-validate/validate/validate.proto https://raw.githubusercontent.com/lyft/protoc-gen-validate/master/validate/validate.proto && \
        chmod a+x /usr/bin/protoc

#Install Go
RUN wget https://dl.google.com/go/go1.12.7.linux-amd64.tar.gz
RUN tar -xvf go1.12.7.linux-amd64.tar.gz
RUN mv go /usr/local

RUN mkdir -p /gocode/src
RUN mkdir /gocode/bin
ENV GOROOT /usr/local/go
ENV GOPATH /gocode

ENV PATH "$PATH:/usr/local/go/bin:$GOPATH/bin"
ENV PATH "$PATH:$GOROOT/bin:$GOPATH/bin"
RUN go get -u google.golang.org/grpc
RUN go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway
RUN go get -u github.com/golang/protobuf/protoc-gen-go

WORKDIR /
ADD ./generate_proxy_grpc.sh /
ADD ./watcher.sh /

RUN chmod +x /generate_proxy_grpc.sh
RUN chmod +x /watcher.sh

ENV PROXY_EXEC_FILE=/proxy_grpc_generated.go
ENV START_DIR=.
ENV DESTINATION_HOST=localhost
ENV DESTINATION_PORT=8087
ENV PROXY_PORT=9031

RUN apt -y install inotify-tools

CMD ["/watcher.sh"]
#ENTRYPOINT ["/bin/bash"]
