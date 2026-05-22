variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short prefix applied to every resource name"
  type        = string
  default     = "music-etl"
}

variable "environment" {
  description = "Deployment environment — dev or prod"
  type        = string
  default     = "dev"
}
