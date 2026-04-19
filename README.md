# k8s-multi-cluster-leader-election

This repository demonstrates multi-cluster leader election in Kubernetes using the client-go [leaderelection](https://github.com/kubernetes/client-go/tree/master/tools/leaderelection) package and a custom resource lock.

Multi-cluster leader election is useful in high-availability scenarios where you want your workload to keep running without interruption even if an entire cluster goes down. You can deploy your workload to multiple clusters, potentially in different regions, and they can all perform leader election across clusters using the [leaderelection](https://github.com/kubernetes/client-go/tree/master/tools/leaderelection) package with no changes.

The demo application is inspired by [k8s-leader-election](https://github.com/mayankshah1607/k8s-leader-election), which is a sample application that demonstrates in-cluster leader election using the built-in LeaseLock.

[Mayank Shah](https://github.com/mayankshah1607) did a great job explaining how leader election works in general in his article: [Leader election in Kubernetes using client-go](https://itnext.io/leader-election-in-kubernetes-using-client-go-a19cbe7a9a85).

What's different about this application is that it uses a custom global [resource lock](https://github.com/the-gigi/go-k8s/tree/main/pkg/multi_cluster_lock) based on a Github gist that implements the [resourcelock.Interface](https://github.com/kubernetes/client-go/blob/28ccde769fc5519dd84e5512ebf303ac86ef9d7c/tools/leaderelection/resourcelock/interface.go#L144) interface:

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

The client-go leaderelection package is designed to accept any lock that implements the `resourcelock.Interface` interface, so it is not limited to operate inside a single cluster, just because the built-in locks are all in-cluster objects.

> Important: a Github gist as a shared lock is fine for a demo, but it is **not** a good production choice (rate limits, latency, GitHub becomes part of your HA story). For real cross-cluster leader election, implement `resourcelock.Interface` against whatever globally consistent store you already operate (Spanner, Cosmos DB with strong consistency, DynamoDB with conditional writes, etcd, Consul, CockroachDB, Postgres advisory locks, S3/GCS with conditional writes, etc.).

To test cross-cluster leader election the demo creates three virtual clusters and shows what happens when the leader is killed.

# Prerequisites for running the leader election demo

The default [values.yaml](helm/leader-elector/values.yaml) points at the image in my (Gigi) DockerHub and a private Gist I own:

```
image: g1g1/multi-cluster-leader-election:1.0
gist: 49602e14c52b53a41862a174b629c7b2
```

The image is multi-arch (`linux/amd64` and `linux/arm64`), so it works on both Intel/AMD and Apple Silicon out of the box. To use your own image and Gist, edit `values.yaml`.

Set this environment variable so the deploy step can write to your Gist:

- `LEADER_ELECTION_GITHUB_API_TOKEN` — a GitHub personal access token with the `gist` scope. See https://docs.github.com/en/rest/gists/gists.

If you also want to rebuild and push the image, log in to DockerHub once with `docker login` (the build script uses your existing Docker credentials, no extra env vars needed).

You will also need the following tools in your path:

- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
- [kind](https://kubernetes.io/docs/tasks/tools/#kind)
- [helm](https://helm.sh/docs/intro/install/)
- [yq](https://github.com/mikefarah/yq)
- [vcluster](https://github.com/loft-sh/vcluster) (v0.20+)
- [docker](https://docs.docker.com/get-docker/) with `buildx` (only needed if you rebuild the image)

These tools are used by the [cicd.sh](cicd.sh) script, which powers the demo.

# Usage

There is a Makefile with the following commands:

```
$ make
Available targets:

help            This help screen
build           Build and push the multi-arch Docker image of the leader election demo app to DockerHub
provision       Create 3 virtual clusters in a kind cluster called kind-kind
deploy          Deploy the leader election demo app to all the virtual clusters
check-leader    Check the logs of all participants in the leader election
```

`make build` is only needed if you modify the code and want your own image. Otherwise just use the default image from `values.yaml`. Under the hood `make build` calls [build.sh](build.sh), which uses `docker buildx` to build and push for `linux/amd64` and `linux/arm64`.

Run `make deploy` (which depends on `provision`) to:

1. Create a default kind cluster (if one doesn't already exist).
2. Create three virtual clusters named `napoleon`, `cleopatra`, and `stalin` (each in its own namespace inside the kind cluster, which makes them fast and cheap to set up and tear down).
3. Connect to each vcluster, which adds three kubectl contexts: `vcluster_napoleon_napoleon_kind-kind`, `vcluster_cleopatra_cleopatra_kind-kind`, `vcluster_stalin_stalin_kind-kind`.
4. Helm-install the `leader-elector` Deployment into each vcluster. They all point at the same Gist, so exactly one of them wins the lease.

Then run `make check-leader` to display the logs from all three vclusters and see who is the current leader.

# Cross-cluster Leader Election in Action

Right after `make deploy`, one of the three pods will win the lease and the others will acknowledge it:

```
$ make check-leader
---------------
napoleon logs
---------------
I0419 19:52:43.836783       1 leaderelection.go:258] successfully acquired lease Github gist lock: napoleon
I0419 19:52:43.837820       1 main.go:31] I am napoleon! I will lead you to greatness!
I0419 19:52:43.838063       1 main.go:24] started leading.

---------------
cleopatra logs
---------------
I0419 19:52:43.099532       1 main.go:34] All hail napoleon

---------------
stalin logs
---------------
I0419 19:52:44.448922       1 main.go:34] All hail napoleon
```

Napoleon is the current leader. Now kill napoleon by deleting its deployment:

```
$ kubectl delete deploy leaderelection -n default --context vcluster_napoleon_napoleon_kind-kind
deployment.apps "leaderelection" deleted
```

After the lease expires (10 seconds), one of the surviving pods grabs the lock and the others switch their allegiance:

```
$ make check-leader
---------------
napoleon logs
---------------
error: timed out waiting for the condition

---------------
cleopatra logs
---------------
I0419 19:52:43.099532       1 main.go:34] All hail napoleon
I0419 19:53:45.831924       1 leaderelection.go:258] successfully acquired lease Github gist lock: cleopatra
I0419 19:53:45.833015       1 main.go:31] I am cleopatra! I will lead you to greatness!
I0419 19:53:45.833028       1 main.go:24] started leading.

---------------
stalin logs
---------------
I0419 19:52:44.448922       1 main.go:34] All hail napoleon
I0419 19:53:37.543813       1 main.go:34] All hail cleopatra
```

If you're curious, here is what the gist looks like after the failover:

```
$ gh gist view 49602e14c52b53a41862a174b629c7b2
Lock for multi-cluster leader election demo

{"holderIdentity":"cleopatra","leaseDurationSeconds":10,"acquireTime":"2026-04-19T19:53:33Z","renewTime":"2026-04-19T19:53:33Z","leaderTransitions":1}
```

`leaderTransitions` increments every time the lease changes hands.

# Cleanup

```
for c in napoleon cleopatra stalin; do vcluster delete $c -n $c; done
kind delete cluster
```
