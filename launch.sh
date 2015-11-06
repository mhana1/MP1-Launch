#!/bin/bash

./cleanup.sh

declare -a instArray

mapfile -t instArray < <(aws ec2 run-instances --image-id $1 --count $2 --instance-type $3 --security-group-ids $4 --subnet-id $5 --key-name $6  --associate-public-ip-address --iam-instance-profile Name=$7 --user-data file://../MP1-ENV/install-env.sh --output table | grep InstanceId | sed "s/|//g" | tr -d ' ' | sed "s/InstanceId//g")

echo ${instArray[@]}

aws ec2 wait instance-running --instance-ids ${instArray[@]}
echo "instances are running"

#create load balancer
ELBURL=('aws elb create-load-balancer --load-balancer-name MP1-lb --listeners Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80 --security-groups $4 --subnets $5 --output=text');
echo $ELBURL

echo -e "\nFinished launching ELB and sleeping 25 second"
for i in {0..25}; do echo -ne '.'; sleep 1;done
echo "\n"

#register load balancer
aws elb register-instances-with-load-balancer --load-balancer-name MP1-lb --instances ${instArray[@]}

aws elb configure-health-check --load-balancer-name MP1-lb --health-check Target=HTTP:80/index.html,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3

echo -e "\nWaiting an additional 3 minutes (180 seconds) . before opening the ELB in a webbrowser"
for i in {0..180}; do echo -ne '.'; sleep 1;done


aws autoscaling create-launch-configuration --launch-configuration-name itmo544-launch-config --image-id $1 --key-name $6  --security-groups $4  --instance-type $3 --user-data file://../MP1-ENV/install-env.sh --iam-instance-profile $7

aws autoscaling create-auto-scaling-group --auto-scaling-group-name itmo-544-extended-auto-scaling-group-2 --launch-configuration-name itmo544-launch-config --load-balancer-names MP1-lb  --health-check-type ELB --min-size 3 --max-size 6 --desired-capacity 3 --default-cooldown 600 --health-check-grace-period 120 --vpc-zone-identifier $5


aws rds create-db-instance --db-instance-identifier mh-db --db-name mhana1DB --db-instance-class db.t1.micro --engine MySQL --allocated-storage 5 --master-username controller --master-user-password letmein888
	 
