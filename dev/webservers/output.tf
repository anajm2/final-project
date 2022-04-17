# Step 10 - Add output variables
output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "test_lb" {
  value = aws_lb.test_lb.dns_name
}