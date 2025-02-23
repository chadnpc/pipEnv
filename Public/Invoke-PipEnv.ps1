function Invoke-PipEnv {
  [CmdletBinding()]
  param (
    [Parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $true)]
    [Alias('c')][AllowNull()]
    [string[]]$commands
  )

  begin {
    $_rs = @(); if (!(Get-Command pipenv -ea Ignore)) { Install-Pipenv };
    $_ps = [venv]::get_pipenv_script()
    $_ch = @{
      shell = {
        $session = [venv]::data.Session
        if ($null -ne $session) {
          $session.Activate()
        } else {
          Write-Console "No active session found!" -f LightCoral
        }
      }
    }
  }

  process {
    if ($null -ne $commands) {
      foreach ($c in $commands) {
        if ($c -in $_ch.Keys) {
          $_rs += $_ch[$c].Invoke()
        } else {
          $_rs += python $_ps $c
        }
      }
    } else {
      $_rs += python $_ps
    }
  }

  end {
    return $_rs
  }
}