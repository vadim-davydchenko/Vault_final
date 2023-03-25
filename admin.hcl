path "auth/*" {
    capabilities = ["create", "update", "read", "delete", "list"]
}
path "sys/auth/*" {
    capabilities = ["create", "update", "delete", "sudo"]
}
path "sys/auth" {
    capabilities = ["read"]
}
path "sys/policies/acl" {
    capabilities = ["list"]
}
path "sys/policies/acl/" {
    capabilities = ["create", "update", "read", "delete", "list"]
}

path "secret/" {
    capabilities = ["create", "update", "read", "delete", "list"]
}

path "prod/*" {
    capabilities = ["create", "update", "read", "delete", "list"]
}

path "stage/*" {
    capabilities = ["create", "update", "read", "delete", "list"]
}

path "dev/*" {
    capabilities = ["create", "update", "read", "delete", "list"]
}

path "sys/mounts*" {
    capabilities = ["create", "update", "read", "delete", "list"]
}

path "sys/health" {
    capabilities = ["read", "sudo"]
}