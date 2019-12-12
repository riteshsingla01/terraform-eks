variable "cluster-name" {
  default = "alsac-eks"
  type    = "string"
}

variable "aws_region" {
  description = "The AWS region to create things in."
  default     = "us-east-1"
}

variable "inst-type" {
  description = "EKS worker instance type."
  default = "t2.micro"
  type    = "string"
}
