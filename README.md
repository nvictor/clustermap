# Clustermap

Kubernetes cluster health at a glance.

Every pod is a tile in a treemap. Size is its footprint, color is its health. Open the app and it reads your kubeconfig, draws the cluster, and keeps it fresh.

![Clustermap](docs/demo.png)

- Five health signals: CPU, memory, restarts, pod status, and warning events.
- Group by namespace or by node. Click to zoom in, click a pod for its details.
- Read-only. Clustermap never changes your cluster.

CPU and memory need the [Metrics Server](https://github.com/kubernetes-sigs/metrics-server).

Requires macOS 15.5 or later and Apple Silicon.
