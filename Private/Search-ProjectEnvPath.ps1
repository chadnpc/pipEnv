function Search-ProjectEnvPath {
  # .SYNOPSIS
  #   Search Project's EnvPath
  # .DESCRIPTION
  #   Searches in the work home for a project with the same name as the project's directory.
  # .LINK
  #   https://github.com/alainQtec/pipEnv/blob/main/Private/Search-ProjectEnvPath.ps1
  [CmdletBinding()]
  param (
    [Parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $true)]
    [string]$ProjectPath = [IO.Directory]::Exists([venv]::data.ProjectPath) ? [venv]::data.ProjectPath : (Resolve-Path .).Path
  )

  begin {
    $reslt = $null; $_env_paths = [venv]::Get_work_Home() | Get-ChildItem -Directory -ea Ignore
  }

  process {
    if ($null -ne $_env_paths) {
      $reslt = $_env_paths.Where({ [IO.File]::ReadAllLines([IO.Path]::Combine($_.FullName, ".project"))[0] -eq $ProjectPath })
      $reslt = ($reslt.count -eq 0) ? $null : $reslt[0]
    }
  }

  end {
    return $reslt
  }
}