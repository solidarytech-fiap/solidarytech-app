# EKS no AWS Academy: nao e permitido criar IAM Roles, entao cluster e nodes
# usam a LabRole existente. Consequencia: sem IRSA/Pod Identity. Os pods
# acessam SQS/DynamoDB/SSM/S3 pela credencial do node (instance profile via
# IMDSv2). Por isso o launch template fixa hop limit = 2 (pod -> node -> IMDS).

data "aws_iam_role" "lab_role" {
  name = var.iam_role_name
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = data.aws_iam_role.lab_role.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Logs do control plane no CloudWatch (custo por GB ingerido).
  enabled_cluster_log_types = var.cluster_log_types

  tags = { Name = var.cluster_name }
}

# Launch template: tags propagadas para EC2/EBS (default_tags do provider
# NAO chega nas instancias criadas pelo Auto Scaling do node group) e IMDSv2.
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.cluster_name}-nodes-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 obrigatorio
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.propagate_tags, { Name = "${var.cluster_name}-node", Service = "platform-eks" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.propagate_tags, { Name = "${var.cluster_name}-node-volume", Service = "platform-eks" })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = merge(var.propagate_tags, { Service = "platform-eks" })
  }

  tags = { Service = "platform-eks" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = data.aws_iam_role.lab_role.arn
  subnet_ids      = var.subnet_ids

  capacity_type  = var.capacity_type
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = var.instance_types

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "general"
    project  = "solidarytech"
  }

  tags = { Service = "platform-eks" }

  lifecycle {
    # Permite que um autoscaler ajuste desired_size sem drift.
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# Add-ons gerenciados pela AWS (atualizacoes de seguranca sem esforco).
resource "aws_eks_addon" "this" {
  for_each = toset(["vpc-cni", "kube-proxy", "coredns"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = { Service = "platform-eks" }

  depends_on = [aws_eks_node_group.this]
}
