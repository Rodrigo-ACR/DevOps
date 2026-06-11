terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ── 1. CLAVE SSH ─────────────────────────────────────────────────
resource "tls_private_key" "clave_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "key_pair" {
  key_name   = "clave-devops-ep2"
  public_key = tls_private_key.clave_ssh.public_key_openssh
}

resource "local_file" "guardar_clave" {
  content         = tls_private_key.clave_ssh.private_key_pem
  filename        = "${path.module}/clave-devops-ep2.pem"
  file_permission = "0400"
}

# ── 2. RED (VPC, SUBREDES, GATEWAYS) ────────────────────────────
resource "aws_vpc" "vpc_principal" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "vpc-devops-ep2" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_principal.id
  tags   = { Name = "igw-devops-ep2" }
}

resource "aws_eip" "eip_nat" {
  domain = "vpc"
  tags   = { Name = "eip-nat-ep2" }
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.eip_nat.id
  subnet_id     = aws_subnet.subred_web.id
  tags          = { Name = "nat-gw-ep2" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_subnet" "subred_web" {
  vpc_id                  = aws_vpc.vpc_principal.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "subred-publica-web" }
}

resource "aws_subnet" "subred_app" {
  vpc_id            = aws_vpc.vpc_principal.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "subred-privada-app" }
}

# ── 3. TABLAS DE RUTEO ───────────────────────────────────────────
resource "aws_route_table" "rt_publica" {
  vpc_id = aws_vpc.vpc_principal.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "rt-publica-ep2" }
}

resource "aws_route_table_association" "web_assoc" {
  subnet_id      = aws_subnet.subred_web.id
  route_table_id = aws_route_table.rt_publica.id
}

resource "aws_route_table" "rt_privada" {
  vpc_id = aws_vpc.vpc_principal.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = { Name = "rt-privada-ep2" }
}

resource "aws_route_table_association" "app_assoc" {
  subnet_id      = aws_subnet.subred_app.id
  route_table_id = aws_route_table.rt_privada.id
}

# ── 4. SECURITY GROUPS ───────────────────────────────────────────
resource "aws_security_group" "sg_web" {
  name        = "sgweb-ep2"
  description = "Trafico web publico"
  vpc_id      = aws_vpc.vpc_principal.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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

resource "aws_security_group" "sg_app" {
  name        = "sgapp-ep2"
  description = "Trafico desde capa web"
  vpc_id      = aws_vpc.vpc_principal.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_web.id]
  }

  ingress {
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_web.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_web.id]
  }

  ingress {
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    security_groups = [aws_security_group.sg_web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── 5. INSTANCIAS EC2 ────────────────────────────────────────────
resource "aws_instance" "ec2_web" {
  ami                    = "ami-00e801948462f718a"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.subred_web.id
  vpc_security_group_ids = [aws_security_group.sg_web.id]
  key_name               = aws_key_pair.key_pair.key_name
  tags                   = { Name = "ec2-web" }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install docker -y
              systemctl enable docker
              systemctl start docker
              usermod -aG docker ec2-user
              yum install git -y
              EOF
}

resource "aws_eip" "eip_web" {
  instance = aws_instance.ec2_web.id
  domain   = "vpc"
  tags     = { Name = "eip-ec2-web" }
}

resource "aws_instance" "ec2_app" {
  ami                    = "ami-00e801948462f718a"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.subred_app.id
  vpc_security_group_ids = [aws_security_group.sg_app.id]
  key_name               = aws_key_pair.key_pair.key_name
  tags                   = { Name = "ec2-app" }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install docker -y
              systemctl enable docker
              systemctl start docker
              usermod -aG docker ec2-user
              yum install git -y
              EOF
}

# ── 6. REPOSITORIOS ECR ──────────────────────────────────────────
resource "aws_ecr_repository" "ecr_frontend" {
  name         = "innovatech-frontend"
  force_delete = true
  tags         = { Name = "ecr-frontend" }
}

resource "aws_ecr_repository" "ecr_backend_despachos" {
  name         = "innovatech-backend-despachos"
  force_delete = true
  tags         = { Name = "ecr-backend-despachos" }
}

resource "aws_ecr_repository" "ecr_backend_ventas" {
  name         = "innovatech-backend-ventas"
  force_delete = true
  tags         = { Name = "ecr-backend-ventas" }
}

# ── 7. OUTPUTS ───────────────────────────────────────────────────
output "ip_publica_web" { value = aws_eip.eip_web.public_ip }
output "ip_privada_app" { value = aws_instance.ec2_app.private_ip }
output "ecr_frontend" { value = aws_ecr_repository.ecr_frontend.repository_url }
output "ecr_despachos" { value = aws_ecr_repository.ecr_backend_despachos.repository_url }
output "ecr_ventas" { value = aws_ecr_repository.ecr_backend_ventas.repository_url }
