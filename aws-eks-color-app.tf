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
  enable_dns_hostnames  = true #The VPC must have DNS hostname and DNS resolution support 
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

# Attach Policy to Role 
resource "aws_iam_role_policy_attachment" "ditwl-role-eks-01-policy-attachment-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.ditwl-role-eks-01.name
}

# EKS Node Group Assume Role, manage EC2 Instances
data "aws_iam_policy_document" "ditwl-ipd-ng-eks-01" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "ditwl-role-ng-eks-01" {
  name = "eks-node-group-example"
  assume_role_policy = data.aws_iam_policy_document.ditwl-ipd-ng-eks-01.json
}

# Attach Policy to Role for EKS Node Group: AmazonEKSWorkerNodePolicy
resource "aws_iam_role_policy_attachment" "ditwl-role-eks-01-policy-attachment-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.ditwl-role-ng-eks-01.name
}

# Attach Policy to Role for EKS Node Group: AmazonEKS_CNI_Policy
resource "aws_iam_role_policy_attachment" "ditwl-role-eks-01-policy-attachment-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.ditwl-role-ng-eks-01.name
}

# Attach Policy to Role for EKS Node Group: AmazonEC2ContainerRegistryReadOnly
resource "aws_iam_role_policy_attachment" "ditwl-role-eks-01-policy-attachment-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.ditwl-role-ng-eks-01.name
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

#EKS Node Group (Worker Nodes)
resource "aws_eks_node_group" "ditwl-eks-ng-eks-01" {
  cluster_name    = aws_eks_cluster.ditwl-eks-01.name
  node_group_name = "ditwl-eks-ng-eks-01"
  node_role_arn   = aws_iam_role.ditwl-role-ng-eks-01.arn
  subnet_ids      = [aws_subnet.ditwl-sn-za-pro-pub-00.id, aws_subnet.ditwl-sn-zb-pro-pub-04.id]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.ditwl-role-eks-01-policy-attachment-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.ditwl-role-eks-01-policy-attachment-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.ditwl-role-eks-01-policy-attachment-AmazonEC2ContainerRegistryReadOnly,
  ]

  # Allow external changes without Terraform plan difference
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

}
