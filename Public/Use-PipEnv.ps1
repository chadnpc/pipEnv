function Use-pipEnv {
  [CmdletBinding(DefaultParameterSetName = 'envdir')][Alias('activate')]
  param (
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ParameterSetName = 'envdir')]
    [validateScript({
        if (Test-Path -Path $_ -PathType Container -ea Ignore) {
          return $true
        } else {
          throw [System.ArgumentException]::new('envdir', "Path: $_ is not a valid directory.")
        }
      })]
    [string]$Path,

    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, parameterSetName = 'env')]
    [ValidateNotNullOrEmpty()]
    [Venv]$env
  )

  process {
    $e = ($PSCmdlet.ParameterSetName -eq 'env') ? $env : ([Venv]::Create($Path))
    if ($null -ne $e) { $e.Activate() }
  }
}