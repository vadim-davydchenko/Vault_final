### Building a basic highly available Vault infrastructure in a Kubernetes cluster

**1) Run minikube, create namespaces**

`sudo sysctl -w fs.inotify.max_user_instances=8192`

`minikube start --driver docker --nodes 3`

```
kubectl create ns vault
kubectl create ns vault-a
kubectl create ns monitoring
kubectl create ns cert-manager
```

**2) Add repo for Helm**

```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm repo add hashicorp https://helm.releases.hashicorp.com
```

**3) Install prometheus stack**

`helm install -n monitoring prometheus prometheus-community/kube-prometheus-stack`

**4) Deploy cluster with Raft backend**

`helm install -n vault vault ./vault-custom -f vault-helm-config.yaml`

**5) Initialize vault on pod vault-0 with 3 keys, any two of which print out Vault**

`kubectl exec -it vault-0 -n vault -- vault operator init -key-shares=3 -key-threshold=2 -tls-skip-verify`

`kubectl exec -it vault-0 -n vault -- vault operator unseal`

**6) Connect raft for vault-1 and vault-2. Url for vault-0 in cluster `http://vault-0.vault-internal:8200`**

```
kubectl exec -ti -n vault vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -ti -n vault vault-1 -- vault operator unseal

kubectl exec -ti -n vault vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -ti -n vault vault-2 -- vault operator unseal

kubectl exec -ti -n vault vault-0 -- vault login
kubectl exec -ti -n vault vault-0 -- vault operator raft list-peers
```

*Setting Autounseal*

**7) Activate transit autounseal on vault-0**

`kubectl port-forward vault-0 -n vault 8200:8200`

`export VAULT_ADDR=http://127.0.0.1:8200`

`vault login`

`vault secrets enable transit`

`vault write -f transit/keys/autounseal`

**8) Create policy autounseal, token for which will allow to execute autounseal**

`vault policy write autounseal autounseal-policy.hcl`

**9) Generate orphan token for policy autounseal with period 24 hours**

`vault token create -orphan -policy="autounseal" -period=24h`

**10) Write config vault for autounseal in file `vault-auto-unseal-helm-values.yml` and install chart**

`helm install -n vault-a vault ./vault -f vault-auto-unseal-helm-values.yml \ `

`kubectl -n vault-a exec -it vault-0 -- vault operator init | cat > .vault-recovery`
