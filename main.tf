# new demo vpc with 3 private subnets, 3 public subnets, a network interface
# to connect the private subnets to the public subnets, and a 

# Configure the AWS Provider
provider "aws" {
  # can add credentials here if we want - access_key and secret_key - not recommended for prod
  # can add a shared_credentials_file with the path for the credentials file
  region = "us-east-1"
  # when changing the region, make sure the number of availability zones is compatible for our architecture
}
provider "aws" {
  region = "us-east-2"
  alias  = "us-east-2"
  // alias required when invoking the same provider twice
}

# local variables, can be anything that you might use repetitively, no need to declare type
locals {
  team         = "api_mgmt_dev"
  application  = "corp_api"
  server_name  = "ec2-${var.environment}-api-${var.variables_sub_az}"
  service_name = "Automation"
  app_team     = "Cloud Team"
  createdby    = "terraform"
}

locals {
  # Common tags to be assigned to all resources
  common_tags = {
    Name      = local.server_name
    Owner     = local.team
    App       = local.application
    Service   = local.service_name
    AppTeam   = local.app_team
    CreatedBy = local.createdby
  }
}


# can use data blocks to query resources that are already created, ping APIs, or just get data from another source
# documentation is online for using all different types of providers for gathering information
# Retrieve the list of AZs in the current AWS region
# current region was defined in the provider block
data "aws_availability_zones" "available" {}
data "aws_region" "current" {}

# Terraform Data Block - Lookup Ubuntu 16.04
data "aws_ami" "ubuntu_16_04" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  owners = ["099720109477"]
}

#Define the VPC
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = var.vpc_name
    Environment = "demo_environment"
    Terraform   = "true"
    Region      = data.aws_region.current.name # data is the top level, aws_region is the type, current is the local name, name is the attribute

  }
}

# Deploy the private subnets
resource "aws_subnet" "private_subnets" {
  for_each   = var.private_subnets
  vpc_id     = aws_vpc.vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value)
  availability_zone = tolist(data.aws_availability_zones.available.names)[
  each.value]
  tags = {
    Name      = each.key
    Terraform = "true"
  }
}
# Deploy the public subnets
resource "aws_subnet" "public_subnets" {
  for_each   = var.public_subnets
  vpc_id     = aws_vpc.vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value + 100)
  availability_zone = tolist(data.aws_availability_zones.available.
  names)[each.value]
  map_public_ip_on_launch = true
  tags = {
    Name      = each.key
    Terraform = "true"
  }
}
#Create route tables for public and private subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
    #nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "demo_public_rtb"
    Terraform = "true"
  }
}
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    # gateway_id = aws_internet_gateway.internet_gateway.id
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "demo_private_rtb"
    Terraform = "true"
  }
}
#Create route table associations
resource "aws_route_table_association" "public" {
  depends_on     = [aws_subnet.public_subnets]
  route_table_id = aws_route_table.public_route_table.id
  for_each       = aws_subnet.public_subnets
  subnet_id      = each.value.id
}
resource "aws_route_table_association" "private" {
  depends_on     = [aws_subnet.private_subnets]
  route_table_id = aws_route_table.private_route_table.id
  for_each       = aws_subnet.private_subnets
  subnet_id      = each.value.id
}
#Create Internet Gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "demo_igw"
  }
}
#Create EIP for NAT Gateway
resource "aws_eip" "nat_gateway_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.internet_gateway]
  tags = {
    Name = "demo_igw_eip"
  }
}
#Create NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  depends_on    = [aws_subnet.public_subnets]
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = aws_subnet.public_subnets["public_subnet_1"].id
  tags = {
    Name = "demo_nat_gateway"
  }
}

/*
# Terraform Resource Block - To Build EC2 instance in Public Subnet
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.ubuntu_16_04.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnets["public_subnet_1"].id
  tags = {
    Name  = local.server_name
    Owner = local.team
    App   = local.application
  }
}
*/


resource "aws_instance" "ubuntu_server" {
  ami                         = data.aws_ami.ubuntu_16_04.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnets["public_subnet_1"].id
  security_groups             = [aws_security_group.vpc-ping.id, aws_security_group.ingress-ssh.id, aws_security_group.vpc-web.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.generated.key_name

  // connections cannot stand on their own, they must be embedded in another resource block
  connection {
    user        = "ubuntu"
    private_key = tls_private_key.generated.private_key_pem
    host        = self.public_ip
  }

  # runs a local executable with the command given
  // this command changes the provisions of the private key 
  // When using Windows, chmod requires the installation of Git for Windows as well as the addition of a system environment variable
  // add this to the system environment variables: C:\Program Files\Git\usr\bin
  provisioner "local-exec" {
    command = "chmod 600 ${local_file.private_key_pem.filename}"
  }

  // runs commands/executables on a remote resource
  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf /tmp",
      "sudo git clone https://github.com/hashicorp/demo-terraform-101 /tmp", // clones the repo into a temp directory
      "sudo sh /tmp/assets/setup-web.sh",
    ]
  }

  tags = {
    Name = "Ubuntu EC2 Server"
  }
  lifecycle {
    ignore_changes = [security_groups]
  }
}

resource "aws_subnet" "variables-subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.variables_sub_cidr
  availability_zone       = var.variables_sub_az
  map_public_ip_on_launch = var.variables_sub_auto_ip

  tags = {
    Name      = "sub-variables-${var.variables_sub_az}"
    Terraform = "true"
  }
}

resource "tls_private_key" "generated" {
  algorithm = "RSA"
}

// saves the key to a local file, presumably from the 'local' provider
resource "local_file" "private_key_pem" {
  content  = tls_private_key.generated.private_key_pem // previously created key, reference is above
  filename = "MyAWSKey.pem"
}

resource "aws_key_pair" "generated" {
  key_name   = "MyAWSKey"
  public_key = tls_private_key.generated.public_key_openssh
  lifecycle {
    ignore_changes = [key_name]
  }
}

resource "aws_security_group" "ingress-ssh" {
  name   = "allow-all-ssh"
  vpc_id = aws_vpc.vpc.id
  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
    // all ports in the range from 22 to 22 
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
  }
  // Terraform removes the default rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create Security Group - Web Traffic
resource "aws_security_group" "vpc-web" {
  name        = "vpc-web-${terraform.workspace}"
  vpc_id      = aws_vpc.vpc.id
  description = "Web Traffic"
  ingress {
    description = "Allow Port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow Port 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow all ip and ports outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "vpc-ping" {
  name        = "vpc-ping"
  vpc_id      = aws_vpc.vpc.id
  description = "ICMP for Ping Access"
  ingress {
    description = "Allow ICMP Traffic"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow all ip and ports outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Terraform Resource Block - To Build Web Server in Public Subnet
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.ubuntu_16_04.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnets["public_subnet_1"].id
  security_groups = [aws_security_group.vpc-ping.id,
  aws_security_group.ingress-ssh.id, aws_security_group.vpc-web.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.generated.key_name
  connection {
    user        = "ubuntu"
    private_key = tls_private_key.generated.private_key_pem
    host        = self.public_ip
  }
  # Leave the first part of the block unchanged and create our `local-exec` provisioner
  provisioner "local-exec" {
    command = "chmod 600 ${local_file.private_key_pem.filename}"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf /tmp",
      "sudo git clone https://github.com/hashicorp/demo-terraform-101 /tmp",
      "sudo sh /tmp/assets/setup-web.sh",
    ]
  }
  tags = local.common_tags
  /*
  tags = {
    // quotes only required when you're using a space in the name
    Name        = "Web EC2 Server"
    Service     = local.service_name
    "AppTeam"   = local.app_team
    "CreatedBy" = local.createdby
  }*/
  lifecycle {
    ignore_changes = [security_groups]
  }
}

/* 
// imported resource
resource "aws_instance" "aws_linux" {
  instance_type = "t2.micro"
  ami           = "ami-02396cdd13e9a1257"
  tags = {
    Name = "kensington"
    Owner = "James"
  }

}  */

// name of the module block doesn't need to be the same as the folder/module we're referencing
// passing along arguements which are then received by the module

module "server_subnet_3" {
  source    = "./modules/server" // unix notation
  ami       = data.aws_ami.ubuntu_16_04.id
  subnet_id = aws_subnet.public_subnets["public_subnet_3"].id

  // list of security groups
  security_groups = [
    aws_security_group.vpc-ping.id,
    aws_security_group.ingress-ssh.id,
    aws_security_group.vpc-web.id
  ]
}


// outputs must be invoked in the main.tf file that you're using the module in
// the output becomes specific to the infrastructure/service/hardware that you pass it 
// since the object we created comes from a module, we can use the output functions in that module
// the output name must match the output in the module (I think?)
output "public_ip" {
  value = module.server_subnet_3.public_ip
}
output "public_dns" {
  value = module.server_subnet_3.public_dns
}
output "size" {
  value = module.server_subnet_3.size
}


module "server_subnet_1" {
  source      = "./modules/web_server"
  ami         = data.aws_ami.ubuntu_16_04.id
  key_name    = aws_key_pair.generated.key_name
  user        = "ubuntu"
  private_key = tls_private_key.generated.private_key_pem
  subnet_id   = aws_subnet.public_subnets["public_subnet_1"].id
  security_groups = [aws_security_group.vpc-ping.id,
    aws_security_group.ingress-ssh.id,
  aws_security_group.vpc-web.id]
}

/*
module "autoscaling" {
  source  = "github.com/terraform-aws-modules/terraform-aws-autoscaling?ref=v4.9.0"
  //version = "3.0"  // version not required when pulling from github
  name    = "myasg"

  vpc_zone_identifier = [aws_subnet.private_subnets["private_subnet_1"].id,
    aws_subnet.private_subnets["private_subnet_2"].id,
  aws_subnet.private_subnets["private_subnet_3"].id]
  min_size         = 0
  max_size         = 1
  desired_capacity = 1
  //health_check_type = "EC2"
  //use_mixed_instances_policy = false

  # Launch template
  //use_lt        = true
  //create_lt     = true
  image_id      = data.aws_ami.ubuntu_16_04.id
  instance_type = "t3.micro"
  tags_as_map = {
    Name = "Web EC2 Server 2"
  }

}*/

/*

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "4.9.0"
  # Autoscaling group
  name                = "myasg"
  vpc_zone_identifier = [aws_subnet.private_subnets["private_subnet_1"].id, aws_subnet.private_subnets["private_subnet_2"].id, aws_subnet.private_subnets["private_subnet_3"].id]
  min_size            = 0
  max_size            = 1
  desired_capacity    = 1
  # Launch template
  use_lt        = true
  create_lt     = true
  image_id      = data.aws_ami.ubuntu_16_04.id
  instance_type = "t3.micro"
  tags_as_map = {
    Name = "Web EC2 Server 2"
  }
}

// passing in autoscaling as the resource we want the output for
// then calling for what we want
// can find the outputs available to us in the source code online'
// we don't care how the output is calculated, just how to invoke/call it 
// we can't make the same call that's in the output file, we have to call it using a resource
output "asg_group_size" {
  value = module.autoscaling.autoscaling_group_max_size

} */
/*
module "s3-bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "2.11.1"

  //terraform-20230427234806986800000001.s3.amazonaws.com
}
output "s3_bucket_bucket_domain_name" {
  value = module.s3-bucket.s3_bucket_bucket_domain_name
}*/

resource "aws_instance" "web_server_2" {
  ami           = data.aws_ami.ubuntu_16_04.id
  instance_type = "t2.small"
  subnet_id     = aws_subnet.public_subnets["public_subnet_2"].id
  tags = {
    Name = "Web EC2 Server 2"
  }
}



/*
module "vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  name               = "my-vpc-terraform"
  cidr               = "10.0.0.0/16"
  azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_nat_gateway = true
  enable_vpn_gateway = true
  tags = {
    Name        = "VPC from Module"
    Terraform   = "true"
    Environment = "dev"
  }
}
*/

