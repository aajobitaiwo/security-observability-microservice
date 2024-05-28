# Data source to retrieve default VPC
data "aws_vpc" "default" {
  default = true
}

# Creating Security Group for the Jenkins CI instance
resource "aws_security_group" "dynamicsg" {
  name        = "DevSecOps-Jenkins-CI-SG"
  description = "SG for Jenkins-CI"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = var.sg_ports
    iterator = port
    content {
      from_port   = port.value
      to_port     = port.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Data source to retrieve most recent Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Data source to retrieve SSH Key Pair
data "aws_key_pair" "ssh-key" {
  key_name           = "ohio-us-east-2-kp"
  include_public_key = true

  #   filter {
  #     name   = "tag:Component"
  #     values = ["web"]
  #   }
}

# Data source to retrieve IAM instance profile
data "aws_iam_role" "iam-role" {
  name = "EC2_w._Admin"
}

# Creating Jenkins Ci instance 
resource "aws_instance" "jenkins-server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.large"
  key_name               = data.aws_key_pair.ssh-key.key_name
  vpc_security_group_ids = [aws_security_group.dynamicsg.id]

  root_block_device {
    volume_size = 50 # 50GB storage
    volume_type = "gp2"
  }

  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo touch /etc/apt/keyrings/adoptium.asc
    sudo wget -O /etc/apt/keyrings/adoptium.asc https://packages.adoptium.net/artifactory/api/gpg/key/public
    echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | sudo tee /etc/apt/sources.list.d/adoptium.list
    sudo apt update -y
    sudo apt install temurin-17-jdk -y
    /usr/bin/java --version
    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
                    /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
                    https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
                                /etc/apt/sources.list.d/jenkins.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install jenkins -y
    sudo systemctl start jenkins
    sudo cat /var/lib/jenkins/secrets/initialAdminPassword

    #Install docker
    sudo apt install docker.io -y
    sudo usermod -aG docker ubuntu
    newgrp docker
    sudo chmod 777 /var/run/docker.sock
    docker version
    sudo usermod -aG docker jenkins

    # Install Trivy
    sudo apt-get install wget apt-transport-https gnupg lsb-release -y
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
    sudo apt-get update
    sudo apt-get install trivy -y

    # Install Terraform
    sudo apt install wget -y
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update && sudo apt install terraform

    # Install kubectl
    sudo apt update
    sudo apt install curl -y
    curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    kubectl version --client

    # Install AWS CLI 
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    sudo apt-get install unzip -y
    unzip awscliv2.zip
    sudo ./aws/install

    # Deploy a SonarQube Container
    docker volume create sonarqube-volume
    docker volume inspect volume sonarqube-volume
    docker run -d --name sonarqube -v sonarqube-volume:/opt/sonarqube/data -p 9000:9000 sonarqube:lts-community
    EOF

  tags = {
    Name = "Jenkins-CI"
  }
}