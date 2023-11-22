# Copyright (C) 2018 - 2023 IT Wonder Lab (https://www.itwonderlab.com)
#
# This software may be modified and distributed under the terms
# of the MIT license.  See the LICENSE file for details.
# -------------------------------- WARNING --------------------------------
# IT Wonder Lab's best practices for infrastructure include modularizing 
# Terraform/OpenTofu configuration. 
# In this example, we define everything in a single file. 
# See other tutorials for best practices at itwonderlab.com
# -------------------------------- WARNING --------------------------------

#Define Terrraform Providers and Backend
terraform {
  required_version = "> 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#-----------------------------------------
# Default provider: AWS
#-----------------------------------------
provider "aws" {
  shared_credentials_files = ["~/.aws/credentials"]
  profile                  = "ditwl_infradmin"
  region                   = "us-east-1" //See BUG https://github.com/hashicorp/terraform-provider-aws/issues/30488
}

# VPC
resource "aws_vpc" "ditlw-vpc" {
  cidr_block = "172.21.0.0/19" #172.21.0.0 - 172.21.31.254
  tags = {
    Name = "ditlw-vpc"
  }
}

# Subnet Zone: A, Env: PRO, Type: PUBLIC, Code: 00
resource "aws_subnet" "ditwl-sn-za-pro-pub-00" {
  vpc_id                  = aws_vpc.ditlw-vpc.id
  cidr_block              = "172.21.0.0/23" #172.21.0.0 - 172.21.1.255
  map_public_ip_on_launch = true            #Assign a public IP address
  availability_zone = "us-east-1a"
  tags = {
    Name = "ditwl-sn-za-pro-pub-00"
  }
}

# Subnet Zone: B, Env: PRO, Type: PUBLIC, Code: 04
resource "aws_subnet" "ditwl-sn-zb-pro-pub-04" {
  vpc_id                  = aws_vpc.ditlw-vpc.id
  cidr_block              = "172.21.4.0/23" #172.21.4.0 - 172.21.5.255
  map_public_ip_on_launch = true            #Assign a public IP address
  availability_zone = "us-east-1b"
  tags = {
    Name = "ditwl-sn-zb-pro-pub-04"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "ditwl-ig" {
  vpc_id = aws_vpc.ditlw-vpc.id
  tags = {
    Name = "ditwl-ig"
  }
}

# Routing table for public subnet (access to Internet)
resource "aws_route_table" "ditwl-rt-pub-main" {
  vpc_id = aws_vpc.ditlw-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ditwl-ig.id
  }

  tags = {
    Name = "ditwl-rt-pub-main"
  }
}

# Set new main_route_table as main
resource "aws_main_route_table_association" "ditwl-rta-default" {
  vpc_id         = aws_vpc.ditlw-vpc.id
  route_table_id = aws_route_table.ditwl-rt-pub-main.id
}

# Create a Security Group
resource "aws_security_group" "ditwl-sg-eks-01-color-app" {
  name        = "ditwl-sg-eks-01-color-app"
  vpc_id      = aws_vpc.ditlw-vpc.id
}

# Allow access from the Internet to port 8008
resource "aws_security_group_rule" "ditwl-sr-internet-to-eks-01-color-app-8080" {
  security_group_id        = aws_security_group.ditwl-sg-eks-01-color-app.id
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  cidr_blocks              = ["0.0.0.0/0"] # Internet
}

# Allow all outbound traffic to Internet
resource "aws_security_group_rule" "ditwl-sr-all-outbund" {
  security_group_id = aws_security_group.ditwl-sg-eks-01-color-app.id
  type              = "egress"
  from_port         = "0"
  to_port           = "0"
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# EKS Cluster requires an IAM Role that allows managing AWS resources
data "aws_iam_policy_document" "ditwl-ipd-eks-01" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Role 
resource "aws_iam_role" "ditwl-role-eks-01" {
  name               = "ditwl-role-eks-01"
  assume_role_policy = data.aws_iam_policy_document.ditwl-ipd-eks-01.json
}

# Attach Policity to Role 
resource "aws_iam_role_policy_attachment" "ditwl-role-eks-01-policy-attachment-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.ditwl-role-eks-01.name
}

# EKS Cluster
resource "aws_eks_cluster" "ditwl-eks-01" {
  name     = "ditwl-eks-01"
  role_arn = aws_iam_role.ditwl-role-eks-01.arn

  vpc_config {
    subnet_ids = [aws_subnet.ditwl-sn-za-pro-pub-00.id, aws_subnet.ditwl-sn-zb-pro-pub-04.id]
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.ditwl-role-eks-01-policy-attachment-AmazonEKSClusterPolicy
  ]
}