/*
output "web_server_ip" {
  description = "Public IP Address of Web Server on EC2"
  value       = aws_instance.web_server.public_ip
  sensitive   = true
}

output "hello-world" {
  description = "Print a Hello World text output"
  value       = "Hello World"
} 

// value is what the actual output will show
output "vpc_id" {
  description = "Output the ID for the primary VPC"
  value       = aws_vpc.vpc.id
}

output "public_url" {
  description = "Public URL for our Web Server"
  value       = "https://${aws_instance.ubuntu_server.private_ip}:8080/index.html"
}
output "vpc_information" {
  description = "VPC Information about Environment"
  value       = "Your ${aws_vpc.vpc.tags.Environment} VPC has an ID of ${aws_vpc.vpc.id}"
} 

output "server_public_ip" {
  description = "This is the public IP of my web server"
  value       = aws_instance.web_server.public_ip
}
output "ec2_instance_arn" {
  value     = aws_instance.web_server.arn
  sensitive = true
} */
