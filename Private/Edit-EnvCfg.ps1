function Edit-EnvCfg {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $false)]
    [string]$Path = "pyvenv.cfg",

    [Parameter(Mandatory = $true)]
    [System.Collections.Generic.KeyValuePair[String, String]]$Pair

  )

  process {
    $_cp = [IO.FileInfo]::new(($Path | xcrypt GetUnResolvedPath))
    if ($_cp.Exists) {
      $cfg = Read-Env $_cp.FullName
      $cfg = $cfg | Select-Object @{ l = 'Name'; e = { $_.Name } }, @{ l = 'value'; e = { ($_.Name -eq $Pair.Key) ? $Pair.Value : $_.Value } }
      $str = ''; $cfg.ForEach({ $str += "{0} = {1}`n" -f $_.Name, $_.value });
      [void][IO.File]::WriteAllText($_cp.FullName, $str.TrimEnd())
    }
  }
}