# Trivy Infrastructure-as-Code continuous integration demo

This repository shows one thing: a scanner catching bad cloud infrastructure in
continuous integration (CI) and failing the build so that infrastructure never
ships.

The scanner is [Trivy](https://github.com/aquasecurity/trivy). The infrastructure
is Terraform for Amazon Web Services (AWS). The gate is a GitHub Actions workflow.

## What this demonstrates

Infrastructure-as-Code (IaC) means you describe your cloud setup in files instead
of clicking around a console. That is great for repeatability. It also means a
misconfigured security group or an unencrypted database is now a text file you can
scan before it ever reaches AWS.

So that is what happens here. On every push and pull request, Trivy reads the
Terraform and checks it against a library of misconfiguration rules. If it finds a
high or critical problem, it exits non-zero and the GitHub Actions run goes red.
A red run blocks the merge. The bad infrastructure never gets applied.

## The second control / policy-as-code / paved road framing

This is the framing I care about for product security.

A single control fails. People forget to turn on encryption. A reviewer misses an
open port. You do not want the only thing standing between a mistake and production
to be one human remembering one checkbox.

So you add a second control that does not get tired. Trivy in CI is that control.
It is policy-as-code: the rules about what "secure enough" means live in a scanner
that runs automatically, the same way every time, on every change. Nobody has to
remember to run it.

And it builds a paved road. The `secure/` directory in this repo is the easy path.
It passes the scan with no fuss. When the secure way is also the path of least
resistance, people take it. The control is not there to punish engineers. It is
there to make the safe thing the default thing.

## Before and after

Two directories, same resources, opposite outcomes.

`insecure/` is the "before". It is deliberately broken so Trivy has something to
catch. It has:

- An Amazon Simple Storage Service (S3) bucket with a public-read access control
  list, no customer managed encryption key, no logging, and no versioning.
- A security group that allows Secure Shell (SSH, port 22) and Remote Desktop
  Protocol (RDP, port 3389) from `0.0.0.0/0`, meaning the entire internet, plus
  unrestricted outbound traffic.
- A Relational Database Service (RDS) instance with storage encryption turned off
  and public access turned on.
- An Elastic Block Store (EBS) volume with encryption turned off.
- An Identity and Access Management (IAM) policy that grants every action on every
  resource.

`secure/` is the "after". Same resources, fixed:

- The S3 buckets use a customer managed Key Management Service (KMS) key, block all
  public access, log to a second bucket, and keep versions.
- The security group allows SSH from one internal range only, and scopes outbound
  traffic instead of opening it to the world.
- The RDS instance has encryption on and public access off.
- The EBS volume is encrypted.
- The IAM policy grants one action on one resource.

Every file in `insecure/` carries a header comment saying the problems are
intentional teaching examples. Do not deploy that directory.

## How to read the failing run

Open the Actions tab and pick a run. You will see four jobs.

- `Scan insecure/ (expected to FAIL)` ends red. Open it and read the Trivy step.
  You will see a table of findings, each with a check identifier (for example
  `AVD-AWS-0107`), a severity, and the exact file and line it fired on. Below the
  table the step exits with code 1, which is what fails the job and the run.
- `Scan secure/ (expected to PASS)` ends green. Same scanner, same settings, no
  high or critical findings, exit code 0.
- `Scan intended-public/ (expected to PASS)` ends green too, but for a more
  interesting reason: that bucket is public on purpose, so the public access
  checks do fire, and each one is waived by a reasoned, time-boxed inline Trivy
  ignore. The encryption check is not waived; it is fixed. See the "Exceptions
  and accountability" section below.
- `Ignore inventory (informational)` always ends green. It does not gate the
  build. It reads the whole tree and writes a table of every active suppression
  to the run summary, so no waiver is invisible.

The red job is the whole point. That is the moment a bad change would have been
stopped. The failure is not a broken workflow. It is the scanner doing its job and
reporting real findings.

## Running it yourself

You need Trivy installed locally. Then:

```
# Fails, because the infrastructure is insecure.
trivy config --severity HIGH,CRITICAL --exit-code 1 ./insecure

# Passes, because the infrastructure is on the paved road.
trivy config --severity HIGH,CRITICAL --exit-code 1 ./secure

# Passes, because the only findings are public access checks that are
# waived with reasoned, time-boxed inline ignores, and encryption is fixed.
trivy config --severity HIGH,CRITICAL --exit-code 1 ./intended-public
```

## Tuning the policy

Real teams tune these gates. Two common levers are in play here.

- Severity threshold. This demo gates on `HIGH,CRITICAL` so the signal is the
  stuff that actually matters. You can widen it to `MEDIUM` and below as a team
  matures, or tighten it.
- Ignore list. Sometimes you accept a specific finding as a known, documented,
  time-boxed risk. See `.trivyignore.example` for how that looks. The workflow
  keeps the core gate failing on purpose, so the ignore wiring is shown commented
  out, not active.

## The workflow

`.github/workflows/trivy.yml` runs the official `aquasecurity/trivy-action`, pinned
to a released version tag so the behavior does not drift under us. It runs
`scan-type: config` (the Infrastructure-as-Code scanner), prints a readable table,
filters to `HIGH,CRITICAL`, and sets `exit-code: '1'` so findings fail the build.

## Exceptions and accountability

Sometimes a finding is not a mistake. A bucket is supposed to be public because it
serves a static website. In that case you do not want to disable the scanner and you
do not want to live with a permanently red build. You want to accept exactly that one
finding, on the record, with a reason and an expiry, and you want someone on the
security side to know it happened. The `intended-public/` directory is the worked
example of that, and this section explains the four mechanisms that keep an exception
honest.

### The inline ignore syntax

Trivy lets you waive a specific finding with a comment placed directly above the
resource the finding fires on:

```
#trivy:ignore:AVD-AWS-0086 exp:2027-10-31
resource "aws_s3_bucket" "site" {
```

Two details matter.

First, the waiver is per resource. Trivy fires different checks on different
resources. The public access block checks (`AVD-AWS-0086`, `AVD-AWS-0087`,
`AVD-AWS-0091`, `AVD-AWS-0093`) fire on the `aws_s3_bucket` resource, while a public
read access control list check (`AVD-AWS-0092`) fires on the separate
`aws_s3_bucket_acl` resource. So an ignore comment only silences the checks that fire
on the resource it sits above. A bucket that is public through both an ACL and the
access block would need ignore comments above both resources.

Second, every waiver carries a reason and an expiry. The `exp:` date is a forcing
function: when it passes, Trivy stops honoring the ignore and the finding comes back,
which pushes the exception back in front of a human instead of letting it rot forever.
In `intended-public/main.tf` each of the four ignores names the specific control it
waives, gives the reason (the bucket must serve objects to anonymous website
visitors), and sets an expiry.

### Ignoring public access does not waive encryption

This is the part people get wrong. Waiving the public access checks silences only
those checks. The encryption check (`AVD-AWS-0132`) keeps firing until you address it
separately. That is a feature, not a gap: you accept only the risk you actually meant
to accept. So the `intended-public/` bucket does not ignore the encryption finding, it
fixes it, with a customer managed Key Management Service (KMS) key. It also keeps
access logging and versioning on. The only thing public about that bucket is the one
thing you asked for.

### The four accountability mechanisms

1. CODEOWNERS review gate. `.github/CODEOWNERS` assigns every place a finding can be
   suppressed (the `.trivyignore` files and the `intended-public/` directory where
   inline ignores live) to a security owner. On any pull request that touches those
   paths, GitHub automatically requests that owner's review. Enforce it with branch
   protection that requires CODEOWNERS review, and a waiver cannot merge without a
   security sign off. The owner in this demo is a placeholder you replace with your own
   `@org/security-team`.

2. The ignore-inventory continuous integration step. The `ignore-inventory` job reads
   the whole tree on every run and writes a table of every active suppression (file,
   line, check identifier, reason or expiry) to the run summary. On a pull request it
   also diffs against the base branch and lists the ignores this pull request newly
   adds, under a heading that calls for security review. It is informational and never
   fails the build, because the gate is the CODEOWNERS review, not a hard block. Its
   value is that no suppression is ever invisible.

3. Trivy suppressed-findings listing. Some Trivy scanners accept a flag to print what
   was suppressed, so the scan log itself shows the waived findings. The installed
   Trivy version 0.70.0 has no such flag for `trivy config` (there is no
   `--show-suppressed` on that subcommand), so this demo does not wire it. If a future
   version adds it, pass it on the scan jobs and the suppressed findings appear in the
   scan log alongside the inventory. Until then the ignore-inventory job is the
   listing.

4. Expiry as a forcing function. The `exp:` date on each inline ignore means a waiver
   is temporary by construction. When it lapses the finding returns and fails the gate,
   so a stale exception cannot quietly outlive its reason. Renewing it is a new pull
   request, which pulls the security owner back in through mechanism one.

### Live notification as an extension

This demo stops at making waivers visible in the run and gating them on review. A
production setup often wants an active notification too: post to a Slack channel or a
generic webhook, or open a tracking issue, whenever a pull request adds a new ignore.
That needs a secret (a Slack token or webhook Uniform Resource Locator, or a token
with issue write access), so it is deliberately not wired here. The ignore-inventory
job already computes the newly added ignores, so adding a step that posts them to a
webhook is the natural extension point once you supply the secret.
