.SILENT:
.PHONY: help

## This help screen
help:
	printf "Available targets:\n\n"
	awk '/^[a-zA-Z\-\_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")-1); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "%-15s %s\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)

## Build and push the Docker image of the leader election demo app to DockerHub
build:
	./cicd.sh build

## Create 3 kind clusters and deploy the deploy the leader election demo app to all of them
deploy:
	./cicd.sh deploy

## Demonstrate multi-cluster leader election works when killing the the current leader
test: deploy
	./cicd.sh test
