﻿function New-venv {
  # .DESCRIPTION
  #   create a new virtual environment
  # .LINK
  #   https://github.com/chadnpc/pipEnv/blob/main/Public/New-venv.ps1
  # .EXAMPLE
  #   New-venv
  #   Create a new virtual environment in the current directory
  # .EXAMPLE
  #   New-venv | Activate-Env
  #   same as (New-venv).Activate()
  # .EXAMPLE
  #   $e = New-venv . myEnvName
  #   $e.Activate()
  [CmdletBinding(supportsShouldProcess = $true)]
  [OutputType([Venv])]
  param (
    # Project root path
    [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
    [ValidateScript({
        if (![string]::IsNullOrWhiteSpace($_)) {
          return $true
        } else {
          throw [System.ArgumentException]::new("Please provide a valid (NullOrWhiteSpace) directory name.", 'Path')
        }
      }
    )][Alias('p')]
    [string]$Path = '.'
  )
  begin {
    $Path = (Resolve-Path ($Path | xcrypt GetUnResolvedPath) -ea Ignore).Path
    $Path = [IO.Directory]::Exists($Path) ? $Path : $(throw [System.IO.DirectoryNotFoundException]::new("Directory not found: $Path"))
    $Name = Split-Path $Path -Leaf; $v = $null
  }
  process {
    if ($PSCmdlet.ShouldProcess($Path, "Create virtual environment for $Name")) {
      $v = [venv]::Create($Path)
    }
  }

  end {
    return $v
  }
}