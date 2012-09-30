#!/bin/sh

# must return 0 and YAML in order to work properly according to documentation
# this script should query amazon services (dynamodb/s3 etc) to get required 
# info for a node and return the data in YAML format

# for now it is just a dummy ENC for testing
# it just sets environment to sng_dev for every node that is requesting catalog from us

echo 'parameters:'
echo ' environment: sng_dev'
#echo ' nodename: ip-10-29-224-201.ec2.internal'
exit 0

