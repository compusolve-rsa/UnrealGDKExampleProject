# coding=utf-8

import os
import re
import common
from datetime import datetime

def get_gdk_commit_hash(gdk_repo, gdk_branch_name):
    cmds = [
        'git',
        'ls-remote',
        '--head',
        '\"%s\"' % gdk_repo,
        '\"%s\"' % gdk_branch_name
    ]
    res = common.run_shell(cmds)
    return res.stdout.read().decode('UTF-8')[0:6]


def generate_auth_token(project_name):
    common.pushd('spatial')
    cmds = [
        'spatial',
        'project',
        'auth',
        'dev-auth-token',
        'create',
        '--description="Token generated for Example Project CI"',
        '--project_name=%s' % project_name
    ]
    res = common.run_shell(cmds)
    utf8_string = res.stdout.read().decode('UTF-8')
    print(utf8_string)
    url = re.findall(r'token_secret:\\"(.+)\\"', utf8_string)
    print(url)
    common.set_buildkite_meta_data('auth-token', url[0].decode('ASCII'))


if __name__ == "__main__":
    gdk_repo = common.get_environment_variable('GDK_REPOSITORY', 'git@github.com:spatialos/UnrealGDK.git')
    gdk_branch_name = common.get_environment_variable('GDK_BRANCH', 'master')
    project_name = common.get_environment_variable('SPATIAL_PROJECT_NAME', 'unreal_gdk')

    common.log('get-gdk-head-commit')
    gdk_commit_hash = get_gdk_commit_hash(gdk_repo, gdk_branch_name)
    
    common.log('generate-project-name')
    engine_version_count = common.get_buildkite_meta_data('engine-version-count')
    now = datetime.now()
    for index in range(0, int(engine_version_count)):
        index_str = '%d' % (index + 1)
        name = 'deployment-name-%s' % index_str
        value = 'exampleproject_%s_%s_%s' % (index_str, now.strftime('%m%d_%M%M%S'), gdk_commit_hash)
        common.set_buildkite_meta_data(name, value)
    
    common.log('genreate-auth-token')
    generate_auth_token(project_name)

    exit(0)
