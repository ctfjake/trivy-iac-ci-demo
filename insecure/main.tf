# INTENTIONAL MISCONFIGURATIONS - teaching example, do NOT deploy.
# Every resource in this file is deliberately insecure so Trivy's
# config scanner has something to catch. The fixed version lives
# in ../secure. Nothing here is a real account or credential.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- S3 bucket: no encryption, public, no logging, no versioning ---

resource "aws_s3_bucket" "data" {
  bucket = "trivy-demo-insecure-data"
}

# Public-read ACL exposes object contents to the whole internet.
resource "aws_s3_bucket_acl" "data" {
  bucket = aws_s3_bucket.data.id
  acl    = "public-read"
}

# --- Security group: SSH and RDP open to the entire internet ---

resource "aws_security_group" "open" {
  name        = "trivy-demo-open-sg"
  description = "Allow SSH and RDP from anywhere"

  ingress {
    description = "SSH from the world"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "RDP from the world"
    from_port   = 3389
    to_port     = 3389
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

# --- RDS instance: storage encryption disabled, publicly accessible ---

resource "aws_db_instance" "database" {
  identifier          = "trivy-demo-db"
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username            = "admin"
  password            = "ChangeMe123!"
  storage_encrypted   = false
  publicly_accessible = true
  skip_final_snapshot = true
}

# --- EBS volume: encryption disabled ---

resource "aws_ebs_volume" "disk" {
  availability_zone = "us-east-1a"
  size              = 20
  encrypted         = false
}

# --- IAM policy: wildcard action on wildcard resource (god mode) ---

resource "aws_iam_policy" "admin" {
  name = "trivy-demo-admin"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}
