#Requires -PSEdition Desktop

function New-JobWrapper {
<#
.SYNOPSIS
Creates and starts a background job with an embedded stopwatch, automatic timeout, and automatic transcript logging.

.DESCRIPTION
Wraps the standard Start-Job cmdlet by attaching a diagnostic stopwatch and an asynchronous self-destruct timer. By default, it safely wraps the provided script block in a Start-Transcript block, saving the output to the Temp folder. If the job runs longer than the specified timeout, it is automatically stopped in the background. Returns a custom object containing the job, timer, and runtime parameters.

.EXAMPLE
$myJob = New-JobWrapper -Name "Task1" -ScriptBlock { Start-Sleep -Seconds 10 } -TimeoutSeconds 15

.EXAMPLE
$mySilentJob = New-JobWrapper -Name "Task2" -ScriptBlock { Write-Host "No logs here" } -TimeoutSeconds 15 -NoTranscript
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Identifying name of job")]
        [Alias("name")]
        [string]$JobName,
        [Parameter(Mandatory = $true, HelpMessage = "Scriptblock to be invoked")]
        [Alias("script")]
        [scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $true, HelpMessage = "Max seconds before job is treated as failed")]
        [Alias("timeout")]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory = $false, HelpMessage = "List of arguments to provide to scriptblock")]
        [System.Collections.Generic.List[object]]$ArgumentList,
        [Parameter(Mandatory = $false, HelpMessage = "Credentials to run script block as")]
        [pscredential]$Credential,
        [Parameter(Mandatory = $false, HelpMessage = "Working directory of job")]
        [string]$WorkingDir,
        [Parameter(Mandatory = $false, HelpMessage = "Pre-script block to run")]
        [scriptblock]$InitializationScript,
        
        [Parameter(Mandatory = $false, HelpMessage = "Disable automatic transcript logging to the Temp folder")]
        [switch]$NoTranscript
    )

    # ---------------------------------------------------------
    # Logging Script Block
    # ---------------------------------------------------------
    if (-not $NoTranscript) {
        $transcriptFolder = Join-Path $env:Temp "Transcripts\$(Get-date -f yyyyMMddTHHmm)"
        if (-not $(Test-Path $transcriptFolder)){ $null = New-Item -Path $transcriptFolder -ItemType Directory -Force -Confirm:$false}

        $OriginalScriptText = $ScriptBlock.ToString()
        $SafeName = $JobName -replace '[^a-zA-Z0-9_-]', '' 
        
        $WrappedScriptText = @"
            `$LogPath = Join-Path '$transcriptFolder' 'JobTranscript-$SafeName.txt'
            Start-Transcript -Path `$LogPath -Force | Out-Null
            try {
                # The & operator executes the inner block, and @args passes all parameters down safely
                & {
                    $OriginalScriptText
                } @args 
            }
            finally {
                Stop-Transcript | Out-Null
            }
"@
        $ScriptBlock = [scriptblock]::Create($WrappedScriptText)
    }
    # ---------------------------------------------------------

    $JobDetails = @{
        Name        = $JobName
        ScriptBlock = $ScriptBlock
    }
    
    if ($ArgumentList) { $JobDetails["ArgumentList"] = $ArgumentList }
    if ($Credential) { $JobDetails["Credential"] = $Credential }
    if ($WorkingDir) { $JobDetails["WorkingDirectory"] = $WorkingDir } 
    if ($InitializationScript) { $JobDetails["InitializationScript"] = $InitializationScript }

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $job = Start-Job @JobDetails

    # ---------------------------------------------------------
    # Self destruct
    # ---------------------------------------------------------
    $Timer = [System.Timers.Timer]::new($TimeoutSeconds * 1000)
    $Timer.AutoReset =$false
    
    # Register a background event that fires when the timer elapses
    Register-ObjectEvent -InputObject $Timer -EventName Elapsed -MessageData $job -Action {
        $TrackedJob = $Event.MessageData
        
        if ($TrackedJob.State -eq 'Running') { $TrackedJob | Stop-Job }
        $sender.Dispose()
        Unregister-Event -SourceIdentifier $EventSubscriber.SourceIdentifier -Force
    } | Out-Null
    
    $Timer.Start()
    # ---------------------------------------------------------

    $out = [ordered]@{
        Timer     = $watch
        Job       = $job
        JobParams = @{} 
    }

    # Record job params
    foreach ($key in $PSBoundParameters.Keys) {
        $out["JobParams"][$key] = $PSBoundParameters[$key]
    }

    return [pscustomobject]$out 
}
function Watch-JobWrapper {
    <#
.SYNOPSIS
Displays a live, interactive console dashboard for tracked jobs.

.DESCRIPTION
Takes an array of custom job objects created by New-JobWrapper and displays a live-updating UI in the console. It tracks running status, automatically stops internal timers when jobs finish, color-codes the output, and enforces the failsafe timeout visually.

.EXAMPLE
Watch-JobWrapper -Jobs @($job1, $job2)
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Input job wrappers")]
        [array]$Jobs 
    )
    $Width = try { $Host.UI.RawUI.WindowSize.Width } catch { 60 }

    $nameWidth = 10
    $maxWidth = [math]::Floor($Width / 2)
    foreach ($item in $Jobs) {
        if ($item.Job.Name.Length -gt $nameWidth) { $nameWidth = $item.Job.Name.Length }
    }
    if ($nameWidth -gt $maxWidth) { $nameWidth = $maxWidth }

    $allComplete = $false

    while (-not $allComplete) {
        Clear-Host
        Write-Host "=== Job Dashboard ".PadRight($Width, "=") -ForegroundColor Cyan
        
        $runningCount = 0

        foreach ($item in $Jobs) {
            # Normalize name
            $jName = $item.Job.Name
            if ($jName.Length -gt $nameWidth) {
                $jName = $jName.Substring(0, $nameWidth - 3) + "..."
            }
            $paddedName = $jName.PadRight($nameWidth + 2)

            $state = $item.Job.State
            if ($state -eq 'Running') { 
                $runningCount++ 
                $Colour = 'White'
            }
            else {
                $item.Timer.Stop() 
                $Colour = switch ($state) {
                    'Completed' { 'Green' }
                    'Failed' { 'Red' }
                    'Stopped' { 'Red' }
                    Default { 'White' }
                }
            }

            $elapsed = [math]::Round($item.Timer.Elapsed.TotalSeconds, 1)
            $timeout = $item.JobParams.TimeoutSeconds

            # Failsafe timeout catch
            if ($elapsed -gt $timeout) {
                $item.Job | Stop-Job -Confirm:$false -ErrorAction SilentlyContinue
                $elapsed = $timeout
                
                $state = 'Stopped' 
                $Colour = 'Red'
            }

            # Write out
            Write-Host "$paddedName | $($state.ToString().PadRight(12)) | $($(${elapsed}).ToString().Padright(5))s / ${timeout}s" -ForegroundColor $Colour
        }

        Write-Host "".PadRight($Width, "=") -ForegroundColor Cyan

        if ($runningCount -eq 0) {
            $allComplete = $true
        }
        else {
            Start-Sleep -Milliseconds 500
        }
    }
}

function Stop-JobWrapper {
    <#
.SYNOPSIS
Stops and removes specified job wrappers or all jobs in the session.

.DESCRIPTION
A cleanup utility that accepts specific custom job objects or an -All switch to forcefully stop and remove background jobs. It safely suppresses errors for jobs that are already locked or deleted.

.EXAMPLE
Stop-JobWrapper -Jobs @($job1, $job2)
.EXAMPLE
Stop-JobWrapper -All
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Input job wrappers", ParameterSetName = 'Provided')]
        [array]$Jobs,
        [Parameter(Mandatory = $true, HelpMessage = "All running jobs", ParameterSetName = 'All')]
        [switch]$All
    )
    switch ($PsCmdlet.ParameterSetName) {
        Provided {
            foreach ($item in $Jobs) {
                $item.Job | Stop-Job -ErrorAction SilentlyContinue
                $item.Job | Remove-Job -Force -ErrorAction SilentlyContinue
                Write-Host "Job: $($item.Job.Name) stopped and removed" -ForegroundColor Yellow
            } 
        }
        All { 
            Get-Job | Stop-Job -ErrorAction SilentlyContinue
            Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
            Write-Host "All jobs stopped and removed" -ForegroundColor Yellow
        }
    }
}

function Wait-JobWrapper {
    <#
.SYNOPSIS
Silently blocks the script until all specified tracked jobs complete.

.DESCRIPTION
Monitors an array of custom job objects without generating any console output. It enforces job timeouts in the background and precisely freezes each job's stopwatch upon completion, allowing you to accurately read their elapsed times later.

.EXAMPLE
Wait-JobWrapper -Jobs @($job1, $job2)
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Input job wrappers")]
        [array]$Jobs 
    )

    $allComplete = $false

    while (-not $allComplete) {
        $runningCount = 0

        foreach ($item in $Jobs) {
            if ($item.Job.State -eq 'Running') {
                
                $elapsed = $item.Timer.Elapsed.TotalSeconds
                $timeout = $item.JobParams.TimeoutSeconds

                # Failsafe timeout catch
                if ($elapsed -gt $timeout) {
                    $item.Job | Stop-Job -Confirm:$false -ErrorAction SilentlyContinue
                }
                else {
                    $runningCount++ 
                }
            }
            else {
                # Freeze the stopwatch so you can accurately read it later
                if ($item.Timer.IsRunning) {
                    $item.Timer.Stop()
                }
            }
        }

        if ($runningCount -gt 0) {
            Start-Sleep -Milliseconds 500
        }
        else {
            $allComplete = $true
        }
    }
}

function Receive-JobWrapper {
    <#
    .SYNOPSIS
    Waits for tracked jobs to complete and returns their output as a hashtable.

    .DESCRIPTION
    Takes an array of custom job objects. If any jobs are still running, it automatically calls Wait-JobWrapper to block until completion. It then retrieves the output from each job, formats it into an ordered dictionary keyed by the job's name, and optionally deletes the jobs from memory.

    .EXAMPLE
    $results = Receive-JobWrapper -Jobs @($job1, $job2) -CleanUp
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Input job wrappers")]
        [array]$Jobs,
        
        [Parameter(Mandatory = $false, HelpMessage = "Remove the jobs from memory after receiving results")]
        [switch]$CleanUp
    )

    if ($Jobs.Job.State -contains 'Running') {
        Wait-JobWrapper -Jobs $Jobs
    }

    # Collect results into an ordered dictionary
    $Results = [ordered]@{ }

    foreach ($item in $Jobs) {
        $name = $item.Job.Name
        
        # Handle duplicate job names by appending the underlying Job ID
        if ($Results.Contains($name)) {
            $name = "$name ($($item.Job.Id))"
        }

        $state = $item.Job.State

        if ($state -eq 'Completed') {
            $Results[$name] = $item.Job | Receive-Job -ErrorAction SilentlyContinue
        }
        elseif ($state -eq 'Stopped') {
            $Results[$name] = "[Stopped / Timed Out]"
        }
        else {
            # Capture error streams for failed jobs (2>&1 merges errors to success stream)
            $errorMsg = $item.Job | Receive-Job -ErrorAction SilentlyContinue 2>&1
            if ($errorMsg) {
                $Results[$name] = "[Failed] $errorMsg"
            } else {
                $Results[$name] = "[$state]"
            }
        }

        if ($CleanUp) {
            $item.Job | Remove-Job -Force -ErrorAction SilentlyContinue
        }
    }

    return $Results
}