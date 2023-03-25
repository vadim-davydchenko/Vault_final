path "rebrain-pki*" {
        capabilities = ["read", "list"]
}
path "rebrain-pki/sign/local-certs" {
        capabilities = ["create", "update"]
}
path "rebrain-pki/issue/local-certs" {
        capabilities = ["create"]
}