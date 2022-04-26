# k8s-multi-cluster-leader-election
Demonstrate multi-cluster leader election in Kubernetes using the client-go [leaderelection](https://github.com/kubernetes/client-go/tree/master/tools/leaderelection) package and custom resource lock.

Multi-cluster leader election is useful in high-availability scenarios where you want your workload to keep running without interruption even if an entire cluster goes down. You can deploy your workload to multiple clusters, potentially in different regions, and they can all perform leader election across clusters using the [leaderelection](https://github.com/kubernetes/client-go/tree/master/tools/leaderelection) package with no changes. 

The demo application is inspired by [k8s-lesder-election](https://github.com/mayankshah1607/k8s-leader-election), which is a sample application that demonstrates in-cluster leader election using the built-in LeaseLock. 

[Mayank Shah](https://github.com/mayankshah1607) did a great job explaining how leader election works in general in his article: [Leader election in Kubernetes using client-go](https://itnext.io/leader-election-in-kubernetes-using-client-go-a19cbe7a9a85).

What's different about this application is that it uses a custom global [resource lock based on a Github gist](https://github.com/the-gigi/go-k8s/tree/main/pkg/multi_cluster_lock) that implements the [resourcelock.Interface](https://github.com/kubernetes/client-go/blob/28ccde769fc5519dd84e5512ebf303ac86ef9d7c/tools/leaderelection/resourcelock/interface.go#L144) interface:

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

The leaderelection package is designed to accept any lock that implements the resourcelock.Interface interface, so it
is not limited to operate inside a single cluster, just because the built-in locks are all in-cluster objects.

Also, to test the cross-cluster leader election I create three kind clusters and show how leader election works when killing the leader.

# Usage

There is a Makefile with the following commands

```
$ make
Available targets:

help            This help screen
build           Build and push the Docker image of the leader election demo app to DockerHub
deploy          Create 3 kind clusters and deploy the deploy the leader election demo app to all of them
test            Demonstrate multi-cluster leader election works when killing the the current leader
```

The build target create a Docker image and pushes it to DockerHub as `g1g1/multi-cluster-leader-election:`




