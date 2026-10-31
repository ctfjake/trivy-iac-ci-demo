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

Open the Actions tab and pick a run. You will see two jobs.

- `Scan insecure/ (expected to FAIL)` ends red. Open it and read the Trivy step.
  You will see a table of findings, each with a check identifier (for example
  `AVD-AWS-0107`), a severity, and the exact file and line it fired on. Below the
  table the step exits with code 1, which is what fails the job and the run.
- `Scan secure/ (expected to PASS)` ends green. Same scanner, same settings, no
  high or critical findings, exit code 0.

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
