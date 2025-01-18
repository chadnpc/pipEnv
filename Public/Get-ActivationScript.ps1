function Get-ActivationScript {
  [CmdletBinding()][OutputType([string])]
  param (
    [Parameter(Mandatory = $false)]
    [string]$Path = (Resolve-Path .).Path
  )

  process {
    return [venv]::GetActivationScript($Path)
  }
}