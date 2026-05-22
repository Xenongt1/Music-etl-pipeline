terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local backend for now — remote state (S3 + DynamoDB lock) deferred until spine works
  backend "local" {}
}

provider "aws" {
  region = var.aws_region
  # No profile here — set AWS_PROFILE=mubarak-admin in your shell before running terraform.
  # This keeps the code identity-agnostic and safe to commit.
}

# Used by s3.tf to build a globally-unique bucket name
data "aws_caller_identity" "current" {}
