function Search-ProjectEnvPath {
  # .SYNOPSIS
  #   Search Project's EnvPath
  # .DESCRIPTION
  #   Searches in the work home for a project with the same name as the project's directory.
  # .LINK
  #   https://github.com/alainQtec/pipEnv/blob/main/Private/Search-ProjectEnvPath.ps1
  [CmdletBinding()][OutputType([System.IO.DirectoryInfo])]
  param (
    [Parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $true)]
    [string]$ProjectPath = (Resolve-Path .).Path
  )

  begin {
    $r = $null; $_env_paths = [venv]::Get_work_Home() | Get-ChildItem -Directory -ea Ignore
  }

  process {
    if ($null -ne $_env_paths) {
      $name = $ProjectPath | Split-Path -Leaf
      for ($c = 0; $null -eq $r -and $c -lt $_env_paths.count; $c++) {
        $e = (Read-Env ([IO.Path]::Combine($_env_paths[$c].FullName, "pyvenv.cfg"))).Where({ $_.Name -eq "Prompt" -and $_.Value -eq $name })
        $r = $e ? $_env_paths[$c] : $null
      }
    }
  }

  end {
    return $r
  }
}