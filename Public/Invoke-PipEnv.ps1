function Invoke-PipEnv {
  # .SYNOPSIS
  #  this function to call PipEnv
  # .DESCRIPTION
  #  this function behaves like an advanced shim / wrapper around PipEnv to do automations
  # .NOTES
  #  This function will auto install PyEnv
  [CmdletBinding()]
  param (
    [Parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $true, valueFromRemainingArguments = $true)]
    [Alias('c')][AllowNull()][string[]]$commands
  )

  begin {
    $result = @();
    $preset_command_actions = @{
      shell = {
        $session = [venv]::data.Session
        if ($null -ne $session) {
          $session.Activate()
        } else {
          Write-Console "[✖] " -f Red -NoNewLine ; Write-Console "No active session found!" -f LightCoral
        }
      }
    }
  }

  process {
    $py = [venv]::GetPythonExecutable()
    if ($null -ne $commands) {
      foreach ($c in $commands) {
        if ($c -in $preset_command_actions.Keys) {
          $result += $preset_command_actions[$c].Invoke()
        } else {
          $result += &$py -m pipenv $c
        }
      }
      return $result
    }
    [string]$line = (($commands | Out-String) + ' ').Trim()
    if (![string]::isNullOrEmpty($line)) {
      return &$py -m pipenv $commands
    }
    return &$py -m pipenv
  }
}