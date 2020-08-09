# coding=utf-8

import sys
import json
import common
import requests


if __name__ == "__main__":
    gdk_branch_name = common.get_environment_variable("GDK_BRANCH", "master")
    launch_deployment = common.get_environment_variable("START_DEPLOYMENT", "true")
    slack_channel = common.get_environment_variable("SLACK_CHANNEL", "#unreal)-gdk-builds")
    project_name = common.get_environment_variable("SPATIAL_PROJECT_NAME", "unreal_gdk")
    mac_build = common.get_environment_variable("MAC_BUILD", "false")
    firebase_test = common.get_environment_variable("FIREBASE_TEST", "false")
    engine_version_count = common.get_buildkite_meta_data("engine-version-count")
    gdk_commit_hash = common.get_buildkite_meta_data("gdk_commit_hash")

    cmds = [
        'imp-ci',
        'secrets',
        'read',
        '--environment=production',
        '--buildkite-org=improbable',
        '--secret-type=slack-webhook',
        '--secret-name=unreal-gdk-slack-web-hook'
        ]
    res = common.run_shell(cmds)
    for line in res.stderr.readlines():
        utf8 = line.decode('UTF-8').strip()
        if len(utf8) > 0:
            print('%s' % utf8)
    slack_webhook_secret = res.stdout.read().decode('UTF-8')
    print(slack_webhook_secret)
