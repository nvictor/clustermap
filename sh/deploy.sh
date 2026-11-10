#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: demo-apps
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: demo-apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-deployment
  namespace: demo-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7.2
        ports:
        - containerPort: 6379
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: demo-apps
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
    spec:
      containers:
      - name: api-server
        image: hashicorp/http-echo:0.2.3
        args:
        - "-text=Hello from API Server"
        ports:
        - containerPort: 5678
---
# The workloads below are unhealthy on purpose, one per health signal.
# Restarts and status: exits right after starting, so it ends up in CrashLoopBackOff.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crash-loop
  namespace: demo-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crash-loop
  template:
    metadata:
      labels:
        app: crash-loop
    spec:
      containers:
      - name: crash-loop
        image: busybox:1.36
        command: ["sh", "-c", "echo starting; sleep 5; exit 1"]
---
# Status and events: the image does not exist, so it ends up in ImagePullBackOff.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bad-image
  namespace: demo-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bad-image
  template:
    metadata:
      labels:
        app: bad-image
    spec:
      containers:
      - name: bad-image
        image: registry.invalid/clustermap/missing:v1
---
# Memory: holds about 90 MiB against a 100 MiB limit.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-hog
  namespace: demo-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: memory-hog
  template:
    metadata:
      labels:
        app: memory-hog
    spec:
      containers:
      - name: memory-hog
        image: busybox:1.36
        command: ["sh", "-c", "dd if=/dev/zero of=/dev/shm/fill bs=1M count=90; sleep 1000000"]
        resources:
          requests:
            memory: 64Mi
          limits:
            memory: 100Mi
---
# CPU: spins a busy loop against a 100m limit.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cpu-burner
  namespace: demo-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cpu-burner
  template:
    metadata:
      labels:
        app: cpu-burner
    spec:
      containers:
      - name: cpu-burner
        image: busybox:1.36
        command: ["sh", "-c", "while true; do :; done"]
        resources:
          requests:
            cpu: 50m
          limits:
            cpu: 100m
---
# Status: asks for more memory than any node has, so it stays Pending.
apiVersion: v1
kind: Pod
metadata:
  name: unschedulable
  namespace: demo-apps
spec:
  containers:
  - name: unschedulable
    image: busybox:1.36
    command: ["sleep", "1000000"]
    resources:
      requests:
        memory: 512Gi
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: counter
  namespace: demo-apps
spec:
  serviceName: counter
  replicas: 2
  selector:
    matchLabels:
      app: counter
  template:
    metadata:
      labels:
        app: counter
    spec:
      containers:
      - name: counter
        image: busybox:1.36
        command: ["sh", "-c", "while true; do date; sleep 10; done"]
        resources:
          limits:
            cpu: 50m
            memory: 32Mi
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
  namespace: demo-apps
spec:
  selector:
    matchLabels:
      app: node-agent
  template:
    metadata:
      labels:
        app: node-agent
    spec:
      containers:
      - name: node-agent
        image: busybox:1.36
        command: ["sleep", "1000000"]
        resources:
          limits:
            cpu: 50m
            memory: 32Mi
EOF
