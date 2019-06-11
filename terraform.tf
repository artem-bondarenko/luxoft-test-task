#!/usr/bin/env terraform

provider "aws" {
  access_key = var.access_key
  secret_key = var.secret_key
  region     = var.region
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096

  provisioner "local-exec" {
    command = "echo '${self.private_key_pem}' > ansible-rsa-4096.key && chmod u=rw,g=,o= ansible-rsa-4096.key"
  }

}

resource "aws_key_pair" "generated_key" {
  key_name   = "ansible"
  public_key = "${tls_private_key.key.public_key_openssh}"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "allow_ssh" {
  name = "allow_ssh"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
}

resource "aws_instance" "docker-nginx" {
  ami           = "${data.aws_ami.ubuntu.id}"
  instance_type = "t2.micro"
  key_name      = "${aws_key_pair.generated_key.key_name}"
  vpc_security_group_ids = [ "${aws_security_group.allow_ssh.id}" ]
  count = "2"

  provisioner "remote-exec" {
    inline = ["sudo apt-get -qq install python -y"]

    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "ubuntu"
      private_key = "${tls_private_key.key.private_key_pem}"
    }
  }

  provisioner "local-exec" {
    command = "ansible-playbook -u ubuntu -i ${self.public_ip}, --private-key ansible-rsa-4096.key --ssh-common-args='-o StrictHostKeyChecking=no' ansible.yml" 
  }  

  provisioner "local-exec" {
    command = "echo '${self.public_ip}' >> docker-nginx.public-ip.list"
  }

}
