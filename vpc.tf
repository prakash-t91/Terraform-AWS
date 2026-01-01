resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc-name
  }
}

resource "aws_subnet" "public_subnet" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnet" {
  count      = length(var.azs)
  vpc_id     = aws_vpc.vpc.id
  cidr_block = var.private_subnet_cidrs[count.index]
  #cidr_block        = var.private_subnet_cidrs[count.index + 1]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

resource "aws_network_interface" "network_interface" {
  subnet_id       = aws_subnet.private_subnet[0].id
  private_ips     = ["10.0.3.10", "10.0.3.11"]
  security_groups = [aws_security_group.private_sg.id]
}

resource "aws_eip" "one" {
  domain = "vpc"
  #network_interface         = aws_network_interface.network_interface.id
  #associate_with_private_ip = "10.0.1.10"
}

resource "aws_eip" "two" {
  domain = "vpc"
  #network_interface         = aws_network_interface.network_interface.id
  #associate_with_private_ip = "10.0.1.11"
}

resource "aws_eip" "nat_eip" {
  count  = length(var.azs)
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gw_pb" {
  count         = length(var.azs)
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id     = aws_subnet.public_subnet[count.index].id
  depends_on    = [aws_internet_gateway.igw]
  #secondary_allocation_ids       = [aws_eip.secondary.id]
  #secondary_private_ip_addresses = ["10.0.3.0/24"]
  tags = {
    Name = "nat-gateway-ps-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "nat_gw_pr" {
  count         = length(var.azs)
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id     = aws_subnet.private_subnet[count.index].id
  #connectivity_type = "private"

  tags = {
    Name = "nat-gateway-pr-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = var.igw-name
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = var.public-rt-name
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw_pb[0].id
  }

  tags = {
    Name = var.private-rt-name
  }
}

resource "aws_route_table_association" "public_rt_association" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rt_association" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for subnet in aws_subnet.public_subnet : subnet.id]
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  #target_type = "ip"
  vpc_id = aws_vpc.vpc.id
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "alb-sg"
  }
}

resource "aws_security_group" "instance_sg" {
  vpc_id = aws_vpc.vpc.id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "instance-sg"
  }
}

resource "aws_security_group" "private_instance_sg" {
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "bastion_sg" {
  vpc_id      = aws_vpc.vpc.id
  description = "Allowing Jenkins, Sonarqube, SSH Access"
  name_prefix = "bastion-sg-"
  ingress = [
    for port in [22, 8080, 9000, 9090, 80] : {
      description      = "TLS from VPC"
      from_port        = port
      to_port          = port
      protocol         = "tcp"
      ipv6_cidr_blocks = ["::/0"]
      self             = false
      prefix_list_ids  = []
      security_groups  = []
      cidr_blocks      = ["0.0.0.0/0"]
    }
  ]

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "public-bastion-host-sg"
  }
}

resource "aws_security_group" "nginx_sg" {
  vpc_id      = aws_vpc.vpc.id
  description = "nginx-server-sg"
  name_prefix = "nginx_sg-"
  ingress = [
    for port in [22, 80, 443] : {
      description      = "TLS from VPC"
      from_port        = port
      to_port          = port
      protocol         = "tcp"
      ipv6_cidr_blocks = ["::/0"]
      self             = false
      prefix_list_ids  = []
      security_groups  = []
      cidr_blocks      = ["0.0.0.0/0"]
    }
  ]

  egress {
    from_port   = 80
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP and HTTPS"
  }
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS"
  }

  tags = {
    Name = "nginx-server-sg"
  }
}

resource "aws_security_group" "private_sg" {
  vpc_id      = aws_vpc.vpc.id
  description = "Allowing SSH Access"
  name_prefix = "private-sg-"

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "private-sg"
  }
}

output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "subnet_id" {
  value = aws_subnet.public_subnet[0].id
}

output "elastic_public_ip" {
  value = aws_eip.nat_eip[0].public_ip
}

output "elastic_private_ip" {
  value = aws_eip.nat_eip[0].private_ip
}

output "network_interface_id" {
  value = aws_network_interface.network_interface.id
}

output "alb_dns_name" {
  value = aws_lb.app_lb.dns_name
}
