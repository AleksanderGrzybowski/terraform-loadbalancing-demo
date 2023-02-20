locals {
  region = "eu-central-1"

  vpc_cidr     = "192.168.69.0/24"
  subnet_cidrs = {
    a = "192.168.69.0/25"
    b = "192.168.69.128/25"
  }

  instance_type = "t3a.nano"
  ami           = "ami-0d1ddd83282187d18"
  asg_max_size  = 2
}

provider "aws" {
  region = "eu-central-1"
}

resource "aws_vpc" "demo_vpc" {
  cidr_block = local.vpc_cidr

  tags = { Name = "demo_vpc" }
}

resource "aws_internet_gateway" "demo_igw" {
  vpc_id = aws_vpc.demo_vpc.id

  tags = { Name = "demo_igw" }
}

resource "aws_subnet" "demo_subnet" {
  for_each = local.subnet_cidrs

  vpc_id            = aws_vpc.demo_vpc.id
  cidr_block        = each.value
  availability_zone = "eu-central-1${each.key}"

  tags = { Name = "demo_subnet_${each.key}" }
}

resource "aws_route_table" "demo_route_table" {
  vpc_id = aws_vpc.demo_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo_igw.id
  }

  tags = { Name = "demo_route_table" }
}

resource "aws_route_table_association" "demo_route_table_association" {
  for_each = local.subnet_cidrs

  route_table_id = aws_route_table.demo_route_table.id
  subnet_id      = aws_subnet.demo_subnet[each.key].id
}

resource "aws_security_group" "demo_security_group" {
  vpc_id = aws_vpc.demo_vpc.id

  ingress {
    from_port   = 0
    protocol    = "ALL"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    protocol    = "ALL"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "demo_security_group" }
}

resource "aws_launch_template" "demo_launch_template" {
  name          = "demo_lt"
  instance_type = local.instance_type
  image_id      = local.ami
  key_name      = "id_rsa"

  placement {
    availability_zone = "${local.region}${keys(local.subnet_cidrs)[0]}"
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.demo_security_group.id]
  }

  user_data = base64encode(file("setup.sh"))
}

resource "aws_alb_target_group" "demo_tg" {
  name        = "demotg"
  vpc_id      = aws_vpc.demo_vpc.id
  target_type = "instance"
  protocol    = "HTTP"
  port        = 80
}

resource "aws_autoscaling_group" "demo_asg" {
  name = "demo_asg"

  launch_template {
    id      = aws_launch_template.demo_launch_template.id
    version = aws_launch_template.demo_launch_template.latest_version

  }
  vpc_zone_identifier = [for k, v in aws_subnet.demo_subnet : v.id]
  min_size            = 1
  max_size            = local.asg_max_size
  desired_capacity    = local.asg_max_size
  target_group_arns   = [aws_alb_target_group.demo_tg.arn]
}

resource "aws_alb" "demo_alb" {
  name               = "demoalb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.demo_security_group.id]
  subnets            = [for k, v in aws_subnet.demo_subnet : v.id]
}

resource "aws_alb_listener" "demo_alb_listener" {
  load_balancer_arn = aws_alb.demo_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    forward {
      target_group { arn = aws_alb_target_group.demo_tg.arn }
    }
  }
}

output "alb_public_dns" {
  value = aws_alb.demo_alb.dns_name
}
