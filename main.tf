# Specify the provider and access details
provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region = "${var.region}"
}

# Create a VPC to launch the instances into
resource "aws_vpc" "default" {
    cidr_block = "${var.vpc_cidr}"
    enable_dns_hostnames = true
    tags {
        Name = "terraform-aws-vpc"
    }
}

# Create an internet gateway to give subnet access to the outside world
resource "aws_internet_gateway" "default" {
    vpc_id = "${aws_vpc.default.id}"
}



############################ public subnet ##########################

#### publuc subnet ######
resource "aws_subnet" "us-east-1a-public" {
    vpc_id = "${aws_vpc.default.id}"
    depends_on = ["aws_internet_gateway.default"]
    cidr_block = "${var.public_subnet_cidr}"
    availability_zone = "us-east-1a"

    tags {
        Name = "${var.user}-${var.app_name}-${var.environment} Public Subnet"
    }
}
#### public subnet custom routing table - communicate with internet via internet gateway ######
resource "aws_route_table" "us-east-1a-public" {
    vpc_id = "${aws_vpc.default.id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.default.id}"
    }

    tags {
        Name = "${var.user}-${var.app_name}-${var.environment} Public Subnet route"
    }
}
### public subnet with routing table association ###
resource "aws_route_table_association" "useast-1a-public" {
    subnet_id = "${aws_subnet.us-east-1a-public.id}"
    route_table_id = "${aws_route_table.us-east-1a-public.id}"
}


###### security goroups #########

### webserver security group #####
resource "aws_security_group" "web-server" {
    name = "vpc_web"
    description = "Allow incoming ssh connections fromm all but only http connectins only from VPC."

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        security_groups = ["${aws_security_group.elb.id}"]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress { # MySQL
        from_port = 3306
        to_port = 3306
        protocol = "tcp"
        cidr_blocks = ["${var.private_subnet_cidr}", "${var.private_subnet_cidr_1}"]
    }

    egress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "WebServerSG"
    }
}

##### loadbalancer security group ######

resource "aws_security_group" "elb" {
    name = "vpc_elb"
    description = "Allow incoming HTTP connections."

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = -1
        to_port = -1
        protocol = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }



    egress { # MySQL
        from_port = 3306
        to_port = 3306
        protocol = "tcp"
        cidr_blocks = ["${var.private_subnet_cidr}", "${var.private_subnet_cidr_1}"]
    }

    egress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "elbSG"
    }
}

### webserver instance ###
resource "aws_instance" "web" {
    ami = "${lookup(var.amis, var.region)}"
    count = "${var.count}"
    availability_zone = "us-east-1a"
    instance_type = "${var.instance_type}"
    key_name = "${var.aws_key_pair_name}"
    vpc_security_group_ids = ["${aws_security_group.web-server.id}"]
    subnet_id = "${aws_subnet.us-east-1a-public.id}"
    associate_public_ip_address = true
    source_dest_check = false


    tags {
        Name = "${var.user}-${var.app_name}-${var.environment} Web Server ${count.index}"
    }
}

#### number of webserver instance ###
resource "aws_eip" "web" {
    count = "${var.count}"
    instance = "${element(aws_instance.web.*.id, count.index)}"
    vpc = true
}
### LB - instance ####
resource "aws_elb" "app" {
  name = "${var.user}-${var.app_name}-${var.environment}"
  subnets = ["${aws_subnet.us-east-1a-public.id}"]
  security_groups = ["${aws_security_group.elb.id}"]
  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }
  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "TCP:80"
    interval = 5
  }
  instances = ["${aws_instance.web.*.id}"]
}



############################ private subnet ########################


####### Create NAT instance ######
#### NAT security group #####
resource "aws_security_group" "nat" {
    name = "vpc_nat"
    description = "net"

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["${var.private_subnet_cidr}"]
    }
    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["${var.private_subnet_cidr}"]
    }
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = -1
        to_port = -1
        protocol = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }
    egress {
        from_port = -1
        to_port = -1
        protocol = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "NATSG"
    }
}

###  NAT instance ##### 
resource "aws_instance" "nat" {
    ami = "ami-6e9e4b06"
    availability_zone = "us-east-1a"
    subnet_id = "${aws_subnet.us-east-1a-public.id}"
    instance_type = "${var.instance_type}"
    key_name = "${var.aws_key_pair_name}"
    vpc_security_group_ids = ["${aws_security_group.nat.id}"]
    subnet_id = "${aws_subnet.us-east-1a-public.id}"
    associate_public_ip_address = true
    source_dest_check = false

    tags {
        Name = "${var.user}-${var.app_name}-${var.environment} VPC NAT"
    }
}

#### NAT instance eip #### 
resource "aws_eip" "nat" {
    instance = "${aws_instance.nat.id}"
    vpc = true
}

##### Create private subnet to launch db instance ####
resource "aws_subnet" "us-east-1a-private" {
    vpc_id = "${aws_vpc.default.id}"

    cidr_block = "${var.private_subnet_cidr}"
    availability_zone = "us-east-1a"

    tags {
        Name = "${var.user}-${var.app_name}-${var.environment} Private Subnet"
    }
}
#### route table to connect to internet via NAT ###
resource "aws_route_table" "us-east-1a-private" {
    vpc_id = "${aws_vpc.default.id}"

    route {
        cidr_block = "0.0.0.0/0"
        instance_id = "${aws_instance.nat.id}"
    }

    tags {
        Name = "${var.user}-${var.app_name}-${var.environment} Private Subnet route"
    }
}
##### routing table nd subnet association ######
resource "aws_route_table_association" "us-east-1a-private" {
    subnet_id = "${aws_subnet.us-east-1a-private.id}"
    route_table_id = "${aws_route_table.us-east-1a-private.id}"
}
resource "aws_subnet" "us-east-1a-private_1" {
    vpc_id = "${aws_vpc.default.id}"

    cidr_block = "${var.private_subnet_cidr_1}"
    availability_zone = "us-east-1b"

    tags {
        Name = "${var.user}-${var.app_name}-${var.environment} Private Subnet_1"
    }
}

resource "aws_route_table" "us-east-1a-private_1" {
    vpc_id = "${aws_vpc.default.id}"

    route {
        cidr_block = "0.0.0.0/0"
        instance_id = "${aws_instance.nat.id}"
    }

    tags {
        Name = "${var.user}-${var.app_name}-${var.environment} Private Subneti_1 route"
    }
}

resource "aws_route_table_association" "us-east-1a-private_1" {
    subnet_id = "${aws_subnet.us-east-1a-private_1.id}"
    route_table_id = "${aws_route_table.us-east-1a-private_1.id}"
}

############################### RDS - DB ######################

##### security group for DB instance ######
resource "aws_security_group" "db" {
    name = "vpc_db"
    description = "Allow incoming database connections."

    ingress { # MySQL
        from_port = 3306
        to_port = 3306
        protocol = "tcp"
        security_groups = ["${aws_security_group.web-server.id}"]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }
    ingress {
        from_port = -1
        to_port = -1
        protocol = "icmp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }

    egress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "DBServerSG"
    }
}

##### mysql DB instance ######
resource "aws_db_instance" "default" {
  identifier = "${var.user}-wordpress-db"
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.6"
  instance_class       = "db.m3.medium"
  storage_type		 = "gp2"
  username             = "${var.db_username}"
  password             = "${var.db_password}"
  db_subnet_group_name = "${aws_db_subnet_group.main_db_subnet_group.name}"
  parameter_group_name = "default.mysql5.6"
  vpc_security_group_ids = ["${aws_security_group.db.id}"]
}

resource "aws_db_subnet_group" "main_db_subnet_group" {
    name = "${var.user}-wordpress-db-subnetgroup"
    description = "RDS subnet group"
    subnet_ids = ["${aws_subnet.us-east-1a-private.id}", "${aws_subnet.us-east-1a-private_1.id}"]
}