FROM golang:1.18 AS builder

WORKDIR /build

ADD go.mod  go.mod
ADD go.sum  go.sum
ADD main.go main.go

# Update
RUN apt-get --allow-releaseinfo-change update && apt upgrade -y

# Fetch dependencies
RUN go mod download all

# Build image as a truly static Go binary
RUN CGO_ENABLED=0 GOOS=linux go build -o /leader_elector -a -tags netgo -ldflags '-s -w' .

FROM scratch
MAINTAINER Gigi Sayfan <the.gigi@gmail.com>
COPY --from=builder /leader_elector /leader_elector
ENTRYPOINT ["/leader_elector"]
