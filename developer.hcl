path "prod/*" {
    capabilities = ["create", "update", "read"]
}
path "stage/*" {
    capabilities = ["create", "update", "read"]
}
path "dev/*" {
    capabilities = ["create", "update", "read"]
}