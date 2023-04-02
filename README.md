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

**4) [Deploy](https://github.com/vadim-davydchenko/Vault_final/blob/master/vault-helm-config.yaml) cluster with Raft backend**

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

**8) Create policy [autounseal](https://github.com/vadim-davydchenko/Vault_final/blob/master/autounseal-policy.hcl), token for which will allow to execute autounseal**

`vault policy write autounseal autounseal-policy.hcl`

**9) Generate orphan token for policy autounseal with period 24 hours**

`vault token create -orphan -policy="autounseal" -period=24h`

**10) Write config vault for autounseal in file `[vault-auto-unseal-helm-values.yml](https://github.com/vadim-davydchenko/Vault_final/blob/master/vault-auto-unseal-helm-values.yml)` and install chart**

`helm install -n vault-a vault ./vault -f vault-auto-unseal-helm-values.yml \ `

`kubectl -n vault-a exec -it vault-0 -- vault operator init | cat > .vault-recovery`

*User-pass authorization*

**11) Init secrets for path prod, stage, dev and access userpass**

`vault auth enable userpass`

`vault secrets enable -path=prod -version=2 kv`

`vault secrets enable -path=stage -version=2 kv`

`vault secrets enable -path=dev -version=2 kv`

**12) Create policy [secret-admin-policy](https://github.com/vadim-davydchenko/Vault_final/blob/master/admin.hcl), which will satisfy the following conditions:**
- for path "auth/*" will access next permissions: все, кроме patch и deny
- по пути "sys/auth/*" will access: "create", "update", "delete", "sudo"
- по пути "sys/auth" will access only read: "read"
- по пути "sys/policies/acl" only list ACL: "list"
- по путям "sys/policies/acl/", "secret/", "prod/*", "stage/*", "dev/*", "sys/mounts*": all, except patch and deny
- по пути "sys/health" next permissions: "read", "sudo"

`vault policy write admin admin.hcl`

**13) Create policy [developer](https://github.com/vadim-davydchenko/Vault_final/blob/master/developer.hcl), which will satisfy the following conditions:**
- по пути "prod/*" - "read", "create", "update"
- по пути "stage/*" - "read", "create", "update"
- по пути "dev/*" - "read", "create", "update"

`vault policy write developer developer.hcl`

**14) Create policy [junior](https://github.com/vadim-davydchenko/Vault_final/blob/master/junior.hcl), which will satisfy the following conditions:**
- по пути "stage/*" - "read", "create", "update"

`vault policy write junior junior.hcl`

**15) Create users:**
- admin with password nimda and previosly created policy admin
- developer  with password ved and previosly created policy developer
- junior  with password roinuj and previosly created policy junior

`vault write auth/userpass/users/admin password=nimda policies="secret-admin-policy"`

`vault write auth/userpass/users/developer password=ved policies="developer"`

`vault write auth/userpass/users/junior password=roinuj policies="junior"`


*PKI*

**16) Activate PKI for path rebrain-pki, max-lease-ttl=8760h**

`vault secrets enable -path rebrain-pki pki`

`vault secrets tune -max-lease-ttl=8760h rebrain-pki`

**17) Write certificate for path rebrain-pki/config/ca**

`vault write rebrain-pki/config/ca pem_bundle=@bundle.pem`

**18) Create role rebrain-pki/roles/local-certs for create certificate with next parameters:**
- max_ttl 24 hours
- localhost deny
- allow domain myapp.st_login.rebrain.me
- allow bare domain
- deny subdomain
- deny wildcard certificate
- deny ip sans

```
vault write rebrain-pki/roles/local-certs \
ttl="24h" \
allow_localhost=false \
allowed_domains="myapp.st_login.rebrain.me" \
allow_bare_domains=true \
allow_subdomains=false \
allow_wildcard_certificates=false \
allow_ip_sans=false
enforce_hostnames=false
```

**19) Create policy [cert-issue-policy](https://github.com/vadim-davydchenko/Vault_final/blob/master/cert-issue-policy.hcl), which will satisfy the following conditions:**
- path "rebrain-pki*" - "read", "list"
- path "rebrain-pki/sign/local-certs" - "create", "update"
- path "rebrain-pki/issue/local-certs" - "create"

`vault policy write cert-issue-policy cert-issue-policy.hcl`

**20) Activate Authentication kubernetes. Use as a host https://$KUBERNETES_PORT_443_TCP_ADDR:443**

`vault auth enable kubernetes`

*Take token_reviewer_jwt*

`kubectl create token vault -n vault`

*Setting Authentication*

```
vault write auth/kubernetes/config \
token_reviewer_jwt="<your_jwt_token_vault>" \
kubernetes_host=<https://$KUBERNETES_PORT_443_TCP_ADDR:443> \
kubernetes_ca_cert=@/home/user/.minikube/ca.crt
```

**21) Create an auth/kubernetes/role/issuer role with a cert-issue-policy that can only be accessed by service accounts named issuer from the namespace default, ttl=20m**

```
vault write auth/kubernetes/role/issuer \
bound_service_account_names=issuer \
bound_service_account_namespaces=default \
policies=cert-issue-policy \
ttl=20m
```

**22) Install cert-manager**

`kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.9.1/cert-manager.crds.yaml`

`helm install cert-manager --namespace cert-manager --version v1.9.1 jetstack/cert-manager`

**23) Create in kubernetes service account issuer**

`kubectl create sa issuer -n default`

**24) Add [secret](https://github.com/vadim-davydchenko/Vault_final/blob/master/issuer-secret.yaml) in kubernetes and [setting](https://github.com/vadim-davydchenko/Vault_final/blob/master/vault-issuer.yaml) [certmanager](https://github.com/vadim-davydchenko/Vault_final/blob/master/myapp-cert.yaml)**

`kubectl apply -f issuer-secret.yaml`

`export ISSUER_SECRET_REF=$(kubectl get secrets --output=json | jq -r '.items[].metadata | select(.name|startswith("issuer-token-")).name')`

`kubectl apply -f vault-issuer.yaml`

`kubectl apply -f myapp-cert.yaml`

**25) Change the type of prometheus and grafana services in the monitoring namespace from ClusterIP to NodePort**

`kubectl edit svc -n monitoring prometheus-kube-prometheus-prometheus`

`kubectl edit svc -n monitoring prometheus-grafana`

**26) Expand Helm Chart [Loki](https://github.com/vadim-davydchenko/Vault_final/blob/master/loki-stack-values.yml)**

`helm install loki grafana/loki-stack -n monitoring -f loki-stack-values.yml`

**27) Configure vault for logging to stdout**

`vault audit enable file file_path=stdout`

**28) Bringing Grafana outside**

`kubectl port-forward -n monitoring svc/prometheus-grafana --address=0.0.0.0 3000:80`
