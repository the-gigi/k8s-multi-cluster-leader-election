# k8s-multi-cluster-leader-election

This repository demonstrates multi-cluster leader election in Kubernetes using the client-go [leaderelection](https://github.com/kubernetes/client-go/tree/master/tools/leaderelection) package and a custom resource lock.

Multi-cluster leader election is useful in high-availability scenarios where you want your workload to keep running without interruption even if an entire cluster goes down. You can deploy your workload to multiple clusters, potentially in different regions, and they can all perform leader election across clusters using the [leaderelection](https://github.com/kubernetes/client-go/tree/master/tools/leaderelection) package with no changes. 

The demo application is inspired by [k8s-leader-election](https://github.com/mayankshah1607/k8s-leader-election), which is a sample application that demonstrates in-cluster leader election using the built-in LeaseLock. 

[Mayank Shah](https://github.com/mayankshah1607) did a great job explaining how leader election works in general in his article: [Leader election in Kubernetes using client-go](https://itnext.io/leader-election-in-kubernetes-using-client-go-a19cbe7a9a85).

What's different about this application is that it uses a custom global [resource lock](https://github.com/the-gigi/go-k8s/tree/main/pkg/multi_cluster_lock)  based on a Github gist that implements the [resourcelock.Interface](https://github.com/kubernetes/client-go/blob/28ccde769fc5519dd84e5512ebf303ac86ef9d7c/tools/leaderelection/resourcelock/interface.go#L144) interface:

```
// Interface offers a common interface for locking on arbitrary
// resources used in leader election.  The Interface is used
// to hide the details on specific implementations in order to allow
// them to change over time.  This interface is strictly for use
// by the leaderelection code.
type Interface interface {
	// Get returns the LeaderElectionRecord
	Get(ctx context.Context) (*LeaderElectionRecord, []byte, error)

	// Create attempts to create a LeaderElectionRecord
	Create(ctx context.Context, ler LeaderElectionRecord) error

	// Update will update and existing LeaderElectionRecord
	Update(ctx context.Context, ler LeaderElectionRecord) error

	// RecordEvent is used to record events
	RecordEvent(string)

	// Identity will return the locks Identity
	Identity() string

	// Describe is used to convert details on current resource lock
	// into a string
	Describe() string
}
```

The client-go leaderelection package is designed to accept any lock that implements the `resourcelock.Interface` interface, so it
is not limited to operate inside a single cluster, just because the built-in locks are all in-cluster objects.

To test the cross-cluster leader election I create three virtual clusters and show how leader election works when killing the leader.

# Prerequisites for running the leader election demo

This setup is using my (Gigi) Dockerhub account to push images to my Github account and private access token to store the shared lock in a private Gist.

If you want to replicate this yourself you need to change [values.yaml](helm/leader-elector/values.yaml) file and replace
the target Docker registry/repository as well as the Gist Id:

```
image: g1g1/multi-cluster-leader-election:amd64-0.6
gist: 49602e14c52b53a41862a174b629c7b2
```

You need to define several environment variables. 

The environment variable `LEADER_ELECTION_GITHUB_API_TOKEN` should contains a Github API token 
for accessing your private Gist. Check out https://docs.github.com/en/rest/gists/gists for more details.

The environment variables `DOCKERHUB_USERNAME` and `DOCKERHUB_PASSWORD` should contain your Dockerhub credentials.
Checkout https://hub.docker.com

You will also need to have the following tools in your path:

- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) (duh!)
- [kind](https://kubernetes.io/docs/tasks/tools/#kind)
- [yq](https://github.com/mikefarah/yq)
- [vcluster](https://github.com/loft-sh/vcluster)

These tools are used by the [cicd.sh](cicd.sh) script, which powers the demo.

# Usage

There is a Makefile with the following commands

```
$ make
Available targets:

help            This help screen
build           Build and push the Docker image of the leader election demo app to DockerHub
provision       Create 3 virtual cluster in a kind cluster called kind-kind
deploy          Deploy the leader election demo app to all the virtual clusters
check-leader    Check the logs of all participants in the leader election
```

First, you run `make build`, which will push a new image to your Docker registry. If you prefer to use
the existing image you can skip this step. It's only necessary if you want to modify the code.

Next, run `make deploy`, which will provision a new default kind cluster (if it doesn't exist) and then proceed to provision three virtual clusters named `napoleon`, `stalin` and `cleopatra`. These virtuals clusters leave in namespaces in the kind cluster, which makes it very fast and cheap to set them up and tear them down. Then, it will deploy the leader election image as a k8s Deployment called leader-election to all the virtual clusters. One of them will be the leaders and the other will wait for their turn.

Then, run `make check-leader`, which displays the logs from all the clusters and will show who the leader is.

# Cross-cluster Leader Election in Action

Let's give it a try. Here is the current state:

```
$ make check-leader
---------------
napoleon logs
---------------
I0111 08:54:13.874758       1 leaderelection.go:248] attempting to acquire leader lease Github gist lock: napoleon...
I0111 08:54:17.998214       1 main.go:34] All hail cleopatra

---------------
cleopatra logs
---------------
I0111 08:52:40.188839       1 leaderelection.go:248] attempting to acquire leader lease Github gist lock: cleopatra...
I0111 08:52:47.946119       1 leaderelection.go:258] successfully acquired lease Github gist lock: cleopatra
I0111 08:52:47.946726       1 main.go:31] I am cleopatra! I will lead you to greatness!
I0111 08:52:47.947698       1 main.go:24] started leading.

---------------
stalin logs
---------------
I0111 08:54:06.218168       1 leaderelection.go:248] attempting to acquire leader lease Github gist lock: stalin...
I0111 08:54:08.604808       1 main.go:34] All hail cleopatra
```

Cleopatra is the current leader. Let's kill Cleopatra by scaling its deployment to zero:

```
$ k scale --replicas=0 deploy leaderelection -n default --context vcluster_cleopatra_cleopatra_kind-kind
deployment.apps/leaderelection scaled
```

Now, if we look at the logs we can see that Stalin became the new leader and Napoleon accepted Stalin's leadership ("All hail Stalin")

```
$ make check-leader
---------------
napoleon logs
---------------
I0111 08:54:13.874758       1 leaderelection.go:248] attempting to acquire leader lease Github gist lock: napoleon...
I0111 08:54:17.998214       1 main.go:34] All hail cleopatra
I0111 08:56:10.682068       1 main.go:34] All hail stalin

---------------
cleopatra logs
---------------
error: timed out waiting for the condition

---------------
stalin logs
---------------
I0111 08:54:06.218168       1 leaderelection.go:248] attempting to acquire leader lease Github gist lock: stalin...
I0111 08:54:08.604808       1 main.go:34] All hail cleopatra
I0111 08:56:13.070595       1 leaderelection.go:258] successfully acquired lease Github gist lock: stalin
I0111 08:56:13.070981       1 main.go:31] I am stalin! I will lead you to greatness!
I0111 08:56:13.071852       1 main.go:24] started leading.
```

If you're curious here is the information the lock stores in the Gist:

```
$ data=$(http https://api.github.com/gists/49602e14c52b53a41862a174b629c7b2 | jq '.files["multi-cluster-leader-election.lock"].content' | sed 's/\\\"/\"/g')

$ echo "${data:1:-1}" | jq .
{
  "holderIdentity": "stalin",
  "leaseDurationSeconds": 10,
  "acquireTime": "2023-01-11T08:55:44Z",
  "renewTime": "2023-01-11T09:14:40Z",
  "leaderTransitions": 41
}
```





