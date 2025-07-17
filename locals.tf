locals {
  tag_name = lower(var.name) == "langfuse" ? "Langfuse" : "Langfuse ${var.name}"
}
