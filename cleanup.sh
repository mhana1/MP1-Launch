#!/bin/bash

declare -a cleanupARR
declare -a cleanupLBARR
declare -a dbInstanceARR

aws ec2 describe-instances --filter Name=instance-state-code,Values=16 --output table | grep InstanceId | sed "s/|//g" | tr -d ' ' | sed "s/InstanceId//g"

mapfile -t cleanupARR < <(aws ec2 describe-instances --filter Name=instance-state-code,Values=16 --output table | grep InstanceId | sed "s/|//g" | tr -d ' ' | sed "s/InstanceId//g")

echo "Terminating instances..."
echo "Instance(s) IDs found:  ${cleanupARR[@]}"

aws ec2 terminate-instances --instance-ids ${cleanupARR[@]} 
echo "Waiting till instances are terminated..."
aws ec2 wait instance-terminated --instance-ids ${cleanupARR[@]}

echo "Cleaning up existing Load Balancers..."
mapfile -t cleanupLBARR < <(aws elb describe-load-balancers --output json | grep LoadBalancerName | sed "s/[\"\:\, ]//g" | sed "s/LoadBalancerName//g")

echo "LoadBalancer(s) found: ${cleanupLBARR[@]}"

LENGTH=${#cleanupLBARR[@]}
for (( i=0; i<${LENGTH}; i++)); 
  do
  aws elb delete-load-balancer --load-balancer-name ${cleanupLBARR[i]} --output text
  sleep 1
done

:'
# Delete existing RDS  Databases
# Note if deleting a read replica this is not your command 
echo "Deletinig existing databases..."
mapfile -t dbInstanceARR < <(aws rds describe-db-instances --output json | grep "\"DBInstanceIdentifier" | sed "s/[\"\:\, ]//g" | sed "s/DBInstanceIdentifier//g" )

if [ ${#dbInstanceARR[@]} -gt 0 ]
   then
   echo "Deleting existing RDS database-instances"
   LENGTH=${#dbInstanceARR[@]}  

   # http://docs.aws.amazon.com/cli/latest/reference/rds/wait/db-instance-deleted.html
      for (( i=0; i<${LENGTH}; i++));
      do 
      aws rds delete-db-instance --db-instance-identifier ${dbInstanceARR[i]} --skip-final-snapshot --output text
      aws rds wait db-instance-deleted --db-instance-identifier ${dbInstanceARR[i]} --output text
      sleep 1
   done
fi

'
# Create Launchconf and Autoscaling groups
echo "Deleting existing autoscaling groups..."
LAUNCHCONF=(`aws autoscaling describe-launch-configurations --output json | grep LaunchConfigurationName | sed "s/[\"\:\, ]//g" | sed "s/LaunchConfigurationName//g"`)

SCALENAME=(`aws autoscaling describe-auto-scaling-groups --output json | grep AutoScalingGroupName | sed "s/[\"\:\, ]//g" | sed "s/AutoScalingGroupName//g"`)

echo "Autoscaling group(s) found: " ${SCALENAME[@]}

if [ ${#SCALENAME[@]} -gt 0 ]
  then

#aws autoscaling detach-launch-
#aws autoscaling update-auto-scaling-group --auto-scaling-group-name $SCALENAME --min-size 0 --max-size 0
aws autoscaling disable-metrics-collection --auto-scaling-group-name $SCALENAME

sleep 10

aws autoscaling delete-auto-scaling-group --auto-scaling-group-name $SCALENAME --force-delete


aws autoscaling delete-launch-configuration --launch-configuration-name $LAUNCHCONF

fi

echo "All done"
