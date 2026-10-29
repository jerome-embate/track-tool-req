output "app_url" {
  value       = "http://${aws_lb.app.dns_name}"
  description = "Public URL of the app through the ALB."
}

output "cluster_name" {
  value       = aws_ecs_cluster.this.name
  description = "ECS cluster name."
}

output "service_name" {
  value       = aws_ecs_service.app.name
  description = "ECS service name."
}

output "log_group" {
  value       = aws_cloudwatch_log_group.app.name
  description = "CloudWatch log group for the app container."
}
