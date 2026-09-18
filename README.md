# aws-ha-webapp-project
# AWS High Availability Web Application

A secure, highly available AWS architecture featuring:
- VPC with public/private subnets across 2 Availability Zones
- Network Load Balancer distributing traffic across 2 application servers
- Bastion Host for secure access to private database servers
- Automated deployment using EC2 User Data
- CloudWatch monitoring
- Infrastructure as Code using CloudFormation

## Architecture
Internet → NLB → App Servers (public subnets) → Bastion Host → Database Servers (private subnets)

## Files
- `user-data.sh` — startup script for application servers
- `cloudformation-stack.yaml` — CloudWatch Alarm deployed via CloudFormation
- `project-guide.md` — full documentation and walkthrough
