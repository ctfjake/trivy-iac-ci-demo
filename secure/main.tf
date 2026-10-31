# FIXED version of ../insecure. This is the "paved road": the same
# resources with encryption on (customer managed keys), public access
# blocked, SSH scoped to one CIDR, egress scoped, and the IAM policy
# narrowed. Trivy's config scan passes on this directory at the
# HIGH,CRITICAL gate. Nothing here is a real account or credential.

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

# --- Customer managed KMS key for S3 encryption ---

resource "aws_kms_key" "s3" {
  description             = "CMK for demo S3 buckets"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

# --- S3 bucket: encrypted with a CMK, private, logged, versioned ---

resource "aws_s3_bucket" "data" {
  bucket = "trivy-demo-secure-data"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "data" {
  bucket        = aws_s3_bucket.data.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Log destination bucket: also encrypted and locked down ---

resource "aws_s3_bucket" "logs" {
  bucket = "trivy-demo-secure-logs"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Security group: SSH from one internal CIDR, egress scoped ---

resource "aws_security_group" "scoped" {
  name        = "trivy-demo-scoped-sg"
  description = "Allow SSH from the corporate VPN range only"

  ingress {
    description = "SSH from corporate VPN"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    description = "HTTPS to the internal network"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }
}

# --- RDS instance: encrypted, not publicly accessible ---

resource "aws_db_instance" "database" {
  identifier                  = "trivy-demo-db"
  engine                      = "postgres"
  instance_class              = "db.t3.micro"
  allocated_storage           = 20
  username                    = "admin"
  manage_master_user_password = true
  storage_encrypted           = true
  publicly_accessible         = false
  skip_final_snapshot         = true
}

# --- EBS volume: encrypted at rest ---

resource "aws_ebs_volume" "disk" {
  availability_zone = "us-east-1a"
  size              = 20
  encrypted         = true
}

# --- IAM policy: scoped to one action on one resource ---

resource "aws_iam_policy" "reader" {
  name = "trivy-demo-reader"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::trivy-demo-secure-data/*"
      }
    ]
  })
}
