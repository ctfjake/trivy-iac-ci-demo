# ACCEPTED EXCEPTION PATTERN: public on purpose, reviewed, time-boxed,
# still encrypted and logged and versioned.
#
# This bucket hosts static website assets that MUST be readable by anonymous
# visitors, so the four Amazon Simple Storage Service (S3) public access block
# controls are deliberately not enforced here. That is a reviewed, documented
# risk, not an accident. Each waiver below is an inline Trivy ignore carrying a
# plain reason and an expiry date (exp:), so the exception is time boxed and
# comes back for review instead of living forever.
#
# Important: waiving the public access controls does NOT waive anything else.
# The bucket is still hardened the way any bucket would be:
#   - server side encryption ON, with a customer managed key (CMK)
#   - access logging ON, to a locked down log bucket
#   - versioning ON
# Trivy still enforces the encryption check (AVD-AWS-0132); we FIX that rather
# than ignore it, so we only ever accept exactly the risk we mean to.
#
# Nothing here is a real account or credential.

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
  description             = "CMK for the intended-public demo buckets"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

# --- Public static-website bucket ---
#
# The four inline ignores below each name one public access control we are
# knowingly not enforcing, with a reason and an expiry. They sit DIRECTLY above
# the aws_s3_bucket resource because that is the resource Trivy fires these
# checks on. The encryption, logging and versioning checks are satisfied by the
# sibling resources further down, not waived.
#
# AVD-AWS-0086 block_public_acls: public read of website objects is the point.
# AVD-AWS-0087 block_public_policy: a public-read bucket policy is required.
# AVD-AWS-0091 ignore_public_acls: anonymous GET access must be honored.
# AVD-AWS-0093 restrict_public_buckets: the bucket is public by design.
# Reviewed by: security-team. Re-review on the exp date below.
#trivy:ignore:AVD-AWS-0086 exp:2027-10-31
#trivy:ignore:AVD-AWS-0087 exp:2027-10-31
#trivy:ignore:AVD-AWS-0091 exp:2027-10-31
#trivy:ignore:AVD-AWS-0093 exp:2027-10-31
resource "aws_s3_bucket" "site" {
  bucket = "trivy-demo-intended-public-site"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "site" {
  bucket        = aws_s3_bucket.site.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "log/"
}

# --- Log destination bucket: private, encrypted, access blocked ---

resource "aws_s3_bucket" "logs" {
  bucket = "trivy-demo-intended-public-logs"
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
