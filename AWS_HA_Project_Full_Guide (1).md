# AWS High Availability Web Application — Full Project Guide

---

## 1. The Idea (Explained as a Story)

Imagine you own a small shop. At first, you only had **one cashier** (one server). If that cashier got sick, the whole shop closed. Customers got angry and left.

So you decided to fix this:

- You hired **two cashiers** (two application servers) instead of one, so if one is busy or sick, the other keeps working. This is called **High Availability**.
- You put a **manager at the door** (Network Load Balancer) who sends each customer to whichever cashier is free. Customers never need to know which cashier they got — they just walk in the front door and get served.
- Behind the shop, you have a **storage room** (the database servers) where you keep important records. You don't want random people walking into the storage room, so you **lock it** and only allow access through **one special door** (the Bastion Host) that only you have the key to.
- Every new cashier you hire already knows how to do their job automatically — you don't have to train them by hand. This is done using a script called **User Data** that sets up the server automatically when it turns on.
- You also have a **security camera system** (CloudWatch) that alerts you if something looks wrong, like too many customers overwhelming a cashier.

That is exactly what this project builds, but in the cloud using AWS:
- Two **public** application servers behind a **Load Balancer**
- Two **private** database servers, reachable only through a **Bastion Host**
- Automatic setup of the app servers using a startup script
- Monitoring using **CloudWatch**
- Everything organized inside a private network called a **VPC**

---

## 2. Full Step-by-Step Walkthrough (What We Actually Did)

### Part 1 — Building the Network (VPC)
1. Created a VPC with CIDR block `10.0.0.0/16`.
2. Created 4 subnets across 2 Availability Zones:
   - `public1` → `10.0.1.0/24` (AZ eu-north-1a)
   - `private1` → `10.0.2.0/24` (AZ eu-north-1a)
   - `public2` → `10.0.3.0/24` (AZ eu-north-1b)
   - `private2` → `10.0.4.0/24` (AZ eu-north-1b)
3. Created and attached an **Internet Gateway (IGW)** to the VPC — this lets public subnets reach the internet.
4. Allocated an **Elastic IP** and created a **NAT Gateway** in a public subnet — this lets private subnets reach the internet for updates, without being exposed to it.
5. Created two Route Tables:
   - **public-rt** → sends `0.0.0.0/0` traffic to the Internet Gateway. Associated with `public1` and `public2`.
   - **private-rt** → sends `0.0.0.0/0` traffic to the NAT Gateway. Associated with `private1` and `private2`.

### Part 2 — Security Groups (the "who is allowed to talk to who" rules)
Created 4 Security Groups:
- **sg-bastion** → allows SSH (port 22) only from my own IP address.
- **sg-nlb** → allows HTTP (port 80) from anywhere on the internet.
- **sg-app** → allows port 8002 only from `sg-nlb`, and SSH only from `sg-bastion`.
- **sg-db** → allows the database port only from `sg-bastion`. Nothing is open to the public internet.

This creates a chain: **Internet → NLB → App Servers → (SSH only via) Bastion → Database Servers**

### Part 3 — Bastion Host
- Launched 1 EC2 instance (Ubuntu 24.04) in a public subnet.
- Gave it a public IP address.
- Attached `sg-bastion`.
- This is the only "door" used to reach the private database servers.

### Part 4 & 5 — Launch Template + Application Servers
- Created a **Launch Template** (`app-launch-template`) containing:
  - Ubuntu 24.04 AMI
  - Instance type `t3.micro`
  - Security group `sg-app`
  - A **User Data script** (a startup script) that:
    - Installs Python
    - Creates a small Python web server that listens on port 8002
    - Returns a page showing the hostname, time, request number, and a unique request ID
    - Sets it up as a systemd service so it restarts automatically and runs on every boot
- Launched 2 EC2 instances from this template — one in `public1`, one in `public2`.

### Part 6 — Network Load Balancer (NLB)
- Created a **Target Group** (`tg-app`) with protocol TCP on port **8002**, and registered both app servers as targets.
- Created a **Network Load Balancer** (`app-nlb`) in both public subnets, with a listener on port **80** forwarding to the target group.
- Result: opening the NLB's DNS name in a browser (no port number needed) shows the application, and refreshing the page alternates between the two app servers.

### Part 7 — Private Database Servers
- Launched 2 EC2 instances (`db-server-1`, `db-server-2`) in the **private** subnets, with **no public IP** and security group `sg-db`.
- Connected to them only through the Bastion Host (SSH "jump" from Bastion → private server).
- Installed PostgreSQL on both.
- Created a test database, a test table, inserted a test record, and verified it with a `SELECT` query.

### Part 8 — CloudWatch Monitoring
- Created a CloudWatch Alarm (`app-cpu-high-alarm`) that triggers when CPU usage on an app server goes above 70% for 5 minutes.

### Extra — CloudFormation (Infrastructure as Code)
- Wrote a small CloudFormation template (YAML) describing a CloudWatch Alarm resource.
- Deployed it using the AWS CLI command `aws cloudformation create-stack`.
- Verified the stack reached status `CREATE_COMPLETE`.
- This shows the ability to manage AWS resources with code instead of clicking manually in the Console.

---

## 3. Errors We Faced and How We Fixed Them

This section is very useful to mention in the discussion — it shows you understand **why** things work, not just clicking buttons.

| # | Error | Cause | How We Fixed It |
|---|-------|-------|------------------|
| 1 | VPC CIDR was `/24` instead of `/16` | Too few IP addresses to comfortably split into 4 subnets | Deleted the small VPC (before creating any resources in it) and recreated it with `10.0.0.0/16` |
| 2 | "Microsoft SQL Server is not supported for instance type t3.micro" when launching an instance | Picked the wrong AMI — an "Ubuntu with SQL Server" Marketplace image instead of plain Ubuntu | Went to **Quick Start** tab and selected the plain **Ubuntu Server 24.04 LTS** AMI |
| 3 | `t2.micro` instance type not available | Not available in this region/account | Used `t3.micro` instead (same purpose, free-tier eligible) |
| 4 | Route table could not be edited (subnet associations greyed out) | The route table was locked because it was linked as an "Edge association" to the NAT Gateway | Created a brand-new route table (`public-rt-2`) instead of forcing changes on the locked one |
| 5 | "CIDR block, a security group ID or a prefix list has to be specified" when adding SSH rule | Source field for SSH rule was left empty | Selected **"My IP"** from the Source dropdown instead of typing manually |
| 6 | SSH `Permission denied (publickey)` | Was using a `.pem` path that didn't actually exist on the computer (wrong file path typed) | Located the real file with `dir *.pem` and used the correct file path |
| 7 | Curl to `localhost:8002` failed with "Couldn't connect to server" on app servers | The Launch Template's **User Data script never actually ran** — it was empty (`curl http://169.254.169.254/latest/user-data` returned nothing) | Since re-running User Data automatically wasn't simple, we manually ran the same setup script by hand (SSH into each app server) to install Python and start the service |
| 8 | SSH from Bastion to a private database server timed out | The database server's security group (`sg-db`) did not allow inbound SSH from the Bastion's security group | Added an inbound rule in `sg-db`: allow SSH (port 22) with source = `sg-bastion` |
| 9 | `apt-get install postgresql` failed with "Network is unreachable" on a private database server | The private subnet's route table was not correctly routing internet traffic through the NAT Gateway | Verified/fixed the private route table's `0.0.0.0/0 → NAT Gateway` route and its subnet association, then the install worked |

**Key lesson to say in the discussion:** *"Most errors were network and permission related — wrong AMI, wrong file paths, or a missing rule in a Security Group or Route Table. Cloud troubleshooting is mostly about checking the path traffic takes step by step."*

---

## 4. How to Demo / Present the Project

Present it in this order — it tells a clear story from "outside" to "inside":

1. **Show the architecture diagram** (drawn or from the AWS Console) — explain the flow: Internet → NLB → App Servers → Bastion → Database Servers.
2. **Open the NLB's DNS name in a browser** — refresh a few times and point out the hostname changing between the two app servers. This proves load balancing works.
3. **SSH into the Bastion Host** from your terminal — show that this is the "front door."
4. **From the Bastion, SSH into a private database server** — show that it has no public IP and can only be reached this way.
5. **Run a database query** on the private server (`SELECT * FROM demo_table;`) — show it works even though the server is fully private.
6. **Show the Launch Template and its User Data script** — explain the automatic setup idea (even though you manually re-ran it due to the bug, explain what it was supposed to do).
7. **Show the CloudWatch Alarm** — explain what it monitors and why it matters.
8. **Show the CloudFormation stack** (`CREATE_COMPLETE` status) — explain that this is "Infrastructure as Code."

---

## 5. Expected Discussion Questions & Answers

### Q1: What is the idea of the project?
"I built a secure, highly available cloud environment. It has two public application servers behind a Load Balancer so the app never goes fully down, and two private database servers that are completely isolated from the internet, reachable only through a Bastion Host. The application servers set themselves up automatically using a startup script, and CloudWatch monitors the system's health."

### Q2: What AWS services did you use?
"VPC, Subnets, Internet Gateway, NAT Gateway, EC2, Security Groups, Network ACLs, Network Load Balancer, Launch Templates, CloudWatch, and CloudFormation."

### Q3: What APIs did you use?
"Most of the project was built through the AWS Management Console, which itself calls AWS APIs behind the scenes. In addition, I directly used the AWS CLI to call APIs myself — for example `describe-instances`, `describe-load-balancers`, and `describe-alarms` to query resources, and `cloudformation create-stack` to deploy a CloudFormation template that creates a CloudWatch Alarm through Infrastructure as Code."

---

## 6. Required Screenshots (In Order)

Take these screenshots as you go, not at the very end, so nothing is missed:

1. **Full architecture overview** (VPC Resource Map page, or a diagram you draw)
2. **VPC page** showing the CIDR block `10.0.0.0/16`
3. **Subnets page** showing all 4 subnets and their Availability Zones
4. **Route Tables page** showing public-rt-2 and private-rt with their routes (IGW and NAT Gateway)
5. **Security Groups page** showing all 4 groups (sg-bastion, sg-nlb, sg-app, sg-db) and their rules
6. **Network ACL rules**
7. **Bastion Host** instance page showing it's Running with a public IP
8. **Launch Template** page showing its configuration and User Data section
9. **Both application servers** Running in the EC2 console
10. **Network Load Balancer** page showing its listener configuration (port 80)
11. **Target Group** page showing both targets as Healthy
12. **Application opened in browser** through the NLB's DNS name (no port number)
13. **Terminal screenshot** proving SSH connection from Bastion into a private database server
14. **Database screenshot**: PostgreSQL version, and the result of the `SELECT` query showing your test record
15. **Proof the app service is running** (`systemctl status bashar-srv.service` output, or the curl response)
16. **CloudWatch Alarm** page showing its configuration
17. *(Extra)* **CloudFormation stack** page showing status `CREATE_COMPLETE`

---

## 7. Quick Reference — Names Used in This Project

| Item | Name / Value |
|---|---|
| VPC CIDR | `10.0.0.0/16` |
| Public Subnets | `my-we-project-public1` (10.0.1.0/24), `my-we-project-public2` (10.0.3.0/24) |
| Private Subnets | `my-we-project-private1` (10.0.2.0/24), `my-we-project-private2` (10.0.4.0/24) |
| Route Tables | `public-rt-2`, `private-rt` |
| Security Groups | `sg-bastion`, `sg-nlb`, `sg-app`, `sg-db` |
| Bastion Host | `bastion-host` |
| Launch Template | `app-launch-template` |
| Application Servers | `app-server-1`, `app-server-2` |
| Load Balancer | `app-nlb` |
| Target Group | `tg-app` (port 8002) |
| Database Servers | `db-server-1`, `db-server-2` |
| CloudWatch Alarm | `app-cpu-high-alarm` |
| CloudFormation Stack | `ha-webapp-cf-stack` (creates `cf-app-cpu-alarm`) |

