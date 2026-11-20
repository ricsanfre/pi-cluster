FROM golang:1.27.4-alpine AS build
LABEL stage=builder

WORKDIR /k3s-mixins

COPY src/ .

RUN ls -la *

# Install required packages
RUN apk add git

# Install jsonnet and the jsonnet-bundler
RUN go install github.com/google/go-jsonnet/cmd/jsonnet@latest
RUN go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@latest

# Install gojsontoyaml
RUN go install github.com/brancz/gojsontoyaml@latest

# Install the mixins pinned in src/jsonnetfile.json.
# kube-prometheus and coredns-mixin are pinned; kubernetes-mixin tracks master
# because its newest tag lags master by months (see README.md).
RUN jb install

# RUN jsonnet main.jsonnet -J vendor > generated.json

# Create output directory for the manifest files
RUN mkdir templates

# Execute command to generate
RUN chmod +x generate.sh
RUN ./generate.sh

FROM scratch AS mixins
COPY --from=build /k3s-mixins/templates /