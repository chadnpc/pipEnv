function Edit-EnvCfg {
  # .SYNOPSIS
  #   Edit a key in a pyvenv.cfg file
  # .DESCRIPTION
  #   Edit a key in a pyvenv.cfg file
  # .PARAMETER Path
  #   The path to the pyvenv.cfg file
  # .PARAMETER Key
  #   The key to edit
  # .PARAMETER Value
  #   The new value for the key
  # .EXAMPLE
  #  Edit-EnvCfg -Path ./.env -Key "PIPENV_CUSTOM_VENV_NAME" -Value "pipenvtools"
  #  Changes the value
  # .EXAMPLE
  #  Edit-EnvCfg -Path "pyvenv.cfg" -Key "NEW_KEY" -Value "new-value"
  #  Adds a new key
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$Path = "pyvenv.cfg",

    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$Key,

    [Parameter(Mandatory = $true, Position = 2)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$Value
  )

  process {
    $_cp = [IO.FileInfo]::new(($Path | xcrypt GetUnResolvedPath))
    if ($_cp.Exists) {
      $content = Get-Content -Path $_cp.FullName
      $regex = "(?m)^($Key\s*=\s*)(.*)$"
      $replaced = $false

      for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match $regex) {
          $content[$i] = $content[$i] -replace $regex, ('${1}' + $Value)
          $replaced = $true
        }
      }

      if (-not $replaced) {
        $content += "$Key = $Value"
      }
      Set-Content -Path $_cp.FullName -Value $content
    }
  }
}
