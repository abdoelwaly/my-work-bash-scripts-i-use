# bash deploy.sh env

env=$1
case $env in
  qc)
    echo "load QC configurations..."
    ;;
  prod)
    echo "load Production configurations..."
    ;;
  *)
    echo -n "UNKNOWN env."
    exit 1
    ;;
esac

source ./conf-${env}.sh

echo $region

source ./vpc.sh
source ./security.sh
source ./autoscalinggroup.sh
source ./dns.sh



# Prerequistes
# Route 53 Hosted Zone
# IAM resources
# CodeCommit repos