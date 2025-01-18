function New-pipEnv {
  # .DESCRIPTION
  #   create a new virtual environment
  # .LINK
  #   https://github.com/alainQtec/pipEnv/blob/main/Public/New-PipEnv.ps1
  # .EXAMPLE
  #   New-pipEnv .
  #   Create a new virtual environment in the current directory
  # .EXAMPLE
  #   New-pipEnv ~/path/to/project
  #   Create a new virtual environment in the ~/path/to/project directory
  [CmdletBinding(supportsShouldProcess = $true)]
  [OutputType([Venv])]
  param (
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$Path = '.'
  )
  begin {
    $Path = (Resolve-Path $Path -ea Ignore).Path
    $Path = [IO.Directory]::Exists($Path) ? $Path : $(throw [System.IO.DirectoryNotFoundException]::new("Directory not found: $Path"))
    $Name = Split-Path $Path -Leaf; $v = $null
  }
  process {
    if ($PSCmdlet.ShouldProcess("Create virtual environment for $Name", $Path)) {
      Push-Location $Path
      [void][venv]::Run(("install", "check"))
      Pop-Location
      $v = [Venv]::Create($Path)
    }
  }

  end {
    return $v
  }
}