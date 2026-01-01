data "aws_ssm_parameter" "ssh_private_key" {
  name = aws_ssm_parameter.ssh_private_key.name
}

output "ssh_private_key" {
  value     = nonsensitive(data.aws_ssm_parameter.ssh_private_key.value)
  sensitive = true
}
