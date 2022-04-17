

#----------------------------------------------------------
# ACS730 - Week 3 - Terraform Introduction
#
# Build EC2 Instances
#
#----------------------------------------------------------

#  Define the provider
provider "aws" {
  region = "us-east-1"
}

# Data source for AMI id
data "aws_ami" "latest_amazon_linux" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Use remote state to retrieve the data
data "terraform_remote_state" "dev-ntwrk" { // This is to use Outputs from Remote State
  backend = "s3"
  config = {
    bucket = "final-project-dev"             // Bucket where to SAVE Terraform State
    key    = "dev-network/terraform.tfstate" // Object name in the bucket to SAVE Terraform State
    region = "us-east-1"                     // Region where bucket created
  }
}


# Data source for availability zones in us-east-1
data "aws_availability_zones" "available" {
  state = "available"
}

# Define tags locally
locals {
  default_tags = merge(module.globalvars.default_tags, { "env" = var.env })
  prefix       = module.globalvars.prefix
  name_prefix  = "${local.prefix}-${var.env}"
}

# Retrieve global variables from the Terraform module
module "globalvars" {
  source = "../../../modules/globalvars"
}

# Webserver deployment
resource "aws_instance" "my_amazon" {
  ami                         = data.aws_ami.latest_amazon_linux.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.web_key.key_name
  subnet_id                   = data.terraform_remote_state.dev-ntwrk.outputs.private_subnet_ids[0]
  security_groups             = [aws_security_group.web_sg.id]
  associate_public_ip_address = false
  user_data = templatefile("${path.module}/install_httpd.sh",
    {
      env    = upper(var.env),
      prefix = upper(local.prefix)
    }
  )

  root_block_device {
    encrypted = var.env == "prod" ? true : false
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-Amazon-Linux"
    }
  )
}


# Webserver deployment 2
resource "aws_instance" "my_amazon2" {
  ami                         = data.aws_ami.latest_amazon_linux.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.web_key.key_name
  subnet_id                   = data.terraform_remote_state.dev-ntwrk.outputs.private_subnet_ids[1]
  security_groups             = [aws_security_group.web_sg.id]
  associate_public_ip_address = false
  user_data = templatefile("${path.module}/install_httpd.sh",
    {
      env    = upper(var.env),
      prefix = upper(local.prefix)
    }
  )

  root_block_device {
    encrypted = var.env == "prod" ? true : false
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-Amazon-Linux"
    }
  )
}



# Adding SSH key to Amazon EC2
resource "aws_key_pair" "web_key" {
  key_name   = local.name_prefix
  public_key = file("${local.name_prefix}.pub")
}


# Security Group
resource "aws_security_group" "web_sg" {
  name        = "allow_http_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = data.terraform_remote_state.dev-ntwrk.outputs.vpc_id

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-sg"
    }
  )
}



# Bastion deployment
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.latest_amazon_linux.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.web_key.key_name
  subnet_id                   = data.terraform_remote_state.dev-ntwrk.outputs.public_subnet_ids[0]
  security_groups             = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true


  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-bastion"
    }
  )
}

# Security Group for Bastion host
resource "aws_security_group" "bastion_sg" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = data.terraform_remote_state.dev-ntwrk.outputs.vpc_id

  ingress {
    description = "SSH from private IP of CLoud9 machine"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_private_ip}/32", "${var.my_public_ip}/32"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-bastion-sg"
    }
  )
}


# Creating Security Group for ELB
resource "aws_security_group" "demosg1" {
  name        = "Demo Security Group"
  description = "Demo Module"
  vpc_id      = data.terraform_remote_state.dev-ntwrk.outputs.vpc_id
  # Inbound Rules
  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Outbound Rules
  # Internet access to anywhere
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch Congiguration for Auto Scaling 
resource "aws_launch_configuration" "web" {
  name_prefix                 = "web-"
  image_id                    = "ami-04505e74c0741db8d"
  instance_type               = "t3.micro"
  key_name                    = "project-week-dev"
  security_groups             = ["${aws_security_group.demosg1.id}"]
  associate_public_ip_address = true
  user_data = templatefile("${path.module}/install_httpd.sh",
    {
      env    = upper(var.env),
      prefix = upper(local.prefix)
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group 
resource "aws_autoscaling_group" "web" {
  name             = "${aws_launch_configuration.web.name}-asg"
  min_size         = 1
  desired_capacity = 1
  max_size         = 3
  target_group_arns = ["${aws_lb_target_group.tg.arn}"]

  health_check_type = "ELB"
  
  launch_configuration = aws_launch_configuration.web.name
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]
  metrics_granularity = "1Minute"
  vpc_zone_identifier = [
    data.terraform_remote_state.dev-ntwrk.outputs.private_subnet_ids[0],
    data.terraform_remote_state.dev-ntwrk.outputs.private_subnet_ids[1],
  ]
  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }
  tag {
    key                 = "Name"
    value               = "web"
    propagate_at_launch = true
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "web_policy_up" {
  name                   = "web_policy_up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}
resource "aws_cloudwatch_metric_alarm" "web_cpu_alarm_up" {
  alarm_name          = "web_cpu_alarm_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "70"
  dimensions = {
    AutoScalingGroupName = "${aws_autoscaling_group.web.name}"
  }
  alarm_description = "This metric monitor EC2 instance CPU utilization"
  alarm_actions     = ["${aws_autoscaling_policy.web_policy_up.arn}"]
}
resource "aws_autoscaling_policy" "web_policy_down" {
  name                   = "web_policy_down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}
resource "aws_cloudwatch_metric_alarm" "web_cpu_alarm_down" {
  alarm_name          = "web_cpu_alarm_down"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "30"
  dimensions = {
    AutoScalingGroupName = "${aws_autoscaling_group.web.name}"
  }
  alarm_description = "This metric monitor EC2 instance CPU utilization"
  alarm_actions     = ["${aws_autoscaling_policy.web_policy_down.arn}"]
}

# Target Group 
resource "aws_lb_target_group" "tg" {
  name        = "TargetGroup"
  port        = 80
  target_type = "instance"
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.dev-ntwrk.outputs.vpc_id
} 

####################################################
# Target Group Attachment with Instance
####################################################

resource "aws_alb_target_group_attachment" "tgattachment" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.my_amazon.id
  port             = 80
}
resource "aws_alb_target_group_attachment" "tgattachment2" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.my_amazon2.id
  port             = 80
}

####################################################
# Application Load balancer
####################################################

resource "aws_lb" "test_lb" {
  name               = "test-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.demosg1.id}"]
  subnets            =  [data.terraform_remote_state.dev-ntwrk.outputs.public_subnet_ids[0],
                         data.terraform_remote_state.dev-ntwrk.outputs.public_subnet_ids[1]]
}

####################################################
# Listner
####################################################

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.test_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
 type = "forward"

 target_group_arn = aws_lb_target_group.tg.arn

}
}


