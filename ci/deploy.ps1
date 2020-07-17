param(
  [string] $launch_deployment = "false",
  [string] $gdk_branch_name = "master",
  [string] $parent_event_name = "build-unreal-gdk-example-project-:windows:"
)

. "$PSScriptRoot\common.ps1"

Start-Event "deploy-game" $parent_event_name
    # Use the shortened commit hash gathered during GDK plugin clone and the current date and time to distinguish the deployment
    $android_autotest = Get-Meta-Data -variable_name "android-autotest" -default_value "0"
    if ($android_autotest -eq "1") {
        $deployment_name = Get-Meta-Data -variable_name "deployment-name-$($env:STEP_NUMBER)" -default_value "0"
    }
    else {
        $date_and_time = Get-Date -Format "MMdd_HHmm"
        $deployment_name = "exampleproject$($env:STEP_NUMBER)_${date_and_time}_$($gdk_commit_hash)"
    }

    $assembly_name = "$($deployment_name)_asm"
    $runtime_version = Get-Env-Variable-Value-Or-Default -environment_variable_name "SPATIAL_RUNTIME_VERSION" -default_value ""
    $project_name = Get-Env-Variable-Value-Or-Default -environment_variable_name "SPATIAL_PROJECT_NAME" -default_value "unreal_gdk"

    Write-Output "STEP_NUMBER: ${env:STEP_NUMBER}"
    Write-Output "gdk_commit_hash: ${gdk_commit_hash}"
    Write-Output "deployment_name: ${deployment_name}"
    Write-Output "assembly_name: ${assembly_name}"

    $deploy_parent_event_name = "deploy-cloud-deployment-of-unreal-gdk-example-project-:windows:"
pushd "spatial"
    Start-Event "build-worker-configurations" $deploy_parent_event_name
        $build_configs_process = Start-Process -Wait -PassThru -NoNewWindow -FilePath "spatial" -ArgumentList @(`
            "build", `
            "build-config"
        )

        if ($build_configs_process.ExitCode -ne 0) {
            Write-Output "Failed to build worker configurations for the project. Error: $($build_configs_process.ExitCode)"
            Throw "Failed to build worker configurations"
        }
    Finish-Event "build-worker-configurations" $deploy_parent_event_name

    Start-Event "prepare-for-run" $deploy_parent_event_name
        $prepare_for_run_process = Start-Process -Wait -PassThru -NoNewWindow -FilePath "spatial" -ArgumentList @(`
            "prepare-for-run", `
            "--log_level=debug"
        )

        if ($prepare_for_run_process.ExitCode -ne 0) {
            Write-Output "Failed to prepare for a Spatial cloud launch. Error: $($prepare_for_run_process.ExitCode)"
            Throw "Spatial prepare for run failed"
        }
    Finish-Event "prepare-for-run" $deploy_parent_event_name
    

    Start-Event "upload-assemblies" $deploy_parent_event_name
        $upload_assemblies_process = Start-Process -Wait -PassThru -NoNewWindow -FilePath "spatial" -ArgumentList @(`
            "cloud", `
            "upload", `
            "$assembly_name", `
            "--project_name=$project_name", `
            "--log_level=debug", `
            "--force"
        )

        if ($upload_assemblies_process.ExitCode -ne 0) {
            Write-Output "Failed to upload assemblies to cloud. Error: $($upload_assemblies_process.ExitCode)"
            Throw "Failed to upload assemblies"
        }
    Finish-Event "upload-assemblies" $deploy_parent_event_name

    Start-Event "launch-deployment" $deploy_parent_event_name
        # Determine whether deployment should be launched (it will by default)
        if ($launch_deployment -eq "true") {
            $launch_deployment_process = Start-Process -Wait -PassThru -NoNewWindow -FilePath "spatial" -ArgumentList @(`
                "cloud", `
                "launch", `
                "$assembly_name", `
                "$deployment_launch_configuration", `
                "$deployment_name", `
                "--runtime_version=$runtime_version", `
                "--project_name=$project_name", `
                "--snapshot=$deployment_snapshot_path", `
                "--cluster_region=$deployment_cluster_region", `
                "--log_level=debug", `
                "--tags=ttl_1_hours", `
                "--deployment_description=`"Engine commit: $($env:ENGINE_COMMIT_HASH)`"" `
            )

            if ($launch_deployment_process.ExitCode -ne 0) {
                Write-Output "Failed to launch a Spatial cloud deployment. Error: $($launch_deployment_process.ExitCode)"
                Throw "Deployment launch failed"
            }

        } else {
            Write-Output "Deployment will not be launched as you have passed in an argument specifying that it should not be (START_DEPLOYMENT=${launch_deployment}). Remove it to have your build launch a deployment."
        }
    Finish-Event "launch-deployment" $deploy_parent_event_name

    Start-Event "add-dev-login-tag" $deploy_parent_event_name
        $add_dev_login_tag = Start-Process -Wait -PassThru -NoNewWindow -FilePath "spatial" -ArgumentList @(`
            "project", `
            "deployment", `
            "tags", `
            "add", `
            "--project_name=$project_name", `
            "$deployment_name", `
            "dev_login"
        )
        if ($add_dev_login_tag.ExitCode -ne 0) {
            Write-Output "Failed to add dev_login tag to the deployment. Error: $($add_dev_login_tag.ExitCode)"
            Throw "Failed to add dev_login"
        }
    Finish-Event "add-dev-login-tag" $deploy_parent_event_name
popd
Finish-Event "deploy-game" $parent_event_name
