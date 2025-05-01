# EFS File System
resource "aws_efs_file_system" "langfuse" {
  creation_token = "${var.name}-efs"
  encrypted      = true
  throughput_mode = "elastic"

  tags = {
    Name = local.tag_name
  }
}
