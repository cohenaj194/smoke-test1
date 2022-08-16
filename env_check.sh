#!/bin/sh
set -e

stack=$1
sleeve=$2
env_name=$3
exit_status=0
#---- smoketest ----#
smoketest_trigger=$(curl --request POST \
                    --form token=$AC_GITLAB_PIPELINE_TRIGGER_TOKEN \
                    --form ref=master \
                    --form "variables[STACK_NAME]=$stack" \
                    --form "variables[SLEEVE]=$sleeve" \
                    --form "variables[ENV_NAME]=$env_name" \
                    https://gitlab.com/api/v4/projects/$AC_GITLAB_PROJECT_ID/trigger/pipeline)

echo $smoketest_trigger | jq .
smoketest_id=$(echo $smoketest_trigger| jq -r .id)
pipeline_url="https://gitlab.com/api/v4/projects/$AC_GITLAB_PROJECT_ID/pipelines/$smoketest_id"
smoketest_url="$(echo $smoketest_trigger | jq -r .web_url)"

# watch pipeline status
smoketest_status=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_API_PRIVATE_TOKEN" "$pipeline_url" | jq -r .detailed_status.icon)
while [ "$smoketest_status" == "status_pending" -o "$smoketest_status" == "status_running" -o "$smoketest_status" == "null" ]; do
    echo "smoketest status: $smoketest_status"
    sleep 30
    smoketest_status="$(curl -s --header "PRIVATE-TOKEN: $GITLAB_API_PRIVATE_TOKEN" "$pipeline_url" | jq -r .detailed_status.icon)"
done

# smoketest VERIFICATION
mkdir public/
if [ -z "$smoketest_status" ]; then
    echo "smoketest pipeline stopped with status: nil"
    echo "View the pipeline at: $smoketest_url"
    exit_status=1
    slack_msg=":red_circle: Failed Smoke Test $(date +%m/%d/%y) of $stack <$CI_PROJECT_URL/-/jobs/$CI_JOB_ID|$CI_JOB_NAME> with status: <$smoketest_url|nil>"
    anybadge --label=$CI_JOB_NAME --value=nil --file=public/$CI_JOB_NAME.svg passing=green nil=blue
elif [ $smoketest_status != "status_success" ]; then
    echo "smoketest pipeline stopped with status: $smoketest_status"
    echo "View the pipeline at: $smoketest_url"
    exit_status=1
    slack_msg=":red_circle: Failed Smoke Test $(date +%m/%d/%y) of $stack <$CI_PROJECT_URL/-/jobs/$CI_JOB_ID|$CI_JOB_NAME> with status: <$smoketest_url|$smoketest_status>"
    anybadge --label=$CI_JOB_NAME --value=failing --file=public/$CI_JOB_NAME.svg passing=green failing=red
else
    echo "smoketest pipeline passed with status: $smoketest_status"
    echo "View the pipeline at: $smoketest_url"
    slack_msg=":white_check_mark: Passed Smoke Test $(date +%m/%d/%y) of $stack <$CI_PROJECT_URL/-/jobs/$CI_JOB_ID|$CI_JOB_NAME> with status: <$smoketest_url|$smoketest_status>"
    anybadge --label=$CI_JOB_NAME --value=passing --file=public/$CI_JOB_NAME.svg passing=green failing=red
fi

# upload badge to $BADGE_BUCKET and make publicly accessible
aws s3 cp public/$CI_JOB_NAME.svg  "s3://$BADGE_BUCKET/$CI_JOB_NAME.svg"
aws s3api put-object-acl --bucket $BADGE_BUCKET --key $CI_JOB_NAME.svg --acl public-read

# Create Slack messages
msg_data="{\"text\":\"${slack_msg}\"}"
echo "$msg_data"
echo "View the smoketest pipeline at: $smoketest_url"

curl -X POST -H 'Content-type: application/json' --data "$msg_data" $SLACK_CHANNEL_WEBHOOK
curl -X POST -H 'Content-type: application/json' --data "$msg_data" $SLACK_ALERT_CHANNEL_WEBHOOK

exit $exit_status
