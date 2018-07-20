#!/bin/bash
#
# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Script to run the Apache Traffic Server heat stack and Locustio load generator.
# Only one copy of tempest is allowed to run at a time.
#
# usage:  NETWORK_NAME=external_net_name ./run_ats-demo.sh

# Define Variables
#
# NOTE: User will need to set up the required environment variables
# before executing this script if they differ from the default values.
#
# NOTE: This script calls run_openstack_cli.sh which puts a CR at the end
# of each line of output.  Remove using tr -d '\r'


# SET DEFAULT VALUES
export OS_USERNAME=${OS_USERNAME:-admin}
export OS_PASSWORD=${OS_PASSWORD:-password}
export OS_REGION_NAME=${OS_REGION_NAME:-RegionOne}
export NAMESPACE="${NAMESPACE:-openstack}"

STACK_NAME="${STACK_NAME:-ats-demo}"
NETWORK_NAME="${NETWORK_NAME:-external}"
ZONE="${ZONE:-nova}"
TIMEOUT="${TIMEOUT:-300}"

export SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
export OPENSTACKCLI=$SCRIPT_PATH/run_openstack_cli
echo "$SCRIPT_PATH"

## CHECK THAT OPENSTACK COMMANDS WORK (also forces download of docker image if needed)
ERROR=$($SCRIPT_PATH/run_openstack_cli.sh stack list)
if [ "$?" -ne 0 ]; then
    echo "FAILED:  Cannot access openstack."
    echo "ERROR:   ${ERROR: : -1}"
    echo "OS_REGION_NAME = ${OS_REGION_NAME}"
    echo "OS_USERNAME    = ${OS_USERNAME}"
    echo "OS_PASSWORD    = ${OS_PASSWORD}"
    exit 1
fi

## CHECK THAT ATS-DEMO IS NOT ALREADY RUNNING
STATUS=$($SCRIPT_PATH/run_openstack_cli.sh stack list -f csv | tr -d '\r' | grep "\"$STACK_NAME\"" | cut -d ',' -f 3 | sed -e 's/^"//' -e 's/"$//')
if [ -n "$STATUS" ]; then
    CTIME=$($SCRIPT_PATH/run_openstack_cli.sh stack show $STACK_NAME -c creation_time -f value | tr -d '\r')
    echo "FAILED:  ats-demo heat stack was created on [$CTIME] with status [$STATUS]."
    if [ "$STATUS" == "CREATE_COMPLETE" ]; then
        CLIENTURL=$($SCRIPT_PATH/run_openstack_cli.sh stack output show $STACK_NAME client_url -c output_value -f value | tr -d '\r')
        SERVERURL=$($SCRIPT_PATH/run_openstack_cli.sh stack output show $STACK_NAME server_url -c output_value -f value | tr -d '\r')
        echo "         You can access the demo with client_url: [$CLIENTURL] and server_url: [$SERVERURL]."
        echo "         Please delete the stack [$STACK_NAME] and redeploy if the urls are not working."
    else
        echo "         Please delete the stack and redeploy."
    fi
    exit 1
fi

## GET EXTERNAL NETWORK
NET_ID=$($SCRIPT_PATH/run_openstack_cli.sh network list -f csv | tr -d '\r' | grep "$NETWORK_NAME" | cut -d ',' -f 1 | sed -e 's/^"//' -e 's/"$//')
if [ -z "$NET_ID" ]; then
    echo "FAILED:  no network found matching [$NETWORK_NAME].  Available networks are:"
    $SCRIPT_PATH/run_openstack_cli.sh network list
    exit 1
fi

## CREATE HEAT STACK
ERROR=$($SCRIPT_PATH/run_openstack_cli.sh stack create -t ./ats-demo.yaml $STACK_NAME --parameter NetID=$NET_ID --parameter Zone=$ZONE)
if [ "$?" -ne 0 ]; then
    echo "FAILED:  error creating stack [$STACK_NAME]."
    echo "ERROR :  $ERROR"
    exit 1
fi

## WAIT UP TO $TIMEOUT SECONDS FOR STACK TO COMPLETE
i="0"
STATUS=$($SCRIPT_PATH/run_openstack_cli.sh stack show $STACK_NAME -c stack_status -f value | tr -d '\r')
while [ "$STATUS" = "CREATE_IN_PROGRESS" ] && [ $i -lt $TIMEOUT ]; do
    sleep 10
    STATUS=$($SCRIPT_PATH/run_openstack_cli.sh stack show $STACK_NAME -c stack_status -f value | tr -d '\r')
    #echo -n "."
    i=$[$i+10]
done
#echo

## ABORT IF STACK DID NOT COMPLETE
STATUS=$($SCRIPT_PATH/run_openstack_cli.sh stack show $STACK_NAME -c stack_status -f value | tr -d '\r')
if [ "$STATUS" != "CREATE_COMPLETE" ]; then
    echo "FAILED:  Stack [$STACK_NAME] did not complete.  Please check openstack for more details"
    $SCRIPT_PATH/run_openstack_cli.sh stack show $STACK_NAME
    exit 1
fi

## DISPLAY STACK OUTPUTS
CLIENTURL=$($SCRIPT_PATH/run_openstack_cli.sh stack output show $STACK_NAME client_url -c output_value -f value | tr -d '\r')
SERVERURL=$($SCRIPT_PATH/run_openstack_cli.sh stack output show $STACK_NAME server_url -c output_value -f value | tr -d '\r')
echo "SUCCESS:  You can access the demo dashboard with client_url: [$CLIENTURL]"
echo "SUCCESS:  You can stream the sample video using server_url: [$SERVERURL]"
exit 0

