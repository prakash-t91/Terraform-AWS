data "aws_subnets" "public_subnet" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  tags = {
    Tier = "public-subnet"
  }
}

resource "aws_eip" "lb_instance" {
  #count    = 2
  instance = aws_instance.private_instance[0].id
  domain   = "vpc"
}

resource "aws_eip_association" "one" {
 #instance_id          = var.instance_id
  network_interface_id = aws_network_interface.network_interface.id
  allocation_id        = aws_eip.one.id
  private_ip_address   = "10.0.3.10"
}

resource "aws_eip_association" "two" {
 #instance_id          = var.instance_id
  network_interface_id = aws_network_interface.network_interface.id
  allocation_id        = aws_eip.two.id
  private_ip_address   = "10.0.3.11"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_launch_template" "app_lt" {

  name_prefix            = "app-lt"
  image_id               = "ami-0e1bed4f06a3b463d" # Replace with your AMI ID
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  #user_data     = filebase64("user_data.sh") 

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "app-lt-private-instance"
    }
  }
}

resource "aws_autoscaling_group" "app_asg" {
  desired_capacity = 1
  max_size         = 5
  min_size         = 1

  force_delete        = true
  vpc_zone_identifier = [aws_subnet.private_subnet[0].id]
  target_group_arns   = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "app-asg-instance"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
}
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 50
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "low-cpu"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 30
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
}

resource "aws_instance" "public_instance_1" {
  count = 1

  ami = data.aws_ami.ubuntu.id

  instance_type = "t2.micro"

  key_name = aws_key_pair.key_pair.key_name

  subnet_id = aws_subnet.public_subnet[0].id

  depends_on = [aws_internet_gateway.igw]

  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.instance-profile.name

  root_block_device {
    volume_size = 30
  }

  tags = {
    Name = "dev-bastion-server-use1-${count.index}"
  }
}

resource "aws_instance" "public_instance_2" {
  count = 1

  ami = data.aws_ami.ubuntu.id

  instance_type = "t2.micro"

  key_name = aws_key_pair.key_pair.key_name

  subnet_id = aws_subnet.public_subnet[1].id

  depends_on = [aws_internet_gateway.igw]

  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.instance-profile.name

  root_block_device {
    volume_size = 30
  }

  tags = {
    Name = "dev-nginx-server-use1-${count.index}"
  }

  provisioner "remote-exec" {
    inline = ["echo 'ssh connection'"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = data.aws_ssm_parameter.ssh_private_key.value
      #private_key= file("~/.ssh/key2")
      agent = false
      #password   = var.ssh_pass
      host    = aws_instance.public_instance_2[0].public_ip
      port    = var.ssh_port
      timeout = "5m"

    }
  }
provisioner "local-exec" {
    command = <<EOT
      "sleep 7m" &&
      mkdir -p ${path.module}/.ssh &&
      echo '${data.aws_ssm_parameter.ssh_private_key.value}' > ${path.module}/.ssh/temp_key &&
      chmod 644 ${path.module}/.ssh/temp_key &&
      ansible --version &&
      ANSIBLE_HOST_KEY_CHECKING=false 
      ansible-playbook \
      -i ../ansible/inventory.ini 
      ../ansible/playbook.yml \
      --private-key ${path.module}/.ssh/temp_key &&
      rm -f ${path.module}/.ssh/temp_key
      EOT
  }


}

resource "aws_instance" "private_instance" {
  count = 2

  ami = data.aws_ami.ubuntu.id

  instance_type = "t2.micro"

  key_name = aws_key_pair.key_pair.key_name

  subnet_id = aws_subnet.private_subnet[0].id

  depends_on = [aws_nat_gateway.nat_gw_pr]

  vpc_security_group_ids = [aws_security_group.private_sg.id]

  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.instance-profile.name

  root_block_device {
    volume_size = 30
  }

  tags = {
    Name = "dev-appdeployment-use1-${count.index + 1}"
  }
}

output "public_instance_1_id" {
  value       = aws_instance.public_instance_1[0].id
  description = "bastion-hostserver ids"
}

output "public_instance_2_id" {
  value       = aws_instance.public_instance_2[0].id
  description = "nginx-server ids"
}

output "private_instance_id" {
  value       = aws_instance.private_instance[0].id
  description = "private-instance ids"
}

output "bastion_public_instance_ip" {
  value       = aws_instance.public_instance_1[0].public_ip
  description = "bastion-hostserver-public ip"
}

output "nginx_public_instance_ip" {
  value       = aws_instance.public_instance_2[0].public_ip
  description = "nginx-server-public ip"
}

output "private_instance_ip" {
  value       = aws_instance.private_instance[0].private_ip
  description = "private ips"
}

output "public_instance_1_state" {
  value       = aws_instance.public_instance_1[0].instance_state
  description = "bastion-hostserver-instance state"
}

output "public_instance_2_state" {
  value       = aws_instance.public_instance_2[0].instance_state
  description = "nginx-server-instance state"
}

output "app_asg_name" {
  description = "Auto Scaling Group Name"
  value       = aws_autoscaling_group.app_asg.name
}

output "app_asg_id" {
  value       = aws_autoscaling_group.app_asg.id
  description = "Auto Scaling Group ID"
}
