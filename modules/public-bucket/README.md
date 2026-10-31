# modules/public-bucket

A reusable Terraform module for an Amazon Simple Storage Service (S3) bucket
that is intentionally public but safe by default. This is the "paved road"
version: the easy public option that is already hardened, so teams do not have
to hand roll a public bucket and quietly get it wrong.

## What it does

The only public thing about this bucket is anonymous read of objects, and even
that is granted the safe way:

- Anonymous read comes from a SCOPED bucket policy (`s3:GetObject` on the
  objects only), not a blanket public-read access control list (ACL).
- ACLs are disabled entirely with bucket-owner-enforced ownership.
- Object listing is OFF. The policy never grants `s3:ListBucket`, so callers
  can read a known object but cannot enumerate the bucket.
- Transport Layer Security (TLS) is required. A policy condition denies any
  request where `aws:SecureTransport` is false.
- Encryption at rest uses a customer managed key (CMK).
- Access logging is ON, delivered to a caller supplied, locked-down log bucket.
- Versioning is ON.
- The public access block still blocks and ignores public ACLs; it allows
  public policies only, which is what the single scoped read policy needs.

Because the public read is granted by a reviewed policy rather than an
accidental ACL, there is nothing to waive at the ACL layer.

## Inputs

- `bucket_name` (string, required): name of the public bucket to create.
- `log_bucket_id` (string, required): ID of an existing locked-down bucket to
  receive access logs.
- `log_prefix` (string, optional, default `log/`): key prefix for access logs.

## Outputs

- `bucket_id`: ID of the created bucket.
- `bucket_arn`: ARN of the created bucket.

## Note

This module is valid HashiCorp Configuration Language (HCL) and is not wired
into a live continuous integration (CI) scan job. It documents the safe
default. The `intended-public/` directory shows the other path: a public bucket
whose public access controls are waived with reasoned, time-boxed inline Trivy
ignores.
