
# AWS-HA-Wordpress-Site

## Overview

The **AWS-HA-Wordpress-Site** project aims to deploy a highly available and scalable WordPress website on AWS using CloudFormation templates. The infrastructure is designed to ensure high availability, scalability, and security by leveraging various AWS services. This project involves the creation of a custom VPC, subnets, security groups, an application load balancer, auto-scaling groups, IAM roles, and a MySQL database instance.

## Technologies Used

- **Amazon Web Services (AWS)**:
  - VPC
  - EC2
  - S3
  - CloudFormation
  - IAM
  - RDS (MySQL)
  - Application Load Balancer (ALB)
  - Auto Scaling
  - AWS Systems Manager (SSM) Parameter Store
- **WordPress**
- **Bash Scripting**

## CloudFormation Templates

### 1. vpc.yaml

This template creates the network stack, including:

- Custom VPC with two public and private subnets
- Internet Gateway
- NAT Gateway
- Public and private route tables
- Public and private Network ACLs (NACLs) with appropriate inbound and outbound rules
- Security groups for:
  - EC2 web server
  - Database server
  - Application Load Balancer (ALB)

### 2. iam.yaml

This template creates the necessary IAM roles and instance profiles used in other templates.

### 3. auto-scaling.yaml

This template creates:

- Launch Template
- Auto Scaling Group

### 4. alb.yaml

This template sets up the Application Load Balancer stack, including:

- Application Load Balancer (ALB)
- Target Group
- ALB Listener

### 5. db.yaml

This template launches an EC2 instance in the private subnet and sets up a MySQL server.

### 6. bastionhost.yaml

This template launches an EC2 instance in the public subnet to act as a bastion host for connecting to the MySQL server.

### 7. app.yaml

This template orchestrates the creation of the entire stack using nested stacks, including:

- IAM roles
- VPC
- Subnets
- Security Groups
- Auto Scaling Group
- Application Load Balancer

## Bash Scripts

Several bash scripts are used to automate specific tasks:

- **mysql_setup.sh**: Sets up the MySQL server with a secure installation, generates passwords, and stores database credentials in the AWS SSM Parameter Store.
- **bastionhost_setup.sh**: Installs MySQL-client on the bastionhost and tests the database connection.
- **wp_setup.sh**: Installs and sets up WordPress on the web server instance, retrieves parameters from the SSM Parameter Store.

## Deployment

### Prerequisites

- AWS CLI installed and configured
- AWS CloudFormation CLI installed
- S3 bucket for storing CloudFormation templates

## Steps to deploy wordpress website on AWS

1. **Create a S3 bucket for deployment**:
```
aws s3api create-bucket --bucket <YOUR_BUCKET_NAME> --region us-east-1
```
2. **Copy the code to s3 bucket**:
```
aws s3 cp ./wordpress-site/ s3://<YOUR_BUCKET_NAME>/wordpress-site/ --recursive
```
3. **Create CloudFormation stack for the application**:
```
aws cloudformation create-stack \
  --stack-name app \
  --template-url https://<YOUR_BUCKET_NAME>.s3.amazonaws.com/wordpress-site/cf-templates/app.yaml \
  --parameters \
      ParameterKey=DeploymentBucket,ParameterValue=<YOUR_BUCKET_NAME> \
      ParameterKey=InstanceTypeParam,ParameterValue=t3.micro \
      ParameterKey=ACGDesiredCapacity,ParameterValue=1 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

4. **Check app stack**:
```
aws cloudformation describe-stacks --stack-name app --query "Stacks[0].StackStatus" --output text --region us-east-1


aws cloudformation describe-stacks --stack-name app --query "Stacks[0].Outputs" --output table --region us-east-1
```