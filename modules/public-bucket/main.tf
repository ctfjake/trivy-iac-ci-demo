# Reusable "paved road" public bucket module.
#
# This is the easy public option that is already safe by default. It is
# intentionally public (anonymous clients can read objects), but every other
# control is locked down so the only thing public about it is the one thing you
# asked for. Compared with a blanket public access control list (ACL), this:
#
#   - grants anonymous read through a SCOPED bucket policy (s3:GetObject on the
#     objects only), not a blanket public-read ACL
#   - disables ACLs entirely with bucket-owner-enforced ownership
#   - turns object listing OFF (no s3:ListBucket for anonymous callers)
#   - requires Transport Layer Security (TLS) via an aws:SecureTransport policy
#     condition, denying any non-TLS request
#   - encrypts at rest with a customer managed key (CMK)
#   - turns access logging ON to a caller supplied log bucket
#   - turns versioning ON
#   - still blocks public ACLs and ignores public ACLs; only public POLICIES
#     are allowed, which is what the scoped read policy needs
#
# Because the public read here is granted by a reviewed policy rather than an
# accidental ACL, there is nothing to waive at the ACL layer. This module is
# valid HashiCorp Configuration Language (HCL) and is not wired into a live CI
# scan job; it documents the safe default.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "bucket_name" {
  type        = string
  description = "Name of the public bucket to create."
}

variable "log_bucket_id" {
  type        = string
  description = "ID of an existing, locked-down bucket to receive access logs."
}

variable "log_prefix" {
  type        = string
  description = "Key prefix for delivered access logs."
  default     = "log/"
}

resource "aws_kms_key" "this" {
  description             = "CMK for the ${var.bucket_name} public bucket"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
}

# Bucket-owner-enforced disables ACLs completely, so public read can only ever
# come from the scoped policy below, never from an object or bucket ACL.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "this" {
  bucket        = aws_s3_bucket.this.id
  target_bucket = var.log_bucket_id
  target_prefix = var.log_prefix
}

# Block public ACLs and ignore any that appear; allow public POLICIES, because
# the scoped read policy below is the one sanctioned way in. Object listing is
# off: the policy grants GetObject on objects only, never ListBucket.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadObjectsOnly"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.this.arn}/*"
      },
      {
        Sid       = "DenyNonTLSRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

output "bucket_id" {
  value       = aws_s3_bucket.this.id
  description = "ID of the created public bucket."
}

output "bucket_arn" {
  value       = aws_s3_bucket.this.arn
  description = "ARN of the created public bucket."
}
