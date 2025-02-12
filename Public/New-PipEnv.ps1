function New-pipEnv {
  # .DESCRIPTION
  #   create a new virtual environment
  # .LINK
  #   https://github.com/chadnpc/pipEnv/blob/main/Public/New-PipEnv.ps1
  # .EXAMPLE
  #   New-pipEnv .
  #   Create a new virtual environment in the current directory
  # .EXAMPLE
  #   New-PipEnv | Activate-Env
  #   same as (New-PipEnv).Activate()
  # .EXAMPLE
  #   $e = New-pipEnv . myEnvName
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
    $Path = (Resolve-Path $Path -ea Ignore).Path
    $Path = [IO.Directory]::Exists($Path) ? $Path : $(throw [System.IO.DirectoryNotFoundException]::new("Directory not found: $Path"))
    $Name = Split-Path $Path -Leaf; $v = $null
  }
  process {
    if ($PSCmdlet.ShouldProcess("Create virtual environment for $Name", $Path)) {
      $v = [Venv]::Create($Path)
    }
  }

  end {
    return $v
  }
}