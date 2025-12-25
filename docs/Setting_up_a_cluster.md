By [TitanFighter](https://github.com/TitanFighter)

# Setting Up a Cluster

This guide will walk you through creating a fully functional Kubernetes cluster on Hetzner Cloud using hetzner-k3s, complete with ingress controller and a sample application.

## Prerequisites

Before starting, ensure you have:

1. **Hetzner Cloud Account** with project and API token
2. **kubectl** installed on your local machine
3. **Helm** installed on your local machine
4. **hetzner-k3s** installed (see [Installation Guide](Installation.md))
5. **SSH Key Pair** for accessing cluster nodes

## Instructions

### Installation of a "hello-world" project

For testing, we’ll use this "hello-world" app: [hello-world app](https://raw.githubusercontent.com/vitobotta/hetzner-k3s/refs/heads/main/sample-deployment.yaml)

1. Install `kubectl` on your computer: [kubectl installation](https://kubernetes.io/docs/tasks/tools/#kubectl)
2. Install `Helm` on your computer: [Helm installation](https://helm.sh/docs/intro/install/)
3. Install `hetzner-k3s` on your computer: [Installation](Installation.md)
4. Create a file called `hetzner-k3s_cluster_config.yaml` with the following configuration. This setup is for a Highly Available (HA) cluster with 3 master nodes and 3 worker nodes. You can use 1 master and 1 worker for testing:

```yaml
hetzner_token: ...
cluster_name: hello-world
kubeconfig_path: "./kubeconfig"  # or /cluster/kubeconfig if you are going to use Docker
k3s_version: v1.32.0+k3s1

networking:
  ssh:
    port: 22
    use_agent: false
    public_key_path: "~/.ssh/id_rsa.pub"
    private_key_path: "~/.ssh/id_rsa"
  allowed_networks:
    ssh:
      - 0.0.0.0/0
    api:
      - 0.0.0.0/0

masters_pool:
  instance_type: cpx22
  instance_count: 3
  locations:
    - fsn1
    - hel1
    - nbg1

worker_node_pools:
- name: small
  instance_type: cpx22
  instance_count: 4
  location: hel1
- name: big
  instance_type: cpx32
  location: fsn1
  autoscaling:
    enabled: true
    min_instances: 0
    max_instances: 3
```

For more details on all the available settings, refer to the full config example in [Creating a cluster](Creating_a_cluster.md).

5. Create the cluster: `hetzner-k3s create --config hetzner-k3s_cluster_config.yaml`
6. `hetzner-k3s` automatically generates a `kubeconfig` file for the cluster in the directory where you run the tool. You can either copy this file to `~/.kube/config` if it’s the only cluster or run `export KUBECONFIG=./kubeconfig` in the same directory to access the cluster. After this, you can interact with your cluster using `kubectl` installed in step 1.

TIP: If you don’t want to run `kubectl apply ...` every time, you can store all your configuration files in a folder and then run `kubectl apply -f /path/to/configs/ -R`.

7. Create a file: `touch ingress-nginx-annotations.yaml`
8. Add annotations to the file: `nano ingress-nginx-annotations.yaml`

```yaml
# INSTALLATION
# 1. Install Helm: https://helm.sh/docs/intro/install/
# 2. Add ingress-nginx Helm repo: helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
# 3. Update information of available charts: helm repo update
# 4. Install ingress-nginx:
# helm upgrade --install \
# ingress-nginx ingress-nginx/ingress-nginx \
# --set controller.ingressClassResource.default=true \ # Remove this line if you don’t want Nginx to be the default Ingress Controller
# -f ./ingress-nginx-annotations.yaml \
# --namespace ingress-nginx \
# --create-namespace

# LIST of all ANNOTATIONS: https://github.com/hetznercloud/hcloud-cloud-controller-manager/blob/master/internal/annotation/load_balancer.go

controller:
  kind: DaemonSet
  service:
    annotations:
      # Germany:
      # - nbg1 (Nuremberg)
      # - fsn1 (Falkenstein)
      # Finland:
      # - hel1 (Helsinki)
      # USA:
      # - ash (Ashburn, Virginia)
      # Without this, the load balancer won’t be provisioned and will stay in "pending" state.
      # You can check this state using "kubectl get svc -n ingress-nginx"
      load-balancer.hetzner.cloud/location: nbg1

      # Name of the load balancer. This name will appear in your Hetzner cloud console under "Your project -> Load Balancers".
      # NOTE: This is NOT the load balancer created automatically for HA clusters. You need to specify a different name here to create a separate load balancer for ingress Nginx.
      load-balancer.hetzner.cloud/name: WORKERS_LOAD_BALANCER_NAME

      # Ensures communication between the load balancer and cluster nodes happens through the private network.
      load-balancer.hetzner.cloud/use-private-ip: "true"

      # [ START: Use these annotations if you care about seeing the actual client IP ]
      # "uses-proxyprotocol" enables the proxy protocol on the load balancer so that the ingress controller and applications can see the real client IP.
      # "hostname" is needed if you use cert-manager (LetsEncrypt SSL certificates). It fixes HTTP01 challenges for cert-manager (https://cert-manager.io/docs/).
      # Check this link for more details: https://github.com/compumike/hairpin-proxy
      # In short: the easiest fix provided by some providers (including Hetzner) is to configure the load balancer to use a hostname instead of an IP.
      load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'

      # 1. "yourDomain.com" must be correctly configured in DNS to point to the Nginx load balancer; otherwise, certificate provisioning won’t work.
      # 2. If you use multiple domains, specify any one.
      load-balancer.hetzner.cloud/hostname: yourDomain.com
      # [ END: Use these annotations if you care about seeing the actual client IP ]

      load-balancer.hetzner.cloud/http-redirect-https: 'false'
```

- Replace `yourDomain.com` with your actual domain.
- Replace `WORKERS_LOAD_BALANCER_NAME` with a name of your choice.

9. Add the ingress-nginx Helm repo: `helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx`
10. Update the Helm repo: `helm repo update`
11. Install ingress-nginx:

```bash
helm upgrade --install \
ingress-nginx ingress-nginx/ingress-nginx \
--set controller.ingressClassResource.default=true \
-f ./ingress-nginx-annotations.yaml \
--namespace ingress-nginx \
--create-namespace
```

The `--set controller.ingressClassResource.default=true` flag configures this as the default Ingress Class for your cluster. Without this, you’ll need to specify an Ingress Class for every Ingress object you deploy, which can be tedious. If no default is set and you don’t specify one, Nginx will return a 404 Not Found page because it won’t "pick up" the Ingress.

TIP: To delete it: `helm uninstall ingress-nginx -n ingress-nginx`. Be careful, as this will delete the current Hetzner load balancer, and installing a new ingress controller may create a new load balancer with a different public IP.

12. After a few minutes, check that the "EXTERNAL-IP" column shows an IP instead of "pending": `kubectl get svc -n ingress-nginx`

13. The `load-balancer.hetzner.cloud/uses-proxyprotocol: "true"` annotation requires `use-proxy-protocol: "true"` for ingress-nginx. To set this up, create a file: `touch ingress-nginx-configmap.yaml`
14. Add the following content to the file: `nano ingress-nginx-configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  # Do not change the name - this is required by the Nginx Ingress Controller
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  use-proxy-protocol: "true"
```

15. Apply the ConfigMap: `kubectl apply -f ./ingress-nginx-configmap.yaml`
16. Open your Hetzner cloud console, go to "Your project -> Load Balancers," and find the PUBLIC IP of the load balancer with the name you used in the `load-balancer.hetzner.cloud/name: WORKERS_LOAD_BALANCER_NAME` annotation. Copy or note this IP.
17. Download the hello-world app: `curl https://raw.githubusercontent.com/vitobotta/hetzner-k3s/refs/heads/main/sample-deployment.yaml --output hello-world.yaml`
18. Edit the file to add the annotation and set the hostname:

```yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-world
  annotations:                       # <<<--- Add annotation
    kubernetes.io/ingress.class: nginx  # <<<--- Add annotation
spec:
  rules:
  - host: hello-world.IP_FROM_STEP_12.nip.io # <<<--- Replace `IP_FROM_STEP_12` with the IP from step 16.
  ....
```

19. Install the hello-world app: `kubectl apply -f hello-world.yaml`
20. Open http://hello-world.IP_FROM_STEP_12.nip.io in your browser. You should see the Rancher "Hello World!" page.
The `host.IP_FROM_STEP_12.nip.io` (the `.nip.io` part is key) is a quick way to test things without configuring DNS. A query to a hostname ending in `.nip.io` returns the IP address in the hostname itself. If you enabled the proxy protocol as shown earlier, your public IP address should appear in the `X-Forwarded-For` header, meaning the application can "see" it.

21. To connect your actual domain, follow these steps:
   - Assign the IP address from step 12 to your domain in your DNS settings.
   - Change `- host: hello-world.IP_FROM_STEP_12.nip.io` to `- host: yourDomain.com`.
   - Run `kubectl apply -f hello-world.yaml`.
   - Wait until DNS records are updated.

### If you need LetsEncrypt

22. Add the LetsEncrypt Helm repo: `helm repo add jetstack https://charts.jetstack.io`
23. Update the Helm repo: `helm repo update`
24. Install the LetsEncrypt certificates issuer:

```bash
helm upgrade --install \
--namespace cert-manager \
--create-namespace \
--set crds.enabled=true \
cert-manager jetstack/cert-manager
```

25. Create a file called `lets-encrypt.yaml` with the following content:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    email: [REDACTED]
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

26. Apply the file: `kubectl apply -f ./lets-encrypt.yaml`
27. Edit `hello-world.yaml` and add the settings for TLS encryption:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-world
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # <<<--- Add annotation
    kubernetes.io/tls-acme: "true"                      # <<<--- Add annotation
spec:
  rules:
  - host: yourDomain.com  # <<<---- Your actual domain
  tls: # <<<---- Add this block
  - hosts:
    - yourDomain.com
    secretName: yourDomain.com-tls # <<<--- Add reference to secret
  ....
```

TIP: If you didn’t configure Nginx as the default Ingress Class, you’ll need to add the `spec.ingressClassName: nginx` annotation.

28. Apply the changes: `kubectl apply -f ./hello-world.yaml`

## FAQs

### 1. Can I use MetalLB instead of Hetzner's Load Balancer?

Yes, you can use MetalLB with floating IPs in Hetzner Cloud, but I wouldn’t recommend it. The setup with Hetzner's standard load balancers is much simpler. Plus, load balancers aren’t significantly more expensive than floating IPs, so in my opinion, there’s no real benefit to using MetalLB in this case.

### 2. How do I create and push Docker images to a repository, and how can Kubernetes work with these images? (GitLab example)

On the machine where you create the image:

- Start by logging in to the Docker registry: `docker login registry.gitlab.com`.
- Build the Docker image: `docker build -t registry.gitlab.com/COMPANY_NAME/REPO_NAME:IMAGE_NAME -f /some/path/to/Dockerfile .`.
- Push the image to the registry: `docker push registry.gitlab.com/COMPANY_NAME/REPO_NAME:IMAGE_NAME`.

On the machine running Kubernetes:

- Generate a secret to allow Kubernetes to access the images: `kubectl create secret docker-registry gitlabcreds --docker-server=https://registry.gitlab.com --docker-username=MYUSER --docker-password=MYPWD --docker-email=MYEMAIL -n NAMESPACE_OF_YOUR_APP -o yaml > docker-secret.yaml`.
- Apply the secret: `kubectl apply -f docker-secret.yaml -n NAMESPACE_OF_YOUR_APP`.

### 3. How can I check the resource usage of nodes or pods?

First, install the metrics-server from this GitHub repository: https://github.com/kubernetes-sigs/metrics-server. After installation, you can use either `kubectl top nodes` or `kubectl top pods -A` to view resource usage.

### 4. What is Ingress?

There are two types of "ingress" to understand: `Ingress Controller` and `Ingress Resources`.

In the case of Nginx:

- The `Ingress Controller` is Nginx itself (defined as `kind: Ingress`), while `Ingress Resources` are services (defined as `kind: Service`).
- The `Ingress Controller` has various annotations (rules). You can use these annotations in `kind: Ingress` to make them "global" or in `kind: Service` to make them "local" (specific to that service).
- The `Ingress Controller` consists of a Pod and a Service. The Pod runs the Controller, which continuously monitors the /ingresses endpoint in your cluster’s API server for updates to available `Ingress Resources`.

### 5. How can I configure autoscaling to automatically set up IP routes for new nodes to use a NAT server?

First, you’ll need a NAT server, as described in this [Hetzner community tutorial](https://community.hetzner.com/tutorials/how-to-set-up-nat-for-cloud-networks#step-2---adding-the-route-to-the-network).

Then, use `additional_post_k3s_commands` to run commands after k3s installation:
```yaml
additional_packages:
  - ifupdown
additional_post_k3s_commands:
  - apt update
  - apt upgrade -y
  - apt autoremove -y
  - ip route add default via [REDACTED]  # Replace this with your gateway IP
```

You can also use `additional_pre_k3s_commands` to run commands before k3s installation if needed.

## Useful Commands

```bash
kubectl get service [serviceName] -A or -n [nameSpace]
kubectl get ingress [ingressName] -A or -n [nameSpace]
kubectl get pod [podName] -A or -n [nameSpace]
kubectl get all -A
kubectl get events -A
helm ls -A
helm uninstall [name] -n [nameSpace]
kubectl -n ingress-nginx get svc
kubectl describe ingress -A
kubectl describe svc -n ingress-nginx
kubectl delete configmap nginx-config -n ingress-nginx
kubectl rollout restart deployment -n NAMESPACE_OF_YOUR_APP
kubectl get all -A` does not include "ingress", so use `kubectl get ing -A
```

## Useful Links

- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [A visual guide on troubleshooting Kubernetes deployments](https://learnk8s.io/troubleshooting-deployments)
