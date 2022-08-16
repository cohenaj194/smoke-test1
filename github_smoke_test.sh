#!/bin/sh
set -ex

stack=$1
sleeve=$2
env_name=$3
exit_status=0

wait_for_pipelines_to_run(){
    # Wait until all piplines running for a workflow/sleeve have finished
    running_pipeline_ids=$(gh run list --workflow=$sleeve --repo=https://github.com/cohenaj194/altered-carbon \
                           | grep 'in_progress\|queued' \
                           | awk '{print $((NF-2))}')
    while [ ! -z "$running_pipeline_ids" ]; do
        sleep 30
        running_pipeline_ids=$(gh run list --workflow=$sleeve --repo=https://github.com/cohenaj194/altered-carbon \
                           | grep 'in_progress\|queued' \
                           | awk '{print $((NF-2))}')   
    done
}

find_pipeline_id(){
    # check on the last 20 pipelines
    latest_pipeline_ids=$(gh run list --workflow $sleeve --limit 50 --repo=https://github.com/cohenaj194/altered-carbon \
                      | tail -n 50 \
                      | awk '{print $((NF-2))}')


    for l_pipe_id in $latest_pipeline_ids; do
        l_pipe_stack_name=$(gh run view $l_pipe_id --repo=https://github.com/cohenaj194/altered-carbon --log \
                            | grep 'STACK_NAME:' | head -n 1 \
                            | awk -F "STACK_NAME:" '{print $2}' | awk '{print $1}')

        if [ "$l_pipe_stack_name" == "$stack" -a -z $smoketest_id ]; then
            smoketest_id=$l_pipe_id
            return
        else
            destroy_id=$l_pipe_id
            return
        fi
    done

    # fail if we dont get a match in any of the ids in the for loop
    echo "Error: no smoketest id found matching the stack name $stack in last 50 pipelines of $sleeve."
    exit 1
}

#---- smoketest ----#
echo $AC_GITHUB_ACCESS_TOKEN > github_token
gh auth login --with-token < github_token

echo "Apply stack '$stack' with sleeve '$sleeve' in environment '$env_name'."
gh workflow run $sleeve \
   --ref main \
   -f stack_name=$stack \
   -f action=apply \
   -f env_name=$env_name \
   --repo=https://github.com/cohenaj194/altered-carbon

sleep 30
wait_for_pipelines_to_run
find_pipeline_id
echo $smoketest_id
if [ -z $smoketest_id ]; then
    echo "Error smoketest_id was not found"
    exit 1
fi
smoketest_url="https://github.com/cohenaj194/altered-carbon/actions/runs/$smoketest_id"
smoketest_status=$(gh run list  --workflow env-check --repo=https://github.com/cohenaj194/altered-carbon \
                  | grep $smoketest_id \
                  |  awk '{print $2}')
# smoketest VERIFICATION
mkdir public/
if [ -z "$smoketest_status" ]; then
    echo "smoketest pipeline stopped with status: nil"
    echo "View the pipeline at: $smoketest_url"
    exit_status=1
    slack_msg=":red_circle: Failed Smoke Test $(date +%m/%d/%y) of $stack <$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID|$GITHUB_JOB> with status: <$smoketest_url|nil>"
    anybadge --label=$GITHUB_JOB --value=nil --file=public/$GITHUB_JOB.svg passing=green nil=blue
elif [ $smoketest_status != "success" ]; then
    echo "smoketest pipeline stopped with status: $smoketest_status"
    echo "View the pipeline at: $smoketest_url"
    exit_status=1
    slack_msg=":red_circle: Failed Smoke Test $(date +%m/%d/%y) of $stack <$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID|$GITHUB_JOB> with status: <$smoketest_url|$smoketest_status>"
    anybadge --label=$GITHUB_JOB --value=failing --file=public/$GITHUB_JOB.svg passing=green failing=red
else
    echo "smoketest pipeline passed with status: $smoketest_status"
    echo "View the pipeline at: $smoketest_url"
    slack_msg=":white_check_mark: Passed Smoke Test $(date +%m/%d/%y) of $stack <$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID|$GITHUB_JOB> with status: <$smoketest_url|$smoketest_status>"
    anybadge --label=$GITHUB_JOB --value=passing --file=public/$GITHUB_JOB.svg passing=green failing=red
fi

# upload badge to $BADGE_BUCKET and make publicly accessible
aws s3 cp public/$GITHUB_JOB.svg  "s3://$BADGE_BUCKET/$GITHUB_JOB.svg"
aws s3api put-object-acl --bucket $BADGE_BUCKET --key $GITHUB_JOB.svg --acl public-read

msg_data="{\"text\":\"${slack_msg}\"}"
echo "$msg_data"
curl -X POST -H 'Content-type: application/json' --data "$msg_data" $SLACK_CHANNEL_WEBHOOK

#---- DESTROY ----#
echo "Destroy stack '$stack' with sleeve '$sleeve' in environment '$env_name'."

gh workflow run $sleeve \
   --ref main \
   -f stack_name=$stack \
   -f action=destroy \
   -f env_name=$env_name \
   --repo=https://github.com/cohenaj194/altered-carbon

sleep 30
wait_for_pipelines_to_run
find_pipeline_id
echo $destroy_id
if [ -z $destroy_id ]; then
    echo "Error destroy_id was not found"
    exit 1
fi
destroy_url="https://github.com/cohenaj194/altered-carbon/actions/runs/$destroy_id"
destroy_status=$(gh run list  --workflow env-check --repo=https://github.com/cohenaj194/altered-carbon \
                  | grep $smoketest_id \
                  |  awk '{print $2}')

# DESTROY VERIFICATION
if [ -z "$destroy_status" ]; then
    echo "destroy pipeline stopped with status: nil"
    echo "View the pipeline at: $destroy_url"
    exit_status=1
    slack_msg=":red_circle: Failed Smoke Test $(date +%m/%d/%y) destroy of $stack <$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID|$GITHUB_JOB> with status: <$destroy_url|nil>"
elif [ $destroy_status != "success" ]; then
    echo "Destroy pipeline stopped with status: $destroy_status"
    echo "View the pipeline at: $destroy_url"
    slack_msg=":red_circle: Failed Smoke Test $(date +%m/%d/%y) destroy of $stack <$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID|$GITHUB_JOB> with status: <$destroy_url|$destroy_status>"
    exit_status=1
else
    echo "Destroy pipeline passed with status: $destroy_status"
    echo "View the pipeline at: $destroy_url"
    slack_msg=":white_check_mark: Passed Smoke Test $(date +%m/%d/%y) destroy of $stack <$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID|$GITHUB_JOB> with status: <$destroy_url|$destroy_status>"
fi

echo "View the smoketest pipeline at: $smoketest_url"

msg_data="{\"text\":\"${slack_msg}\"}"
echo "$msg_data"
curl -X POST -H 'Content-type: application/json' --data "$msg_data" $SLACK_ALERT_CHANNEL_WEBHOOK

#---- Ticket Generation ----#
# Uncomment to auto create gitlab issues when smoke test fails

# if [ $exit_status != 0 ]; then
#   failed_jobs=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_API_PRIVATE_TOKEN" "$pipeline_url/jobs")
#   failed_stage=$(echo $failed_jobs | jq '.[] | select(.status=="failed") | .stage')
#   failed_name=$(echo $failed_jobs | jq '.[] | select(.status=="failed") | .name')
#   # the real tickets we want to generate
#   git clone https://$GITLAB_TOKEN_NAME:$GITLAB_API_PRIVATE_TOKEN@gitlab.com/yourteam/yourproject/technical.git
#   cd technical
#   glab issue create --title="$smoketest_status $GITHUB_JOB $(date +%m/%d/%y)" --description="**Environment:** $(echo $GITHUB_JOB| awk -F "_" '{print $NF}') **ENV_NAME:** $env_name **Stack:** $stack. $GITHUB_JOB has failed for stack $stack at stage $failed_stage in job $failed_name. View the stack deployment at $smoketest_url. View the stack destroy at $destroy_url."
#   cd ..
# fi

exit $exit_status
