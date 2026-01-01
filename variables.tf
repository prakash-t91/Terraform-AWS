variable "vpc-name" {
  type = string
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "azs" {
  description = "List of Availability Zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "igw-name" {
  type = string
}

variable "private-rt-name" {
  type = string
}

variable "public-rt-name" {
  type = string
}

variable "subnet-name" {
  type    = string
  default = "public-subnet"
}

variable "subnet_id" {
  type = list(string)
}

variable "instance_id" {
  type    = string
  default = ""
}

variable "instance-name" {
  type    = string
  default = "Main-Ec2-Instance"
}
variable "key_name" {
  type    = string
  default = "key2"
}

variable "ssh_port" {
  type    = number
  default = 22
}
variable "iam-role" {
  type    = string
  default = "Terraform"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 Instance"
}
variable "inventory_path" {
  default = "./inventory.ini"
}
