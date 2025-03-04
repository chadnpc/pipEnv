function Dismount-venv {
  [CmdletBinding()][Alias('dispose-env', 'dispose-venv')]
  [OutputType([void])]
  param (
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

  process {
    [void](New-Object venv($Path)).Dispose()
  }
}