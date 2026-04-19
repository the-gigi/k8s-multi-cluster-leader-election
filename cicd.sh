#!/usr/bin/env zsh

# This script can be used by CI/CD (or manually) to build, deploy and test
# the multi-cluster leader election demo.
#
# Usage: ./cicd.sh <action>
#
# The action is one of: build, deploy, test
#
# There is a Makefile that makes it easy to discover and invoke

VERSION=$(cat helm/leader-elector/values.yaml | yq .image | cut -d ':' -f2)
IMAGE="g1g1/multi-cluster-leader-election:${VERSION}"
CLUSTERS=(napoleon cleopatra stalin)

function build() {
  ./build.sh
}

function provision() {
  if ! [[ $(kubectl config get-contexts | rg " kind-kind ") ]]; then
    echo --- creating a kind cluster...
    kind create cluster
  else
    kubectl config use-context kind-kind
  fi

  if [[ $(kubectl config current-context) != kind-kind ]]; then
    echo kube context should be "kind-kind"
    return 1
  fi

  echo --- preparing three virtual clusters: Napoleon, Cleopatra and Stalin
  for cluster in $CLUSTERS[@]; do
    # Always reset to the host kind cluster before each step so we don't
    # accidentally create or connect inside a previously-connected vcluster.
    kubectl config use-context kind-kind > /dev/null
    if ! [[ $(vcluster list | rg $cluster) ]]; then
      echo preparing virtual cluster $cluster...
      vcluster create $cluster -n $cluster --connect=false
    fi
    if ! [[ $(kubectl config get-contexts -o name | rg "^vcluster_${cluster}_${cluster}_kind-kind$") ]]; then
      echo connecting to vcluster $cluster...
      vcluster connect $cluster -n $cluster
    fi
  done

  kubectl config use-context kind-kind > /dev/null
}

function deploy() {
  echo "deploying $IMAGE"

  echo --- deploying leader-elector to the target clusters
  for cluster in $CLUSTERS[@]; do
    echo deploying leader-elector to $cluster cluster
    context="vcluster_${cluster}_${cluster}_kind-kind"
    helm upgrade leader-elector helm/leader-elector --install --kube-context $context \
          --set name=$cluster \
          --set token=$LEADER_ELECTION_GITHUB_API_TOKEN
  done
}

function check-leader() {
  for cluster in $CLUSTERS[@]; do
    echo ---------------
    echo $cluster logs
    echo ---------------
    context="vcluster_${cluster}_${cluster}_kind-kind"
    kubectl logs deploy/leaderelection -n default --context $context | rg -v "Failed to update lock"
    echo
  done
}

# Run the function that was passed as argument
$1
