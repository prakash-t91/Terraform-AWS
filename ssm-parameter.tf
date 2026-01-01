resource "aws_ssm_parameter" "ssh_private_key" {
  #name        = "/home/ansible/.ssh/awskey1"
  name        = "/home/prakash/.ssh/key2"
  description = "key2"
  type        = "String"
  value       = file("~/.ssh/key2")
}
