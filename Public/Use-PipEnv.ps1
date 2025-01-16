function Use-pipEnv {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [Venv]$env
  )

  begin {
  }

  process {
  }

  end {
    $env.Activate()
  }
}