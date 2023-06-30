#!/bin/bash


CHECK_INTERVAL=15


function handle_error {
    echo "Error: $1"
    exit 1
}


function run_tests {
    pytest --verbose --html=pytest_report.html --self-contained-html
}


function upload_report {
    local report_name=$1
    cp $report_name $REPOSITORY_NAME_REPORT/
}


function check_code_style {
    black --check --diff *.py > black_output.txt
}


function create_github_issue {
    local commit_hash=$1
    local pytest_report_url="https://$REPOSITORY_OWNER.github.io/$REPOSITORY_NAME_REPORT/pytest_report.html"
    local black_report_url="https://$REPOSITORY_OWNER.github.io/$REPOSITORY_NAME_REPORT/black_report.html"

    local title="${commit_hash:0:7} failed tests and code style check."
    local body="Commit: $commit_hash failed tests and code style check.

Failed Tests: pytest report - $pytest_report_url

Code Style: black report - $black_report_url"

    curl --request POST \
        --header "Accept: application/vnd.github+json" \
        --header "Authorization: Bearer $GITHUB_ACCESS_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{\"title\":\"$title\",\"body\":\"$body\",\"assignees\":[\"$(git log -1 --pretty=format:'%ae')\"]}" \
        "https://api.github.com/repos/$REPOSITORY_OWNER/$REPOSITORY_NAME_CODE/issues"
}


function tag_commit_success {
    local success_tag="${REPOSITORY_BRANCH_CODE}-ci-success"
    git tag -a "$success_tag" -m "All checks passed"
    git push origin --tags
}

if [ "$#" -ne 7 ]; then
    echo "Usage: $0 <REPOSITORY_OWNER> <REPOSITORY_NAME_CODE> <REPOSITORY_NAME_REPORT> <REPOSITORY_BRANCH_CODE> <REPOSITORY_BRANCH_REPORT> <GITHUB_ACCESS_TOKEN> <CODE_BRANCH_NAME>"
    exit 1
fi


REPOSITORY_OWNER=$1
REPOSITORY_NAME_CODE=$2
REPOSITORY_NAME_REPORT=$3
REPOSITORY_BRANCH_CODE=$4
REPOSITORY_BRANCH_REPORT=$5
GITHUB_ACCESS_TOKEN=$6
CODE_BRANCH_NAME=$7

while true; do
    git fetch origin $REPOSITORY_BRANCH_CODE || handle_error "Failed to fetch changes from $REPOSITORY_BRANCH_CODE"

    CHANGES=$(git rev-list HEAD..origin/$REPOSITORY_BRANCH_CODE --reverse)
    if [ -z "$CHANGES" ]; then
        echo "No new commits. Sleeping for $CHECK_INTERVAL seconds..."
        sleep $CHECK_INTERVAL
        continue
    fi

    for COMMIT_HASH in $CHANGES; do
        echo "Processing commit: $COMMIT_HASH"

        REPOSITORY_PATH_CODE=$(mktemp --directory --tmpdir=/path/to/temp)
        REPOSITORY_PATH_REPORT=$(mktemp --directory --tmpdir=/path/to/temp)

        git checkout $COMMIT_HASH || handle_error "Failed to checkout commit $COMMIT_HASH"

        git clone git@github.com:$REPOSITORY_OWNER/$REPOSITORY_NAME_CODE.git $REPOSITORY_PATH_CODE || handle_error "Failed to clone code repository"

        cd $REPOSITORY_PATH_CODE
        run_tests || handle_error "Unit tests failed"

        upload_report "pytest_report.html" || handle_error "Failed to upload pytest report"

        check_code_style || handle_error "Code style check failed"

        upload_report "black_report.html" || handle_error "Failed to upload black report"

        rm -rf $REPOSITORY_PATH_CODE
        rm -rf $REPOSITORY_PATH_REPORT

        if [ -s black_output.txt ] || [ $? -ne 0 ]; then
            echo "Code style check failed."


            create_github_issue "$COMMIT_HASH" || handle_error "Failed to create GitHub issue"
        else
            tag_commit_success || handle_error "Failed to tag commit as success"
        fi
    done

    echo "Processed all new commits. Sleeping for $CHECK_INTERVAL seconds..."
    sleep $CHECK_INTERVAL
done
