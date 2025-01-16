function Use-pipEnv {
  [CmdletBinding()][Alias('activate')]
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