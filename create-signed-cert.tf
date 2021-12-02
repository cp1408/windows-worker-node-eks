resource "null_resource" "create-signed-cert" {
provisioner "local-exec" {
    command = "./templates/webhook-create-signed-cert.sh"
  }
}
