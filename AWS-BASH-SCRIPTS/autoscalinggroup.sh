
asg_name=${env}-srv02-asg

get_ami_id()
{
    ami_id=$(aws ec2 describe-images --region $region --owners 099720109477 \                                  #OUNER ID changable based on vendor for ex ubuntu or redhat 
      --filters 'Name=name,Values=*ubuntu-jammy-22.04-amd64*' 'Name=state,Values=available' \                  #AMI id  name image id could be change based on the image
      --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
    
    echo "The Ubuntu AMI ID in region $region is: $ami_id"
}


prepare_lt_json()
{
    echo "Preparing Launch Template json file ..."
    userdata=$(< build.sh)
    userdata=$(echo "$userdata" | base64)                                                                     # attention for "$userdata" if gone the build file lost his value

    lt_json=$(< ./lt.json)
    
    #${var/original_subsctring/new_substring}
    lt_json=${lt_json/\{env\}/$env}
    lt_json=${lt_json/\{ami_id\}/$ami_id}
    lt_json=${lt_json/\{sg_id\}/$sg_id}
    lt_json=${lt_json/\{userdata\}/$userdata}

    #echo $lt_json
    echo "Launch Template json is ready."
}

create_lt()
{
    prepare_lt_json

    lt_id=$(aws ec2 describe-launch-templates --region $region \
    --filters Name=launch-template-name,Values=${env}-srv2-lt \
    | grep -oP '(?<="LaunchTemplateId": ")[^"]*')

    if [ "$lt_id" == "" ]; then
        echo "Launch Template will be created..."
        lt_id=$(aws ec2 create-launch-template --region $region \
            --launch-template-name ${env}-srv2-lt \
            --launch-template-data "$lt_json" \
            | grep -oP '(?<="LaunchTemplateId": ")[^"]*')
        if [ "$lt_id" == "" ]; then
            echo "Error while creating the launch template."
            exit 1
        fi
    else
        echo "Launch Template already exists."
    fi
    echo $lt_id
}

get_subnets_ids(){

    subnets_ids=""
    subnets_ids_space=""

    for sub in "${public_subnets[@]}"; do
        readarray -d "," -t sub_array <<< "$sub"        
        sub_id=$(aws ec2 describe-subnets --region $region --filters Name=tag:Name,Values=${env}-sub-public-${sub_array[0]} | grep -oP '(?<="SubnetId": ")[^"]*')
        if [ "$sub_id" == "" ]; then
            echo "subnet ${sub} not exists!"
            exit 1
        fi
        subnets_ids+="$sub_id,"
        subnets_ids_space+="$sub_id "
    done

    subnets_ids=${subnets_ids%,}
    subnets_ids_space=${subnets_ids_space% }

    echo $subnets_ids
    echo $subnets_ids_space
}

create_elb(){

    check_elb=$(aws elbv2 describe-load-balancers --region $region --query "LoadBalancers[?LoadBalancerName == '${env}-autoscaling-nlb']")
    
    if [ "$check_elb" == "[]" ]; then
        
        echo "elb will be created"
        
        check_elb=$(aws elbv2 create-load-balancer --name ${env}-autoscaling-nlb --type network --subnets $subnets_ids_space --security-groups $sg_id )
        if [[ $check_elb != *"LoadBalancerArn"* ]]; then
            echo "Error in creating the elb"
            exit 1
        fi
    else
        echo "elb already exist"
    fi
    echo "$check_elb"
    elb_arn=$(echo "$check_elb" | grep -oP '(?<="LoadBalancerArn": ")[^"]*')
    
    elb_dns_name=$(echo "$check_elb" | grep -oP '(?<="DNSName": ")[^"]*')
    echo $elb_dns_name

    elb_hostedzone_id=$(echo "$check_elb" | grep -oP '(?<="CanonicalHostedZoneId": ")[^"]*')
    echo $elb_hostedzone_id
}

create_target_group(){
    check_tg=$(aws elbv2 describe-target-groups --region $region --query "TargetGroups[?TargetGroupName == '${env}-autoscaling-tg']" | grep -oP '(?<="TargetGroupArn": ")[^"]*')

    if [ "$check_tg" == "" ]; then
        
        echo "target group will be created"

        tg_arn=$(aws elbv2 create-target-group --name ${env}-autoscaling-tg \
            --protocol TCP --port 8002 --vpc-id $vpc_id \
            --health-check-interval-seconds 60 \
            --health-check-timeout-seconds 20 \
            --healthy-threshold-count 2 \
            --unhealthy-threshold-count 3 \
            | grep -oP '(?<="TargetGroupArn": ")[^"]*')
        
        if [ "$tg_arn" == "" ]; then
            echo "Error in create the target group"
            exit 1
        fi
    else
        echo "target group already exist"
        tg_arn=$check_tg
    fi

    echo $tg_arn
}

create_listener(){
    ls_arn=$(aws elbv2 create-listener --load-balancer-arn "$elb_arn" --protocol TCP --port 80 --default-actions Type=forward,TargetGroupArn="$tg_arn" | grep -oP '(?<="ListenerArn": ")[^"]*')
    if [ "$ls_arn" == "" ]; then
        echo "Error in create the listener"
        exit 1
    fi
    echo $ls_arn
}

create_auto_scaling_group(){

    check_asg=$(aws autoscaling describe-auto-scaling-groups --region $region --query "AutoScalingGroups[?AutoScalingGroupName == '${asg_name}']" | grep -oP '(?<="AutoScalingGroupARN": ")[^"]*')

    if [ "$check_asg" == "" ]; then
        
        echo "asg will be created!"
        
        aws autoscaling create-auto-scaling-group \
            --auto-scaling-group-name $asg_name \
            --launch-template LaunchTemplateName=${env}-srv2-lt \
            --target-group-arns $tg_arn \
            --min-size 2 \
            --desired-capacity 2 \
            --max-size 7 \
            --vpc-zone-identifier "$subnets_ids"

            # --health-check-type ELB \
            # --health-check-grace-period 120 \

        echo "asg creation done. kinldy check it from the aws console!"

    else
        echo "asg already exist"
        asg_arn=$check_asg
        echo $asg_name
    fi
}

attach_scaling_policy(){
    config=$(cat << EOF
{
    "TargetValue": 50,
    "PredefinedMetricSpecification": {
         "PredefinedMetricType": "ASGAverageCPUUtilization"
    }
}
EOF
)
    config=$( echo $config | tr -d '\n' | tr -d ' ')

    aws autoscaling put-scaling-policy --auto-scaling-group-name $asg_name \
        --policy-name cpu50-target-tracking-scaling-policy \
        --policy-type TargetTrackingScaling \
        --target-tracking-configuration $config
}

get_ami_id

create_lt

get_subnets_ids
create_elb
create_target_group
create_listener

create_auto_scaling_group
attach_scaling_policy