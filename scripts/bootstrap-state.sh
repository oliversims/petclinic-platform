#!/usr/bin/env bash
set -euo pipefail

#
# bootstrap-state.sh — One-time setup of the Terraform remote state backend
#
# Creates (idempotently):
#   - S3 bucket   petclinic-terraform-state-{account-id}  (versioned, AES256, public access blocked)
#   - DynamoDB    petclinic-terraform-locks               (LockID partition key, String)
# This runs OUTSIDE Terraform — the state backend cannot manage its own state.
#
# Usage:
#   ./scripts/bootstrap-state.sh
#   ./scripts/bootstrap-state.sh --region us-east-1
#

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
PROJECT="petclinic"

usage() {
  echo "Usage: $0 [--region <aws-region>]"
  echo ""
  echo "Options:"
  echo "  --region    AWS region for the state bucket and lock table (default: us-east-1)"
  echo "  -h, --help  Show this help"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      [[ $# -ge 2 ]] || { echo "Error: --region requires a value"; usage; }
      REGION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: unknown argument '$1'"
      usage
      ;;
  esac
done

command -v aws >/dev/null 2>&1 || { echo "Error: aws CLI not found on PATH"; exit 1; }

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${PROJECT}-terraform-state-${ACCOUNT_ID}"
TABLE="${PROJECT}-terraform-locks"

echo "Account:  ${ACCOUNT_ID}"
echo "Region:   ${REGION}"
echo "Bucket:   ${BUCKET}"
echo "Table:    ${TABLE}"
echo ""

#
# S3 bucket
#
if aws s3api head-bucket --bucket "${BUCKET}" >/dev/null 2>&1; then
  echo "[=] S3 bucket ${BUCKET} already exists"
else
  echo "[+] Creating S3 bucket ${BUCKET}"
  if [[ "${REGION}" == "us-east-1" ]]; then
    # us-east-1 rejects a LocationConstraint
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
  aws s3api wait bucket-exists --bucket "${BUCKET}"
fi

echo "[=] Enabling versioning"
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

echo "[=] Enabling default encryption (AES256)"
aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" },
        "BucketKeyEnabled": true
      }
    ]
  }'

echo "[=] Blocking all public access"
aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "[=] Enforcing TLS (deny non-HTTPS requests)"
aws s3api put-bucket-policy \
  --bucket "${BUCKET}" \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Sid\": \"DenyInsecureTransport\",
        \"Effect\": \"Deny\",
        \"Principal\": \"*\",
        \"Action\": \"s3:*\",
        \"Resource\": [
          \"arn:aws:s3:::${BUCKET}\",
          \"arn:aws:s3:::${BUCKET}/*\"
        ],
        \"Condition\": { \"Bool\": { \"aws:SecureTransport\": \"false\" } }
      }
    ]
  }"

echo "[=] Tagging bucket"
aws s3api put-bucket-tagging \
  --bucket "${BUCKET}" \
  --tagging "TagSet=[
    {Key=Project,Value=${PROJECT}},
    {Key=Environment,Value=shared},
    {Key=ManagedBy,Value=bootstrap-script}
  ]"

#
# DynamoDB lock table
#
if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" >/dev/null 2>&1; then
  echo "[=] DynamoDB table ${TABLE} already exists"
else
  echo "[+] Creating DynamoDB table ${TABLE}"
  aws dynamodb create-table \
    --table-name "${TABLE}" \
    --region "${REGION}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --tags Key=Project,Value="${PROJECT}" Key=Environment,Value=shared Key=ManagedBy,Value=bootstrap-script \
    >/dev/null
  echo "[=] Waiting for table to become ACTIVE"
  aws dynamodb wait table-exists --table-name "${TABLE}" --region "${REGION}"
fi

echo ""
echo "Bootstrap complete. State bucket: ${BUCKET}"
echo "This must match the 'bucket' value in terraform/environments/{dev,prod}/backend.tf."
echo ""
echo "Initialize an environment with:"
echo "  cd terraform/environments/dev && terraform init"
