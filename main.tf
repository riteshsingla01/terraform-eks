# Provider
provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Setup vpc, subnets, ig and route tables

resource "aws_vpc" "hackathon_vpc" {

  cidr_block = "10.0.0.0/16"

  tags = map(
    "Name", "hackathon_node",
    "kubernetes.io/cluster/${var.cluster-name}", "shared",
  )

}

resource "aws_subnet" "hackathon_subnets" {
  count = 3

  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = "10.0.${count.index}.0/24"
  vpc_id            = aws_vpc.hackathon_vpc.id

  tags = map(
    "Name", "hackathon_node",
    "kubernetes.io/cluster/${var.cluster-name}", "shared",
  )
}

resource "aws_internet_gateway" "hackathon_ig" {
  vpc_id = aws_vpc.hackathon_vpc.id

  tags = map(
    "Name", "hackathon_ig",
    "kubernetes.io/cluster/${var.cluster-name}", "shared",
  )

}

resource "aws_route_table" "hackathon_rt" {
  vpc_id = aws_vpc.hackathon_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hackathon_ig.id
  }

  tags = map(
    "Name", "hackathon_pub_rt",
    "kubernetes.io/cluster/${var.cluster-name}", "shared",
  )

}

resource "aws_route_table_association" "hackathon_subnets_association" {
  count = 3

  subnet_id      = "${aws_subnet.hackathon_subnets.*.id[count.index]}"
  route_table_id = "${aws_route_table.hackathon_rt.id}"

}


# IAM Role setup for EKS

resource "aws_iam_role" "hackathon-cluster" {

  name               = "hackathon-eks-cluster"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    { 
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
       },
      "Action": "sts:AssumeRole"
    } 
  ]
}
POLICY

  tags = {
    "kubernetes.io/cluster/${var.cluster-name}" = "shared"
  }
}

resource "aws_iam_role_policy_attachment" "hackathon-EKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.hackathon-cluster.name
}

resource "aws_iam_role_policy_attachment" "hackathon-EKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.hackathon-cluster.name
}

resource "aws_security_group" "hackathon-sg" {

  name        = "hackathon_node1"
  description = "Cluster communication with worker nodes"
  vpc_id      = aws_vpc.hackathon_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = map(
    "Name", "hackathon_sg1",
    "kubernetes.io/cluster/${var.cluster-name}", "shared",
  )
}

resource "aws_security_group_rule" "hackathon-sg-rule" {

  type              = "ingress"
  cidr_blocks       = ["3.215.181.135/32"]
  description       = "Allow workstation to communicate with the cluster API Server"
  from_port         = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.hackathon-sg.id
  to_port           = 443

}

resource "aws_eks_cluster" "hackathon-eks-cluster" {

  name     = var.cluster-name
  role_arn = aws_iam_role.hackathon-cluster.arn

  vpc_config {
    security_group_ids = [aws_security_group.hackathon-sg.id]
    subnet_ids         = aws_subnet.hackathon_subnets.*.id
  }

  depends_on = [
    "aws_iam_role.hackathon-cluster",
    "aws_iam_role_policy_attachment.hackathon-EKSClusterPolicy",
    "aws_iam_role_policy_attachment.hackathon-EKSServicePolicy"
  ]
}

resource "aws_iam_role" "hackathon-worker" {

  name               = "hackathon-eks-worker"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement" : [
     {
       "Effect": "Allow",
       "Principal": {
          "Service": "ec2.amazonaws.com"
       },
       "Action": "sts:AssumeRole"
     }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "hackathon-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.hackathon-worker.name
}

resource "aws_iam_role_policy_attachment" "hackathon-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.hackathon-worker.name
}

resource "aws_iam_role_policy_attachment" "hackathon-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.hackathon-worker.name
}

resource "aws_iam_instance_profile" "hackathon_profile" {
  name = "hackathon-eks-pf"
  role = aws_iam_role.hackathon-worker.name
}

resource "aws_security_group" "hackathon-worker" {
  name        = "hackathon-eks-worker-node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = aws_vpc.hackathon_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = map(
    "Name", "hackathon-worker",
    "kubernetes.io/cluster/${var.cluster-name}", "owned",
  )
}

resource "aws_security_group_rule" "hackathon-node-ingres" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.hackathon-worker.id
  source_security_group_id = aws_security_group.hackathon-worker.id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "hackathon-node-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = aws_security_group.hackathon-worker.id
  source_security_group_id = aws_security_group.hackathon-sg.id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "hackathon-cluster-ingress-node-https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.hackathon-sg.id
  source_security_group_id = aws_security_group.hackathon-worker.id
  to_port                  = 443
  type                     = "ingress"
}

data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.hackathon-eks-cluster.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

data "aws_region" "current" {}

locals {
  hackathon-node-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.hackathon-eks-cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.hackathon-eks-cluster.certificate_authority.0.data}' '${var.cluster-name}'
USERDATA
}

resource "aws_launch_configuration" "hackathon-config" {
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.hackathon_profile.name
  image_id                    = data.aws_ami.eks-worker.id
  instance_type               = ${var.inst-type}
  name_prefix                 = "hackathon-eks-cluster"
  security_groups             = [aws_security_group.hackathon-worker.id]
  user_data_base64            = "${base64encode(local.hackathon-node-userdata)}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "hackathon-asg" {
  desired_capacity     = 3
  launch_configuration = "${aws_launch_configuration.hackathon-config.id}"
  max_size             = 3
  min_size             = 2
  name                 = "hackathon-eks-asg"
  vpc_zone_identifier  = aws_subnet.hackathon_subnets.*.id

  tag {
    key                 = "Name"
    value               = "hackathon-eks-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }
}


locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH

apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.hackathon-worker.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
CONFIGMAPAWSAUTH
}

output "config_map_aws_auth" {
  value = "${local.config_map_aws_auth}"
}


[cloud_user@ashuritesh681c eks]$ cat variables.tf 
variable "cluster-name" {
  default = "alsac-eks"
  type    = "string"
}

variable "az-count" {
  default = 5
}
[cloud_user@ashuritesh681c eks]$ cat variables.tf 
variable "cluster-name" {
  default = "alsac-eks"
  type    = "string"
}

variable "az-count" {
  default = 5
}
[cloud_user@ashuritesh681c eks]$ cat output.tf 
locals {
  kubeconfig = <<KUBECONFIG


apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.hackathon-eks-cluster.endpoint}
    certificate-authority-data: ${aws_eks_cluster.hackathon-eks-cluster.certificate_authority.0.data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - "${var.cluster-name}"
KUBECONFIG
}

output "kubeconfig" {
  value = "${local.kubeconfig}"
}

output "subnet_id" {
  value = aws_subnet.hackathon_subnets.*.id
}
[cloud_user@ashuritesh681c eks]$ cat main.tf
# Provider
provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Setup vpc, subnets, ig and route tables

resource "aws_vpc" "hackathon_vpc" {

  cidr_block = "10.0.0.0/16"

  tags = map(
    "Name", "hackathon_node",
    "kubernetes.io/cluster/${var.cluster-name}", "shared",
  )

}

resource "aws_subnet" "hackathon_subnets" {
  count = 3

  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = "10.0.${count.index}.0/24"
  vpc_id            = aws_vpc.hackathon_vpc.id

  tags = map(
    "Name", "hackathon_node",
    "kubernetes.io/cluster/${var.cluster-name}", "shared",
  )
}

resource "aws_internet_gateway" "hackathon_ig" {
  vpc_id = aws_vpc.hackathon_vpc.id

  tags = map(
    "Name", "hackathon_ig",
    "kubernetes.io/cluster/${var.cluster-name}", "shared",
  )

}

resource "aws_route_table" "hackathon_rt" {
  vpc_id = aws_vpc.hackathon_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hackathon_ig.id
  }

  tags = map(
    "Name", "hackathon_pub_rt",
    "kubernetes.io/cluster/${var.cluster-name}", "shared",
  )

}

resource "aws_route_table_association" "hackathon_subnets_association" {
  count = 3

  subnet_id      = "${aws_subnet.hackathon_subnets.*.id[count.index]}"
  route_table_id = "${aws_route_table.hackathon_rt.id}"

}


# IAM Role setup for EKS

resource "aws_iam_role" "hackathon-cluster" {

  name               = "hackathon-eks-cluster"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    { 
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
       },
      "Action": "sts:AssumeRole"
    } 
  ]
}
POLICY

  tags = {
    "kubernetes.io/cluster/${var.cluster-name}" = "shared"
  }
}

resource "aws_iam_role_policy_attachment" "hackathon-EKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.hackathon-cluster.name
}

resource "aws_iam_role_policy_attachment" "hackathon-EKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.hackathon-cluster.name
}

resource "aws_security_group" "hackathon-sg" {

  name        = "hackathon_node1"
  description = "Cluster communication with worker nodes"
  vpc_id      = aws_vpc.hackathon_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = map(
    "Name", "hackathon_sg1",
    "kubernetes.io/cluster/${var.cluster-name}", "shared",
  )
}

resource "aws_security_group_rule" "hackathon-sg-rule" {

  type              = "ingress"
  cidr_blocks       = ["3.215.181.135/32"]
  description       = "Allow workstation to communicate with the cluster API Server"
  from_port         = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.hackathon-sg.id
  to_port           = 443

}

resource "aws_eks_cluster" "hackathon-eks-cluster" {

  name     = var.cluster-name
  role_arn = aws_iam_role.hackathon-cluster.arn

  vpc_config {
    security_group_ids = [aws_security_group.hackathon-sg.id]
    subnet_ids         = aws_subnet.hackathon_subnets.*.id
  }

  depends_on = [
    "aws_iam_role.hackathon-cluster",
    "aws_iam_role_policy_attachment.hackathon-EKSClusterPolicy",
    "aws_iam_role_policy_attachment.hackathon-EKSServicePolicy"
  ]
}

resource "aws_iam_role" "hackathon-worker" {

  name               = "hackathon-eks-worker"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement" : [
     {
       "Effect": "Allow",
       "Principal": {
          "Service": "ec2.amazonaws.com"
       },
       "Action": "sts:AssumeRole"
     }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "hackathon-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.hackathon-worker.name
}

resource "aws_iam_role_policy_attachment" "hackathon-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.hackathon-worker.name
}

resource "aws_iam_role_policy_attachment" "hackathon-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.hackathon-worker.name
}

resource "aws_iam_instance_profile" "hackathon_profile" {
  name = "hackathon-eks-pf"
  role = aws_iam_role.hackathon-worker.name
}

resource "aws_security_group" "hackathon-worker" {
  name        = "hackathon-eks-worker-node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = aws_vpc.hackathon_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = map(
    "Name", "hackathon-worker",
    "kubernetes.io/cluster/${var.cluster-name}", "owned",
  )
}

resource "aws_security_group_rule" "hackathon-node-ingres" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.hackathon-worker.id
  source_security_group_id = aws_security_group.hackathon-worker.id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "hackathon-node-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = aws_security_group.hackathon-worker.id
  source_security_group_id = aws_security_group.hackathon-sg.id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "hackathon-cluster-ingress-node-https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.hackathon-sg.id
  source_security_group_id = aws_security_group.hackathon-worker.id
  to_port                  = 443
  type                     = "ingress"
}

data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.hackathon-eks-cluster.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

data "aws_region" "current" {}

locals {
  hackathon-node-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.hackathon-eks-cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.hackathon-eks-cluster.certificate_authority.0.data}' '${var.cluster-name}'
USERDATA
}

resource "aws_launch_configuration" "hackathon-config" {
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.hackathon_profile.name
  image_id                    = data.aws_ami.eks-worker.id
  instance_type               = "t2.micro"
  name_prefix                 = "hackathon-eks-cluster"
  security_groups             = [aws_security_group.hackathon-worker.id]
  user_data_base64            = "${base64encode(local.hackathon-node-userdata)}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "hackathon-asg" {
  desired_capacity     = 3
  launch_configuration = "${aws_launch_configuration.hackathon-config.id}"
  max_size             = 3
  min_size             = 2
  name                 = "hackathon-eks-asg"
  vpc_zone_identifier  = aws_subnet.hackathon_subnets.*.id

  tag {
    key                 = "Name"
    value               = "hackathon-eks-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }
}


locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH

apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.hackathon-worker.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
CONFIGMAPAWSAUTH
}

output "config_map_aws_auth" {
  value = "${local.config_map_aws_auth}"
}


