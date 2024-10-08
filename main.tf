terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

resource "aws_vpc" "infra_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "infra_vpc"
  }
}

resource "aws_internet_gateway" "infra_gw" {
  vpc_id = aws_vpc.infra_vpc.id

  tags = {
    Name = "infra_gw"
  }

  depends_on = [aws_vpc.infra_vpc]
}

resource "aws_subnet" "infra_subnet" {
  vpc_id            = aws_vpc.infra_vpc.id
  cidr_block        = var.subnet_cidr
  availability_zone = var.availability_zone


  tags = {
    Name = "infra_subnet"
  }

  depends_on = [aws_vpc.infra_vpc]
}

resource "aws_route_table" "infra_rt" {
  vpc_id = aws_vpc.infra_vpc.id

  route {
    cidr_block = var.default_cidr
    gateway_id = aws_internet_gateway.infra_gw.id
  }

  route {
    cidr_block = aws_vpc.infra_vpc.cidr_block
    gateway_id = "local"
  }

  tags = {
    Name = "tf_route_table"
  }

  depends_on = [aws_vpc.infra_vpc, aws_internet_gateway.infra_gw]
}

resource "aws_route_table_association" "infra_rta" {
  subnet_id      = aws_subnet.infra_subnet.id
  route_table_id = aws_route_table.infra_rt.id

  depends_on = [aws_subnet.infra_subnet, aws_route_table.infra_rt]
}

resource "aws_main_route_table_association" "infra_vpc_rta" {
  vpc_id         = aws_vpc.infra_vpc.id
  route_table_id = aws_route_table.infra_rt.id

  depends_on = [aws_vpc.infra_vpc, aws_route_table.infra_rt]
}

# Will require in the future
# resource "aws_network_interface" "infra_ni" {
#   subnet_id   = aws_subnet.infra_subnet.id
#   private_ips = ["10.0.0.10"]

#   attachment {
#     instance = 
#   }

#   # tags = {
#   #   Name = "tf_primary_network_interface"
#   # }
# }

resource "aws_iam_role" "tf_jenkins_role" {
  name = "tf_jenkins_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_default_security_group" "infra_dsg" {
  vpc_id = aws_vpc.infra_vpc.id

  ingress {
    protocol    = var.protocol
    self        = true
    from_port   = var.https_port
    to_port     = var.https_port
    cidr_blocks = [var.default_cidr]
  }

  ingress {
    protocol    = var.protocol
    self        = true
    from_port   = var.http_port
    to_port     = var.http_port
    cidr_blocks = [var.default_cidr]
  }

  # SSH ports
  # ingress {
  #   protocol  = "tcp"
  #   self      = true
  #   from_port = 0
  #   to_port   = 22
  #   cidr_blocks = ["0.0.0.0/0"]
  # }


  egress {
    from_port   = var.jenkins_egress_from_port
    to_port     = var.jenkins_egress_to_port
    protocol    = var.jenkins_egress_protocol
    cidr_blocks = [var.default_cidr]
  }

  depends_on = [aws_vpc.infra_vpc]
}

resource "aws_instance" "tf_jenkins" {
  ami               = var.jenkins_ami
  availability_zone = var.availability_zone
  instance_type     = var.instance_type
  subnet_id         = aws_subnet.infra_subnet.id

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "tf-jenkins"
  }

  depends_on = [aws_subnet.infra_subnet]
}

// Resource to create an EIP
resource "aws_eip" "jenkins_eip" {
  domain = "vpc"
}

data "aws_route53_zone" "infra_zone" {
  zone_id = var.infra_zone
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.tf_jenkins.id
  allocation_id = aws_eip.jenkins_eip.id

  depends_on = [aws_instance.tf_jenkins]
}

resource "aws_route53_record" "jenkins_dns_rec" {
  zone_id = data.aws_route53_zone.infra_zone.zone_id
  name    = var.infra_domain
  type    = "A"
  ttl     = var.jenkins_dns_ttl
  records = [aws_eip.jenkins_eip.public_ip]
}
