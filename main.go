package main

import (
	"context"
	"flag"
	"github.com/the-gigi/go-k8s/pkg/multi_cluster_lock"
	"k8s.io/client-go/tools/leaderelection"
	"k8s.io/client-go/tools/leaderelection/resourcelock"
	"k8s.io/klog/v2"
	"os"
	"time"
)

// run performs the leader election until a new leader is selected
func run(lock resourcelock.Interface, ctx context.Context, id string) {
	leaderelection.RunOrDie(ctx, leaderelection.LeaderElectionConfig{
		Lock:            lock,
		ReleaseOnCancel: true,
		LeaseDuration:   15 * time.Second,
		RenewDeadline:   10 * time.Second,
		RetryPeriod:     2 * time.Second,
		Callbacks: leaderelection.LeaderCallbacks{
			OnStartedLeading: func(c context.Context) {
				klog.Infof("I (%s) will lead you to greatness!", id)
			},
			OnStoppedLeading: func() {
				klog.Info("no longer the leader, staying inactive.")
			},
			OnNewLeader: func(currentId string) {
				if currentId == id {
					klog.Info("I am your leader!")
					return
				}
				klog.Infof("All hail %s", currentId)
			},
		},
	})
}

func main() {
	var (
		gistId         = os.Getenv("GIST_ID")
		githubAPIToken = os.Getenv("GITHUB_API_TOKEN")
		name           = os.Getenv("LEADER_NAME")
	)

	klog.InitFlags(nil)
	klog.Flush()
	flag.Parse()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	lock, err := multi_cluster_lock.NewGistLock(name, gistId, githubAPIToken)
	if err != nil {
		panic(err)
	}
	for {
		run(lock, ctx, name)
		select {
		case <-ctx.Done():
			break
		default:
			continue
		}
	}
}
