@{
    RootModule           = 'job-wrapper.psm1'
    ModuleVersion        = '1.0.0'
    CompatiblePSEditions = @('Desktop', 'Core')
    PowerShellVersion    = '5.1'
    GUID                 = '15f4216f-2e73-4552-bbc9-79a3015acf1a'
    Author               = 'Keiran'
    CompanyName          = 'Open Source'
    Copyright            = '(c) 2026 Keiran. Licensed under the MIT License.'
    LicenseUri           = 'https://opensource.org/licenses/MIT'
    Description          = 'An asynchronous background job wrapper with timeouts, structured output, and live console dashboards.'

    # --- EXPORTS ---
    FunctionsToExport    = @(
        'New-JobWrapper',
        'Watch-JobWrapper',
        'Stop-JobWrapper',
        'Wait-JobWrapper',
        'Receive-JobWrapper'
    )

    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}