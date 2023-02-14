## Creating EFS share
resource "aws_efs_file_system" "efs" {
  tags = {
    Name = "efs"
  }
  encrypted = true
}

## Adding it to the subnet and security group, so it can be reached by the instances
resource "aws_efs_mount_target" "efs-target" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = var.subnet1-id
  security_groups = [var.security-group-id]
}
## Creating ssh key pair for executing remote commands
resource "aws_key_pair" "ssh-key" {
  key_name   = "ssh-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

## Creating two EC2 instances
resource "aws_instance" "web" {
  count         = 2
  ami           = "ami-0d1ddd83282187d18"
  instance_type = "t2.micro"
  key_name      = "ssh-key"

  tags = {
    Name = "web-instance-${count.index}"
  }
  ## Uploading the app.js
  provisioner "file" {
    source      = "/path/to/app.js"
    destination = "/home/ubuntu/app.js"
  }
  ## Creating the connection
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("/path/to/.ssh/id_rsa")
    host        = self.public_ip
  }
  ## Services update and install. Starting app.js and mounting to the EFS share
  provisioner "file" {
    source      = "setup.sh"
    destination = "/tmp/setup.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup.sh",
      "sudo /tmp/setup.sh ${aws_efs_mount_target.efs-target.ip_address}"
    ]
  }
  ## Waiting until the EFS share is created.
  depends_on = [
    aws_efs_file_system.efs
  ]
}
## Creating target group, which will receive traffic from the Load Balancer and route it to the nodes
resource "aws_lb_target_group" "tg" {
  name        = "TargetGroup"
  port        = 3000
  target_type = "instance"
  protocol    = "HTTP"
  vpc_id      = var.vpc-id
}
## Attaching the nodes
resource "aws_alb_target_group_attachment" "tg-attachment" {
  count            = 2
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web[count.index].id
}
## Creating application load balancer
resource "aws_lb" "lb" {
  name               = "ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security-group-id, ]
  subnets            = [var.subnet1-id, var.subnet2-id, var.subnet3-id]

}
## Here is the port that it will listed to and the request types
resource "aws_lb_listener" "listener-3000" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "3000"
  protocol          = "HTTP"
  ## Here the load balancer will forward the traffic to the target group and then to the nodes.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}
## Allow all outbound traffic
resource "aws_security_group_rule" "outbound" {
  type                     = "egress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = var.security-group-id
  source_security_group_id = var.security-group-id
}
# Allow inbound traffic on port 22 from IP
resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["93.183.137.104/32"]
  security_group_id = var.security-group-id
}
## Allow all inbound traffic on port 3000
/* resource "aws_security_group_rule" "webserver" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id        = var.security-group-id
} */

## Allow internal access to PostgreSQL on port 5432 from the same security group
resource "aws_security_group_rule" "postgres-internal" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.security-group-id
  source_security_group_id = var.security-group-id
}

resource "aws_launch_template" "ubuntu-template" {
  name          = "ubuntu-template"
  image_id      = "ami-0d1ddd83282187d18"
  instance_type = "t2.micro"
  key_name      = "ssh-key"
  network_interfaces {
    associate_public_ip_address = true
    device_index                = 0
    subnet_id                   = var.subnet1-id
    security_groups             = [var.security-group-id]
  }
  user_data = filebase64("${path.module}/setup.sh")
}
## Creating the autoscaling group within eu-central-1 availability zone
resource "aws_autoscaling_group" "asg" {
  # Defining the availability Zone in which AWS EC2 instance will be launched
  vpc_zone_identifier = [var.subnet1-id]
  name                = "autoscalegroup"
  # Maximum number of AWS EC2 instances while scaling
  max_size = 4
  # Minimum and desired number of AWS EC2 instances while scaling
  min_size         = 0
  desired_capacity = 0
  # Time after which AWS EC2 instance comes into service before checking health.
  health_check_grace_period = 30
  health_check_type         = "EC2"
  # force_delete deletes the Auto Scaling Group without waiting for all instances in the pool to terminate
  force_delete = true
  # Defining the termination policy where the oldest instance will be replaced first 
  termination_policies = ["OldestInstance"]
  # Scaling group is dependent on autoscaling launch configuration because of AWS EC2 instance configurations
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ubuntu-template.id
      }
    }
  }
}
## Attach the load balancer to the target group
resource "aws_autoscaling_attachment" "asg-attachment" {
  autoscaling_group_name = aws_autoscaling_group.asg.id
  lb_target_group_arn    = aws_lb_target_group.tg.arn
}

## Autoscaling policy that will scale down
resource "aws_autoscaling_policy" "scale-down" {
  name                   = "scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg.name
}
## Autoscaling policy that will scale up
resource "aws_autoscaling_policy" "scale-up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg.name
}
## CloudWatch alarm that will scale up if the request count is above X
resource "aws_cloudwatch_metric_alarm" "elb-request-count-above" {
  alarm_name          = "ELB Request Count Alarm Above"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "This metric monitors the total number of requests to the ELB"
  alarm_actions       = ["${aws_autoscaling_policy.scale-up.arn}"]
  dimensions = {
    LoadBalancer     = aws_lb.lb.arn_suffix
    TargetGroup      = aws_lb_target_group.tg.arn_suffix
    AvailabilityZone = "eu-central-1a"
  }
}
## CloudWatch alarm that will scale down if the request count is below X for X time
resource "aws_cloudwatch_metric_alarm" "elb-request-count-below" {
  alarm_name          = "ELB Request Count Alarm Below"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "5"
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "This metric monitors the total number of requests to the ELB"
  alarm_actions       = ["${aws_autoscaling_policy.scale-down.arn}"]
  dimensions = {
    LoadBalancer     = aws_lb.lb.arn_suffix
    TargetGroup      = aws_lb_target_group.tg.arn_suffix
    AvailabilityZone = "eu-central-1a"
  }
}
## PostgreSQL 
resource "aws_db_instance" "postgresql" {
  allocated_storage = 10
  engine            = "postgres"
  engine_version    = "13.7"
  instance_class    = "db.t3.micro"
  db_name           = "db_name"
  username          = "user"
  # To provide the password in secure way...
  password            = "pass"
  skip_final_snapshot = true
  publicly_accessible = false
}

## Output public ips of the instances
output "my-public-ips" {
  value = aws_instance.web[*].public_ip
}
## Output the dns name for the Load balancer
output "lb-dns-name" {
  value = aws_lb.lb.dns_name
}
