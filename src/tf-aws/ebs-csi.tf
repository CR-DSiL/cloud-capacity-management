#############################################################################################
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
#############################################################################################
locals {
  ebs_csi_driver_namespace = "kube-system"
  ebs_csi_driver_name      = "ebs-csi-driver"

  ebs_csi_driver_controller_iam_resource_name = "eks-${local.ebs_csi_driver_name}-controller-${var.project}-${var.environment}-${var.aws_region}"

  ebs_csi_driver_helm_values = var.enable_aws_ebs_csi_driver ? yamlencode({
    enableVolumeResizing = true
    enableVolumeSnapshot = true
    serviceAccount = {
      controller = {
        create = true
        name   = local.ebs_csi_driver_name
        annotations = {
          "eks.amazonaws.com/role-arn" = module.ebs_csi_driver_controller_iam_role.this_iam_role_arn
        }
      }
    }
  }) : ""
}


# Install helm chart
resource "helm_release" "ebs_csi_driver" {
  count = var.enable_aws_ebs_csi_driver ? 1 : 0

  name       = local.ebs_csi_driver_name
  namespace  = local.ebs_csi_driver_namespace
  chart      = "aws-${local.ebs_csi_driver_name}"
  version    = var.aws_ebs_csi_driver_helm_chart_version
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"

  force_update = true

  values = concat([local.ebs_csi_driver_helm_values], var.ebs_csi_driver_helm_values)
}

# Create IAM role with required policies for EBS CSI driver pod
module "ebs_csi_driver_controller_iam_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "~> 3.0"

  create_role = var.enable_aws_ebs_csi_driver

  role_name = local.ebs_csi_driver_controller_iam_resource_name

  provider_url     = var.oidc_provider_url
  role_policy_arns = [try(aws_iam_policy.ebs_csi_driver_controller[0].arn, "")]

  oidc_fully_qualified_subjects = ["system:serviceaccount:${local.ebs_csi_driver_namespace}:${local.ebs_csi_driver_name}"]

  tags = var.tags
}


resource "aws_iam_policy" "ebs_csi_driver_controller" {
  count = var.enable_aws_ebs_csi_driver ? 1 : 0

  name_prefix = local.ebs_csi_driver_controller_iam_resource_name
  description = "EKS EBS CSI driver controller policy for cluster ${var.cluster_name}"
  policy      = join("", data.aws_iam_policy_document.ebs_csi_driver_controller.*.json)
}

data "aws_iam_policy_document" "ebs_csi_driver_controller" {
  count = var.enable_aws_ebs_csi_driver ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateSnapshot",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:ModifyVolume",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInstances",
      "ec2:DescribeSnapshots",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DescribeVolumesModifications",
    ]
    resources = ["*"]
  }

  statement {
    effect  = "Allow"
    actions = ["ec2:CreateTags"]
    resources = [
      "arn:aws:ec2:*:*:volume/*",
      "arn:aws:ec2:*:*:snapshot/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values = [
        "CreateVolume",
        "CreateSnapshot"
      ]
    }
  }

  statement {
    effect  = "Allow"
    actions = ["ec2:DeleteTags"]
    resources = [
      "arn:aws:ec2:*:*:volume/*",
      "arn:aws:ec2:*:*:snapshot/*"
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateVolume"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/ebs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateVolume"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/CSIVolumeName"
      values   = ["*"]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:DeleteVolume"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/CSIVolumeName"
      values   = ["*"]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:DeleteVolume"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/ebs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:DeleteSnapshot"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/CSIVolumeSnapshotName"
      values   = ["*"]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:DeleteSnapshot"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/ebs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }
}
