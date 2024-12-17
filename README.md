# Deploy Static Website to AWS using Terraform

This guide explains how to deploy a static website to **AWS** using **Terraform**, **S3**, **CloudFront**, and **Origin Access Control (OAC)** for secure and scalable hosting. It also uses **GitHub Actions** for CI/CD automation.

---

## **Table of Contents**
1. [Project Structure](#project-structure)
2. [Prerequisites](#prerequisites)
3. [AWS Resource Setup](#aws-resource-setup)
4. [Terraform Configuration](#terraform-configuration)
5. [GitHub Actions CI/CD Pipeline](#github-actions-cicd-pipeline)
6. [Deploy the Website](#deploy-the-website)
7. [Testing the Setup](#testing-the-setup)
8. [Outputs](#outputs)
9. [Troubleshooting](#troubleshooting)

---

## **1. Project Structure**
Organize your project with the following structure:

```plaintext
project-root/
├── .github/
│   └── workflows/
│       └── deploy.yml        # GitHub Actions pipeline
├── assets/                   # CSS, JS, and images for the website
├── index.html                # Main HTML file
├── error.html                # Error page
├── terraform/
│   ├── main.tf               # Main Terraform file
│   ├── variables.tf          # Input variables
│   ├── backend.tf            # S3 backend for Terraform state
│   ├── outputs.tf            # Outputs
│   └── versions.tf           # Terraform version constraints
└── README.md                 # Project documentation
```

---

## **2. Prerequisites**
Ensure you have the following tools installed:

- **AWS CLI**: Install from [AWS CLI](https://aws.amazon.com/cli/).
- **Terraform**: Install from [Terraform Downloads](https://developer.hashicorp.com/terraform/downloads).
- **GitHub Account**: To store the source code and automate deployments.
- **IAM User** with permissions for S3, CloudFront, and IAM.
- **AWS Access Key & Secret Key**: Configure using `aws configure`.

---

## **3. AWS Resource Setup**
### **S3 Bucket**
- Used to store website files (HTML, CSS, JS, images).
- **Private** bucket with CloudFront access using OAC.

<img width="500" alt="Screenshot 2024-12-17 at 4 59 58 PM" src="https://github.com/user-attachments/assets/80a621a9-29bb-4aa8-801f-2500ad505d58" />


### **CloudFront Distribution**
- Acts as a Content Delivery Network (CDN) for the S3 bucket.
- Configured with **Origin Access Control (OAC)** for secure access.

  <img width="500" alt="Screenshot 2024-12-17 at 4 59 58 PM" src="https://github.com/user-attachments/assets/af0568e5-0a60-4499-ba9d-71757cde95a0" />


### **GitHub Actions**
- Automated pipeline for deploying website files to S3 after a commit.

---

## **4. Terraform Configuration**

### **Create Terraform Files**
#### `main.tf`
```hcl
# S3 bucket for static website (private)
resource "aws_s3_bucket" "website_bucket" {
  bucket = "my-anon-bucket" # Replace with a unique bucket name
}

# S3 bucket website configuration
resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Block Public Access for S3 bucket
resource "aws_s3_bucket_public_access_block" "public_access_block" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "my-s3-oac"
  description                       = "CloudFront OAC to access S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "website_cdn" {
  origin {
    domain_name              = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_id                = "s3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id       = "s3Origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [aws_s3_bucket_public_access_block.public_access_block]
}

# Bucket Policy to Allow CloudFront Access Only
resource "aws_s3_bucket_policy" "cloudfront_access_policy" {
  bucket = aws_s3_bucket.website_bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowCloudFrontAccess",
        Effect    = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.website_bucket.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website_cdn.arn
          }
        }
      }
    ]
  })
}

# Outputs
output "cloudfront_url" {
  description = "CloudFront Distribution URL"
  value       = aws_cloudfront_distribution.website_cdn.domain_name
}

output "s3_bucket_name" {
  description = "S3 Bucket Name"
  value       = aws_s3_bucket.website_bucket.id
}

output "website_endpoint" {
  description = "S3 Static Website Endpoint (for verification only)"
  value       = aws_s3_bucket_website_configuration.website_config.website_endpoint
}
```

#### `versions.tf`
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}
```

#### `backend.tf`
```hcl
terraform {
  backend "s3" {
    bucket = "terraform-backend-state-bucket"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}
```

---

## **5. GitHub Actions CI/CD Pipeline**
Create the file `.github/workflows/deploy.yml`:

```yaml
name: Deploy to AWS S3 and CloudFront

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v3

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Deploy Files to S3
        run: aws s3 sync ./ s3://my-unique-bucket-name --delete

      - name: Invalidate CloudFront Cache
        run: aws cloudfront create-invalidation --distribution-id YOUR_DISTRIBUTION_ID --paths "/*"
```
## **6. Set Up GitHub Secrets**
1. Go to your GitHub repository > Settings > Secrets and Variables > Actions.
2. Add the following secrets:
   - AWS_ACCESS_KEY_ID: Your AWS access key.
   - AWS_SECRET_ACCESS_KEY: Your AWS secret key.
  
     <img width="500" alt="Screenshot 2024-12-17 at 4 59 58 PM" src="https://github.com/user-attachments/assets/e02d9e52-d190-42cd-a188-1142f69edc0a" />


---

## **7. Deploy the Website**

1. **Initialize Terraform**:
   ```bash
   terraform init
   ```
   <img width="500" alt="Screenshot 2024-12-17 at 2 16 43 PM" src="https://github.com/user-attachments/assets/92ccad56-8840-440d-8764-977f40b99cfb" />


2. **Plan and Apply**:
   ```bash
   terraform plan
   terraform apply
   ```
   <img width="500" alt="Screenshot 2024-12-17 at 2 16 07 PM" src="https://github.com/user-attachments/assets/09450f01-42f6-45ca-ada9-2508f92e1440" />

   <img width="500" alt="Screenshot 2024-12-17 at 2 15 38 PM" src="https://github.com/user-attachments/assets/5466372e-ad33-43a0-8a89-51e651920df5" />



3. **Push Code to GitHub**:
   Commit and push your website files to the `main` branch to trigger the GitHub Actions pipeline:
   ```bash
   git add .
   git commit -m "Deploy static website"
   git push origin main
   ```
   <img width="500" alt="Screenshot 2024-12-17 at 5 02 05 PM" src="https://github.com/user-attachments/assets/d7d52853-feac-464f-a665-6c94dd1e5eb0" />


---

## **8. Testing the Setup**
Access your website using the **CloudFront URL** from the Terraform output:

```plaintext
https://<cloudfront_url>
```


https://github.com/user-attachments/assets/4fe5a6d7-a39e-4877-8631-8085fde57635



Verify:
- Static content (HTML, CSS, JS) loads correctly.
- Images and assets are displayed.

---

## **9. Outputs**
Terraform provides the following outputs:

- **CloudFront URL**: Public URL to access your website.
- **S3 Bucket Name**: The name of the S3 bucket hosting your content.

---

## **10. Troubleshooting**
- **Access Denied**: Ensure CloudFront has permissions to access the S3 bucket.
- **404 Errors**: Confirm all assets (CSS, images, JS) are uploaded to S3.
- **Invalidation Issues**: Use `aws cloudfront create-invalidation` to clear the cache.

---

## **Conclusion**
You now have a secure and automated static website deployment pipeline using **Terraform**, **AWS S3**, **CloudFront**, and **GitHub Actions**.
