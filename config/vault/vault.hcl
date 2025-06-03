storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = true
}

ui = true
api_addr = "http://0.0.0.0:8200"
cluster_addr = "http://0.0.0.0:8201"

# Disable mlock for containerized environments
disable_mlock = true

# Log level
log_level = "INFO"
