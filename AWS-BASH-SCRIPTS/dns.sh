#!/bin/bash

dns_name="abdo_elwaly.com"

get_hosted_zone_id()
{
    hosted_zone_id=$(aws route53 list-hosted-zones-by-name --query "HostedZones[?Name == '$dns_name.']"  | grep -oP '(?<="Id": ")[^"]*' | uniq)

    if [ "$hosted_zone_id" == "" ]; then
        echo "Hosted Zone Not Exists ..."
        exit 1
    else
        hosted_zone_id=$(echo "$hosted_zone_id" | sed 's/\/hostedzone\///')
        echo "Hosted Zone Id: $hosted_zone_id"
    fi
}

create_dns_record()
{
    full_sub_domain="$1.$dns_name"
    if [ "$env" != "prod" ]; then
        full_sub_domain="$env$full_sub_domain"
    fi
    change=$(cat << EOF
{
  "Changes": 
  [
    {
      "Action": "CREATE",
      "ResourceRecordSet": 
      {
        "Name": "${full_sub_domain}",
        "Type": "A",
        "AliasTarget":{
          "HostedZoneId": "${elb_hostedzone_id}",
          "DNSName": "${elb_dns_name}",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF
)

    change=$( echo $change | tr -d '\n' | tr -d ' ')
    
    check_record=$(aws route53 list-resource-record-sets --hosted-zone-id $hosted_zone_id --query "ResourceRecordSets[?Name == '$full_sub_domain.']" | grep -oP '(?<="Name": ")[^"]*')
    if [ "$check_record" == "" ]; then
        echo "DNS Record will be created ..."
        record_change=$(aws route53 change-resource-record-sets --hosted-zone-id $hosted_zone_id --change-batch $change)
        echo $record_change
    else
        echo "DNS Record already exist."
    fi
}

get_hosted_zone_id
create_dns_record srv2