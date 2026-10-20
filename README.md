# PSJobWrapper 

[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![PowerShell Core 7+](https://img.shields.io/badge/PowerShellCore-7%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A lightweight PowerShell module designed for managing, monitoring, and safely executing concurrent background jobs.

---

## Key Features

- **Asynchronous Self-Destruct Timers:** Attaches a `System.Timers.Timer` background event handler to every job. Non-responsive or hanging background tasks are killed cleanly before they drain system resources.
- **Live Terminal Dashboard (`Watch-JobWrapper`):** Provides a dynamic, auto-adjusting console dashboard to visually monitor parallel job progress, run states, and elapsed execution times in real time.
- **Automatic Transcript Logging:** Intercepts and logs all standard streams into session-timestamped transcript logs (`$env:Temp\Transcripts\...`) without altering user script block parameters.
- **Non-Blocking Orchestration:** Return immediate control to your main process using fire-and-forget job creation, silent waiting (`Wait-JobWrapper`), or structured output processing (`Receive-JobWrapper`).

---

## Architecture & Module Structure

```
                  ┌──────────────────────┐
                  │   New-JobWrapper     │ ──▶ Launches job + Self-Destruct Timer
                  └──────────┬───────────┘     + Auto Transcript Logging
                             │
            ┌────────────────┴────────────────┐
            ▼                                 ▼
┌──────────────────────┐          ┌──────────────────────┐
│  Watch-JobWrapper    │          │   Wait-JobWrapper    │
│  (Live Dashboard UI) │          │  (Silent Execution)  │
└──────────┬───────────┘          └──────────┬───────────┘
           │                                 │
           └────────────────┬────────────────┘
                            │
                            ▼
               ┌──────────────────────────┐
               │   Receive-JobWrapper     │ ──▶ Aggregates results into
               └────────────┬─────────────┘     Ordered Hashtable
                            │
                            ▼
               ┌──────────────────────────┐
               │    Stop-JobWrapper       │ ──▶ Memory Cleanup & Teardown
               └──────────────────────────┘
```

---

## Installation

### Manual Installation
Clone or download this repository into your PowerShell module directory:

```powershell
$ModulePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules\JobWrapper'
New-Item -ItemType Directory -Path $ModulePath -Force
Copy-Item -Path .\job-wrapper.psm1, .\job-wrapper.psd1 -Destination $ModulePath -Force

# Verify Module Import
Import-Module JobWrapper -Verbose
```

---

## Quick Start & Examples

### 1. Simple Parallel Execution with Live Dashboard

```powershell
Import-Module JobWrapper

# Define tasks with varying execution times
$scriptBlock = {
    param($TaskName, $Duration)
    Write-Host "Starting $TaskName."
    Start-Sleep -Seconds $Duration
    return "Result from $TaskName"
}

# 1. Spawn Jobs
$job1 = New-JobWrapper -Name "Quick Cleanup" -ScriptBlock $scriptBlock -TimeoutSeconds 10 -ArgumentList "Quick Cleanup", 3
$job2 = New-JobWrapper -Name "DISM Servicing" -ScriptBlock $scriptBlock -TimeoutSeconds 15 -ArgumentList "DISM Servicing", 8
$job3 = New-JobWrapper -Name "Hanging Process" -ScriptBlock $scriptBlock -TimeoutSeconds 5  -ArgumentList "Hanging Process", 20

# 2. Monitor execution
Watch-JobWrapper -Jobs $job1, $job2, $job3

# 3. Retrieve results into an ordered dictionary
$results = Receive-JobWrapper -Jobs $job1, $job2, $job3 -CleanUp
$results | Format-Table
```

---

### 2. Silent Wait & Result Harvesting

```powershell
# Spawn background tasks
$jobA = New-JobWrapper -Name "Inventory check" -ScriptBlock { Get-Service } -TimeoutSeconds 30
$jobB = New-JobWrapper -Name "Disk analysis"  -ScriptBlock { Get-CimInstance Win32_LogicalDisk } -TimeoutSeconds 30

# Block main process execution silently
Wait-JobWrapper -Jobs $jobA, $jobB

# Retrieve collected output hashtable
$data = Receive-JobWrapper -Jobs $jobA, $jobB -CleanUp
```
---

## License

Distributed under the **MIT License**. See `LICENSE` for details.
