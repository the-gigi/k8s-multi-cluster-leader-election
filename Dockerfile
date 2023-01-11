FROM --platform=linux/amd64 golang:1.19 AS builder

WORKDIR /build

ADD go.mod  go.mod
ADD main.go main.go

# Update
RUN apt-get --allow-releaseinfo-change update && apt upgrade -y

# Fetch dependencies
RUN go mod tidy &&  \
    go mod download all

# Build image as a truly static Go binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /leader_elector -a -tags netgo -ldflags '-s -w' .

FROM --platform=linux/amd64 gcr.io/distroless/base-debian11
MAINTAINER Gigi Sayfan <the.gigi@gmail.com>
COPY --from=builder /leader_elector /leader_elector
ENTRYPOINT ["/leader_elector"]
