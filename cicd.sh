# This script can be used by CI/CD (or manually) to build, deploy and test
# the multi-cluster leader election demo.
#
# Usage: ./cicd.sh <action>
#
# The action is one of: build, deploy, test
#
# There is a Makefile that makes it easy to discover and invoke

VERSION=0.1
IMAGE="g1g1/multi-cluster-leader-election:${VERSION}"

function build() {
  echo "building $IMAGE"
	echo $DOCKERHUB_PASSWORD | docker login -u $DOCKERHUB_USERNAME --password-stdin
	docker build . -t $IMAGE
	docker push $IMAGE
}

function deploy() {
  echo "deploying $IMAGE"

  echo --- preparing three kind clusters: Napoleon, Cleopatra and Stalin
  for cluster in napoleon, cleopatra and stalin; do
    echo prepare $cluster cluster...
    kind create cluster --name $cluster
  done

  echo --- deploying leader-elector to the clusters
  for cluster in napoleon, cleopatra and stalin; do
    echo deploying leader-elector to $cluster cluster
  done
}

function test() {
  echo checking current leader

  echo kill current leader

  echo verfying new leader was elected
}

# Run the function that was passed as argument
$1