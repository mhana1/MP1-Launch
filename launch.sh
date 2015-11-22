#!/bin/bash

./cleanup.sh

declare -a instArray

mapfile -t instArray < <(aws ec2 run-instances --image-id $1 --count $2 --instance-type $3 --security-group-ids $4 --subnet-id $5 --key-name $6  --associate-public-ip-address --iam-instance-profile Name=$7 --user-data file://../MP1-ENV/install-env.sh --output table | grep InstanceId | sed "s/|//g" | tr -d ' ' | sed "s/InstanceId//g")

echo ${instArray[@]}

aws ec2 wait instance-running --instance-ids ${instArray[@]}
echo "instances are running"

#create load balancer
aws elb create-load-balancer --load-balancer-name MP1-lb --listeners Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80 --security-groups $4 --subnets $5 --output=text

echo -e "\nFinished launching ELB and sleeping 25 second"
for i in {0..25}; do echo -ne '.'; sleep 1;done
echo "\n"

#register load balancer
aws elb register-instances-with-load-balancer --load-balancer-name MP1-lb --instances ${instArray[@]}

aws elb configure-health-check --load-balancer-name MP1-lb --health-check Target=HTTP:80/index.html,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3

aws elb create-lb-cookie-stickiness-policy --load-balancer-name MP1-lb --policy-name cookie --cookie-expiration-period 60

aws elb set-load-balancer-policies-of-listener --load-balancer-name MP1-lb --load-balancer-port 80 --policy-names cookie

echo -e "\nWaiting an additional 3 minutes (180 seconds) . before opening the ELB in a webbrowser"
for i in {0..180}; do echo -ne '.'; sleep 1;done


aws autoscaling create-launch-configuration --launch-configuration-name itmo544-launch-config --image-id $1 --key-name $6  --security-groups $4  --instance-type $3 --user-data file://../MP1-ENV/install-env.sh --iam-instance-profile $7

aws autoscaling create-auto-scaling-group --auto-scaling-group-name itmo-544-autoscaling-group --launch-configuration-name itmo544-launch-config --load-balancer-names MP1-lb  --health-check-type ELB --min-size 3 --max-size 6 --desired-capacity 3 --default-cooldown 600 --health-check-grace-period 120 --vpc-zone-identifier $5


#cloud watch

PolicyARN1=(`aws autoscaling put-scaling-policy --policy-name policy-1 --auto-scaling-group-name itmo-544-autoscaling-group --scaling-adjustment 1 --adjustment-type ChangeInCapacity`);

PolicyARN2=(`aws autoscaling put-scaling-policy --policy-name policy-2 --auto-scaling-group-name itmo-544-autoscaling-group --scaling-adjustment 1 --adjustment-type ChangeInCapacity`);

aws cloudwatch put-metric-alarm --alarm-name AddCapacity --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 120 --threshold 30 --comparison-operator GreaterThanOrEqualToThreshold --dimensions "Name=AutoScalingGroupName,Value=itmo-544-autoscaling-group" --evaluation-periods 2 --alarm-actions $PolicyARN1

aws cloudwatch put-metric-alarm --alarm-name RemoveCapacity --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 120 --threshold 10 --comparison-operator LessThanOrEqualToThreshold --dimensions "Name=AutoScalingGroupName,Value=itmo-544-autoscaling-group" --evaluation-periods 2 --alarm-actions $PolicyARN2

echo "Creating Database..."
aws rds create-db-instance --db-instance-identifier mh-db --db-name mhana1DB --db-instance-class db.t1.micro --engine MySQL --allocated-storage 5 --master-username controller --master-user-password letmein888
	 
