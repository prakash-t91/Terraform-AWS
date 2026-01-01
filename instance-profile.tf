resource "aws_iam_instance_profile" "instance-profile" {
  name = "Terraform"
  role = aws_iam_role.iam-role.name

}
