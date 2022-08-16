# Smoke Test

The `smoke-test` repo is paired with `altered-carbon` to automatically running regular scheduled smoke tests against altered-carbon sleeves, report the status of these tests to a slack channel and create badges that can be linked into the readme of your altered-carbon repo or other locations. 

`smoke-test` also contains other complex features such as automatic gitlab issue ticket generation. 

## CI/CD Env Vars

Add the following variables into your CI/CD pipeline variables to enable smoke tests:

| Variable Name | Description | Example |
|---|---|---|
| AC_GITLAB_PIPELINE_TRIGGER_TOKEN | The trigger token of your altered carbon project | `foobar4lk13h4l1h341hl34hl1324l` |
| AC_GITLAB_PROJECT_ID | The project ID of your local version of Altered-Carbon, this value is important for api interaction and pipeline url's | `12345678` |
| AWS_ACCESS_KEY_ID | An aws access key, used for uploading job badges to your s3 badge bucket | |
| AWS_REGION | The region where your s3 badge bucket is located | `us-east-1` |
| AWS_ACCESS_KEY_ID | An aws secret access key, used for uploading job badges to your s3 badge bucket | |
| BADGE_BUCKET | The name of your public bucket which only stores badges used created based on the status of smoke test jobs | `my-badge-bucket-name` |
| GITLAB_API_PRIVATE_TOKEN | Create a gitlab private api token and add this value under `GITLAB_API_PRIVATE_TOKEN`.  This is used to monitor the status and sucess or failure of jobs | `p-1234567qwe890rtyuz` |
| GITLAB_TOKEN_NAME | Include the name of your gitlab private api token if you want to enable automatic ticket generation | `foobar` |
| SLACK_CHANNEL_WEBHOOK | The slack channel ID where sucess or failure messages will be sent based on jobs run | `https://hooks.slack.com/services/SOMEGUBBERISH1234/MOREGIBBERISH1234/EVENMOREGIBBERISH1234` |
| SLACK_ALERT_CHANNEL_WEBHOOK | The slack channel ID where sucess or failure messages will be sent of destroy sections of jobs to reduce spam | `https://hooks.slack.com/services/SOMEGUBBERISH1234/MOREGIBBERISH1234/EVENMOREGIBBERISH1234` |

## Schedules and Branching

To create a smoke test, add a schedule to this project.  Use a cron similar to `0 18 * * *` to ensure the pipeline runs every day.  If instead you only want your tests running once per week use a cron similar to `0 6 * * 3`.

If you need to spread out the number of smoke tests run, create new branches replace existing jobs in the `.gitlab-ci.yml` file with the extra jobs you wish to include and then create a new schedule for your new branch. The `smoke_test.sh` script is generic enough so that only jobs in `.gitlab-ci.yml` will need to be changed between the branches. 

## Badge Bucket

Create a public S3 bucket and only upload the badge images to this bucket.  This will allow you to easily add badges into your gitlab project page. 

## Slack Channels

Create slack channels where you want messages sent that will report on the status of your smoke test messages. These messages use the following format:

```
    slack_msg=":white_check_mark: Passed Smoke Test $(date +%m/%d/%y) of $stack <$CI_PROJECT_URL/-/jobs/$CI_JOB_ID|$CI_JOB_NAME> with status: <$smoketest_url|$smoketest_status>"
```

They will include links to the ci/cd pipelines running in your `smoke-test` repo and your `altered-carbon` repo. The message will also contain the date when the pipeline was run, the `STACK_NAME` used in the test and the name of the smoke test job. This will easily allow you to check on the status of any pipelines run through smoke test and altered carbon. 

## Automatic Ticket Generation

Uncomment the `Ticket Generation` section of `smoke_test.sh` to enable smoke test to auto create gitlab issues in your `altered-carbon` project when a smoke test fails.