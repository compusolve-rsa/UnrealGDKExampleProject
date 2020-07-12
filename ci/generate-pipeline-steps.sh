#!/bin/bash
set -euo pipefail

BUILDKITE_TEMPLATE_FILE=ci/nightly.template.steps.yaml

# Download the unreal-engine.version file from the GDK repo so we can run the example project builds on the same versions the GDK was run against.
# This is not the pinnacle of engineering, as we rely on GitHub's web interface to download the file, but it seems like GitHub disallows git archive
# which would be our other option for downloading a single file.
# Also resolve the GDK branch to run against. The order of priority is:
# GDK_BRANCH envvar > same-name branch as the branch we are currently on > UnrealGDKVersion.txt > "master".

echo --- init-gdk-branch

GDK_BRANCH_LOCAL="${GDK_BRANCH:-}"
if [ -z "${GDK_BRANCH_LOCAL}" ]; then
    GDK_REPO_HEADS=$(git ls-remote --heads "git@github.com:spatialos/UnrealGDK.git" "${BUILDKITE_BRANCH}")
    EXAMPLEPROJECT_REPO_HEAD="refs/heads/${BUILDKITE_BRANCH}"
    if echo "${GDK_REPO_HEADS}" | grep -qF "${EXAMPLEPROJECT_REPO_HEAD}"; then
        GDK_BRANCH_LOCAL="${BUILDKITE_BRANCH}"
    else
        GDK_VERSION=$(cat UnrealGDKVersion.txt)
        if [ -z "${GDK_VERSION}" ]; then
            GDK_BRANCH_LOCAL="master"
        else
            GDK_BRANCH_LOCAL="${GDK_VERSION}"
        fi
    fi
    echo ${GDK_BRANCH_LOCAL}
fi

echo --- number-of-tries
NUMBER_OF_TRIES=0
while [ $NUMBER_OF_TRIES -lt 5 ]; do
    CURL_TIMEOUT=$((10<<NUMBER_OF_TRIES))
    NUMBER_OF_TRIES=$((NUMBER_OF_TRIES+1))
    echo "Trying to download unreal-engine.version from GitHub's UnrealGDK repository, try: $NUMBER_OF_TRIES, timeout: $CURL_TIMEOUT seconds ..."
    curl -L -m $CURL_TIMEOUT https://raw.githubusercontent.com/spatialos/UnrealGDK/$GDK_BRANCH_LOCAL/ci/unreal-engine.version -o ci/unreal-engine.version
    if [ $? -eq 0 ]; then
        break
    fi
done

if [[ -n "${NIGHTLY_BUILD:-}" ]]; then
    export ANDROID_AUTOTEST="1"

    if [[ -n "${MAC_BUILD:-}" ]]; then
        export IOS_AUTOTEST="1"
    fi
fi

if [[ -n "${SLACK_NOTIFY:-}" ]] || [[ -n "${NIGHTLY_BUILD:-}" ]] || [ ${BUILDKITE_BRANCH} -eq "master" ]]; then
    echo --- add-slack-notify-step
    buildkite-agent pipeline upload "ci/nightly.slack.notify.yaml"
    
    echo --- add-wait-step
    sed "s|NAME_PLACEHOLDER|Wait-auto-test|g" "ci/nightly.wait.yaml" | buildkite-agent pipeline upload
fi

# This script generates BuildKite steps for each engine version we want to test against.
# We retrieve these engine versions from the unreal-engine.version file in the UnrealGDK repository.
# The steps are based on the template in nightly.template.steps.yaml.

# Default to only testing the first version listed in the unreal-engine.version file
MAXIMUM_ENGINE_VERSION_COUNT_LOCAL="${MAXIMUM_ENGINE_VERSION_COUNT:-1}"
if [ -z "${ENGINE_VERSION}" ]; then 
    echo "Generating build steps for the first ${MAXIMUM_ENGINE_VERSION_COUNT_LOCAL} engine versions listed in unreal-engine.version"
    
    IFS=$'\n'
    VERSIONS=$(cat < ci/unreal-engine.version)

    #  turn on firebase auto test steps
    echo --- handle-firebase-steps
    if [[ -n "${NIGHTLY_BUILD:-}" ]]; then
        # set default test result
        buildkite-agent meta-data set "firebase-android-succeed" "0"
        buildkite-agent meta-data set "firebase-android-total" "0"
        buildkite-agent meta-data set "firebase-ios-succeed" "0"
        buildkite-agent meta-data set "firebase-ios-total" "0"

        echo --- add-auto-test-steps
        BUILDKITE_AUTOTEST_TEMPLATE_FILE=ci/nightly.autotest.yaml
        COUNT=1
        for VERSION in ${VERSIONS}; do
            echo --- handle-autotest-COMMIT_HASH:${COMMIT_HASH}-COUNT:${COUNT}
            if ((COUNT > MAXIMUM_ENGINE_VERSION_COUNT_LOCAL)); then
                break
            fi
            
            ENGINE_COMMIT_FORMATED_HASH=$(sed "s/ /_/g" <<< ${VERSION} | sed "s/-/_/g" | sed "s/\./_/g")
            REPLACE_ENGINE_COMMIT_HASH="s|ENGINE_COMMIT_HASH_PLACEHOLDER|${VERSION}|g"
            REPLACE_ENGINE_COMMIT_FORMATED_HASH="s|ENGINE_COMMIT_FORMATED_HASH_PLACEHOLDER|${ENGINE_COMMIT_FORMATED_HASH}|g"

            if [[ -n "${ANDROID_AUTOTEST:-}" ]]; then
                REPLACE_DEVICE_STRING="s|DEVICE_PLACEHOLDER|android|g"
                sed "s|ENGINE_COMMIT_HASH_PLACEHOLDER|${COMMIT_HASH}|g" "${BUILDKITE_AUTOTEST_TEMPLATE_FILE}" | sed $REPLACE_DEVICE_STRING | buildkite-agent pipeline upload
            fi
            
            if [[ -n "${MAC_BUILD:-}" ]] && [[ -n "${IOS_AUTOTEST:-}" ]]; then
                REPLACE_DEVICE_STRING="s|DEVICE_PLACEHOLDER|ios|g"
                sed "s|ENGINE_COMMIT_HASH_PLACEHOLDER|${COMMIT_HASH}|g" "${BUILDKITE_AUTOTEST_TEMPLATE_FILE}" | sed $REPLACE_DEVICE_STRING | buildkite-agent pipeline upload
            fi
            COUNT=$((COUNT+1))
        done
        
        # add wait step
        echo --- add-wait-step
        sed "s|NAME_PLACEHOLDER|Wait-auto-test|g" "ci/nightly.wait.yaml" | buildkite-agent pipeline upload
    fi

    STEP_NUMBER=1
    for VERSION in ${VERSIONS}; do
        echo --- handle-setup-and-build-COMMIT_HASH:${COMMIT_HASH}-STEP_NUMBER:${STEP_NUMBER}
        if ((STEP_NUMBER > MAXIMUM_ENGINE_VERSION_COUNT_LOCAL)); then
            break
        fi

        ENGINE_COMMIT_FORMATED_HASH=$(sed "s/ /_/g" <<< ${VERSION} | sed "s/-/_/g" | sed "s/\./_/g")
        REPLACE_ENGINE_COMMIT_HASH="s|ENGINE_COMMIT_HASH_PLACEHOLDER|${VERSION}|g"
        REPLACE_ENGINE_COMMIT_FORMATED_HASH="s|ENGINE_COMMIT_FORMATED_HASH_PLACEHOLDER|${ENGINE_COMMIT_FORMATED_HASH}|g"

        export ENGINE_COMMIT_HASH="${VERSION}"
        echo "ENGINE_COMMIT_HASH:${ENGINE_COMMIT_HASH}"
        export STEP_NUMBER
        echo "STEP_NUMBER:${STEP_NUMBER}"
        export GDK_BRANCH="${GDK_BRANCH_LOCAL}"
        echo "GDK_BRANCH:${GDK_BRANCH}"
       
        if [[ -n "${MAC_BUILD:-}" ]]; then
            export BUILDKITE_COMMAND="./ci/setup-and-build.sh"
            REPLACE_STRING="s|AGENT_PLACEHOLDER|macos|g"
        else
            export BUILDKITE_COMMAND="powershell -NoProfile -NonInteractive -InputFormat Text -Command ./ci/setup-and-build.ps1"
            REPLACE_STRING="s|AGENT_PLACEHOLDER|windows|g"
        fi
        sed REPLACE_ENGINE_COMMIT_HASH "${BUILDKITE_TEMPLATE_FILE}" | sed REPLACE_ENGINE_COMMIT_FORMATED_HASH | sed $REPLACE_STRING | buildkite-agent pipeline upload
        STEP_NUMBER=$((STEP_NUMBER+1))
    done
    # We generate one build step for each engine version, which is one line in the unreal-engine.version file.
    # The number of engine versions we are dealing with is therefore the counting variable from the above loop minus one.
    STEP_NUMBER=$((STEP_NUMBER-1))
    buildkite-agent meta-data set "engine-version-count" "${STEP_NUMBER}"
else
    echo --- "Generating steps for the specified engine version: ${ENGINE_VERSION}"
    export ENGINE_COMMIT_HASH="${ENGINE_VERSION}"
    echo "ENGINE_COMMIT_HASH:${ENGINE_COMMIT_HASH}"
    export GDK_BRANCH="${GDK_BRANCH_LOCAL}"
    echo "GDK_BRANCH:${GDK_BRANCH}"
    ENGINE_COMMIT_FORMATED_HASH=$(sed "s/ /_/g" <<< ${ENGINE_VERSION} | sed "s/-/_/g" | sed "s/\./_/g")
    REPLACE_ENGINE_COMMIT_HASH="s|ENGINE_COMMIT_HASH_PLACEHOLDER|${ENGINE_COMMIT_HASH}|g"
    REPLACE_ENGINE_COMMIT_FORMATED_HASH="s|ENGINE_COMMIT_FORMATED_HASH_PLACEHOLDER|${ENGINE_COMMIT_FORMATED_HASH}|g"
    
    #  turn on firebase auto test steps
    if [[ -n "${NIGHTLY_BUILD:-}" ]]; then
        echo --- add-auto-test
        BUILDKITE_AUTOTEST_TEMPLATE_FILE=ci/nightly.autotest.yaml
        
        if [[ -n "${ANDROID_AUTOTEST:-}" ]]; then
            REPLACE_STRING="s|DEVICE_PLACEHOLDER|android|g"
            sed REPLACE_ENGINE_COMMIT_HASH "${BUILDKITE_AUTOTEST_TEMPLATE_FILE}" | sed $REPLACE_ENGINE_COMMIT_FORMATED_HASH | sed $REPLACE_STRING | buildkite-agent pipeline upload
        fi
        
        if [[ -n "${MAC_BUILD:-}" ]] && [[ -n "${IOS_AUTOTEST:-}" ]]; then
            REPLACE_STRING="s|DEVICE_PLACEHOLDER|ios|g"
            sed REPLACE_ENGINE_COMMIT_HASH "${BUILDKITE_AUTOTEST_TEMPLATE_FILE}" | sed $REPLACE_ENGINE_COMMIT_FORMATED_HASH | sed $REPLACE_STRING | buildkite-agent pipeline upload
        fi

        echo --- add-wait-step
        sed "s|NAME_PLACEHOLDER|Wait-${ENGINE_COMMIT_FORMATED_HASH}-auto-test|g" "ci/nightly.wait.yaml" | buildkite-agent pipeline upload
    fi

    if [[ -n "${MAC_BUILD:-}" ]]; then
        REPLACE_STRING="s|AGENT_PLACEHOLDER|macos|g"
    else
        REPLACE_STRING="s|AGENT_PLACEHOLDER|windows|g"
    fi
    sed REPLACE_ENGINE_COMMIT_HASH "${BUILDKITE_TEMPLATE_FILE}" | sed REPLACE_ENGINE_COMMIT_FORMATED_HASH | sed $REPLACE_STRING | buildkite-agent pipeline upload

fi
