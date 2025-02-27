#!/usr/bin/env pwsh
using namespace System.IO
using namespace System.Collections.Generic
using namespace System.Management.Automation

#Requires -RunAsAdministrator
#Requires -Modules clihelper.env, cliHelper.core
#Requires -Psedition Core

#region    Classes
enum EnvState {
  Inactive
  Active
}

enum PackageManager {
  pip
  poetry
}

enum EnvManagerName {
  pipEnv
}

class EnvironmentNotFoundException : Exception {
  EnvironmentNotFoundException([string]$Message) : base($Message) {}
}

class EnvManager {
  static [Dictionary[string, string]]$Environments = @{}
  static [PsRecord]$data = @{ # Cached data
    SharePipcache = $False
    ProjectPath   = (Resolve-Path .).Path
    Session       = $null
    Manager       = [EnvManagerName]::pipEnv
    Home          = [EnvManager]::Get_work_Home()
    Os            = Get-HostOs
  }

  static [string] Get_work_Home() {
    $xdgDataHome = [Environment]::GetEnvironmentVariable("XDG_DATA_HOME", [EnvironmentVariableTarget]::User) # For Unix-like systems
    $whm = $xdgDataHome ? ([IO.Path]::Join($xdgDataHome, "virtualenvs")) : ([IO.Path]::Combine([Environment]::GetFolderPath("UserProfile"), ".local", "share", "virtualenvs"))
    $exp = [IO.Path]::Combine([Environment]::ExpandEnvironmentVariables($whm), "")
    $exp = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($exp))
    if (![IO.Directory]::Exists($exp)) {
      try {
        New-Item -Path $exp -ItemType Directory -Force | Out-Null
      } catch {
        throw "Failed to create directory '$exp': $_"
      }
    }
    return $exp
  }
  static [void] LoadEnvironments() {
    # Example: Load environments from a JSON file (you can customize this)
    $envFilePath = Join-Path $env:USERPROFILE ".python_environments.json"
    if (Test-Path $envFilePath) {
      [EnvManager]::Environments = Get-Content $envFilePath | ConvertFrom-Json -AsHashtable
    } else {
      [EnvManager]::Environments = @{}
    }
  }
  static [void] SaveEnvironments() {
    $envFilePath = Join-Path $env:USERPROFILE ".python_environments.json"
    [EnvManager]::Environments | ConvertTo-Json | Set-Content $envFilePath
  }
  static [bool] InstallPackage([string]$Environment, [string]$Package, [string]$Version) {
    try {
      if (![EnvManager]::Environments.ContainsKey($Environment)) {
        throw "Environment '$Environment' does not exist."
      }

      $pipPath = [EnvManager]::GetPipPath($Environment)
      if (!$pipPath) {
        throw "Could not find pip for environment '$Environment'."
      }

      $packageSpec = if ($Version) { "$Package==$Version" } else { $Package }
      & $pipPath install $packageSpec
      return $true
    } catch {
      Write-Console "[✖] " -f Red -NoNewLine ; Write-Console "Failed to install package. $_" -f LightCoral
      return $false
    }
  }
  static [string] FindEnvFile() {
    return [EnvManager]::FindEnvFile((Resolve-Path .).Path)
  }
  static [string] FindEnvFile([string]$folderPath) {
    $envFilePriority = @(".env.local", ".env", ".env.development", ".env.production", ".env.test")
    $files = Get-ChildItem -File -Path $folderPath -Force
    foreach ($envFile in $envFilePriority) {
      $foundFile = $files.Where({ $_.Name -eq $envFile }) | Select-Object -First 1
      if ($foundFile) {
        return $foundFile.FullName
      }
    }
    return [IO.Path]::Combine($folderPath, ".env")
  }
  static [bool] UpdatePackage([string]$Environment, [string]$Package, [string]$Version) {
    try {
      if (![EnvManager]::Environments.ContainsKey($Environment)) {
        throw [InvalidOperationException]::new("Environment '$Environment' does not exist!")
      }

      $pipPath = [EnvManager]::GetPipPath($Environment)
      if (!$pipPath) {
        throw "Could not find pip for environment '$Environment'."
      }

      $packageSpec = if ($Version) { "$Package==$Version" } else { $Package }
      & $pipPath install --upgrade $packageSpec
      return $true
    } catch {
      Write-Console "[✖] " -f Red -NoNewLine ; Write-Console "Failed to update package. $_" -f LightCoral
      return $false
    }
  }
  static [List[Hashtable]] ListPackages([string]$Environment) {
    try {
      if (![EnvManager]::Environments.ContainsKey($Environment)) {
        throw [InvalidOperationException]::new("Environment '$Environment' does not exist!")
      }

      $pipPath = [EnvManager]::GetPipPath($Environment)
      if (!$pipPath) {
        throw "Could not find pip for environment '$Environment'."
      }

      $packages = & $pipPath list --format=json
      return $packages | ConvertFrom-Json | ForEach-Object { @{
          Name    = $_.name
          Version = $_.version
        } }
    } catch {
      Write-Console "[✖] " -f Red -NoNewLine ; Write-Console "Failed to list packages. $_" -f LightCoral
      return [List[Hashtable]]::new()
    }
  }
  static [List[string]] ListEnvironments() {
    return [List[string]][EnvManager]::Environments.Keys
  }
  static [string] GetPipPath([string]$Environment) {
    $envPath = [EnvManager]::Environments[$Environment]
    if (!$envPath) {
      return $null
    }
    if ((xcrypt Get_Host_Os) -eq "Windows") {
      return [IO.Path]::Combine($envPath, "Scripts", "pip.exe")
    } else {
      return [IO.Path]::Combine($envPath, "bin", "pip")
    }
  }
  static [bool] AddEnvironment([string]$Name, [string]$Path) {
    if ([EnvManager]::Environments.ContainsKey($Name)) {
      Write-Console "Environment '$Name' already exists." -f LightCoral
      return $false
    }
    [EnvManager]::Environments[$Name] = $Path
    [EnvManager]::SaveEnvironments()
    return $true
  }
  static [bool] RemoveEnvironment([string]$Name) {
    if (![EnvManager]::Environments.ContainsKey($Name)) {
      Write-Console "Environment '$Name' does not exist." -f LightCoral
      return $false
    }
    [EnvManager]::Environments.Remove($Name)
    [EnvManager]::SaveEnvironments()
    return $true
  }
}

# .SYNOPSIS
#   python virtual environment manager
class venv : EnvManager, IDisposable {
  [string]$Path
  [string]$CreatedAt
  [version]$PythonVersion
  [PackageManager]$PackageManager
  static [validateNotNullOrEmpty()][InstallRequirements]$req = @{ list = @() }
  hidden [bool] $__Isdisposed
  hidden [string]$__name
  venv() {
    [void][venv]::From([IO.DirectoryInfo]::new([venv]::data.ProjectPath), [ref]$this)
  }
  venv([string]$dir) {
    [void][venv]::From([IO.DirectoryInfo]::new($dir), [ref]$this)
  }
  venv([IO.DirectoryInfo]$dir) {
    [void][venv]::From($dir, [ref]$this)
  }
  static [venv] Create() {
    return [venv]::Create([IO.DirectoryInfo]::new([venv]::data.ProjectPath))
  }
  static [venv] Create([string]$dir) {
    return [venv]::Create([IO.DirectoryInfo]::new($dir))
  }
  static [venv] Create([IO.DirectoryInfo]$dir) {
    # .INPUTS
    #  DirectoryInfo: It can be ProjectPath or the exact path for the venv.
    if (!$dir.Exists) { throw [Argumentexception]::new("Please provide a valid path!", [DirectoryNotFoundException]::new("Directory not found: $dir")) }
    $p = $dir.FullName; $e = $null; $v = (Get-Variable 'VerbosePreference' -ValueOnly) -eq 'Continue'
    try {
      if (![venv]::IsValid($dir.FullName)) {
        $_env_paths = $dir.EnumerateDirectories("*", [SearchOption]::TopDirectoryOnly).Where({ [venv]::IsValid($_.FullName) })
        if ($_env_paths.count -eq 0) { throw [EnvironmentNotFoundException]::new("No environment directory found for in $dir") }
        if ($_env_paths.count -gt 1) { throw [EnvironmentNotFoundException]::new("Multiple environment directories found in $dir") }
        $p = $_env_paths[0].FullName
      }
    } catch [EnvironmentNotFoundException] {
      $v ? $(Write-Debug "[venv] Try using already created env in: $([venv]::data.Home | Invoke-PathShortener) ... ") : $null
      $p = [venv]::get_project_envpath($dir.FullName)
    } catch {
      throw $_
    } finally {
      $e = $p ? [venv]::new($p) : $null
    }
    if ($e.IsValid) { return $e }
    # Create new virtual environment named $dir.BaseName and save in work_home [venv]::data.Home
    $_root_path = (Resolve-Path .).Path
    Set-Location $dir.FullName
    $v ? $(Write-Console "[venv] " -f SlateBlue -NoNewLine; Write-Console "Creating new env for '$($dir.FullName | Invoke-PathShortener)' ... "-f LemonChiffon -NoNewLine) : $null
    $usrEnvfile = [IO.FileInfo]::new([venv]::FindEnvFile());
    $wasNotHere = !$usrEnvfile.Exists
    $name = ($dir.BaseName -as [version] -is [version]) ? ("{0}_{1}" -f $dir.Parent.BaseName, $dir.BaseName) : $dir.BaseName
    # https://pipenv.pypa.io/en/latest/virtualenv.html#virtual-environment-name
    if (![string]::IsNullOrWhiteSpace($name)) {
      Edit-EnvCfg -Path $usrEnvfile.FullName -Pair ([KeyValuePair[string, string]]::new("PIPENV_CUSTOM_VENV_NAME", $name))
    }
    Invoke-PipEnv "install", "check"
    Set-Location $_root_path; if ($wasNotHere) { $usrEnvfile.FullName | Remove-Item -Force -ea Ignore }
    $v ? $(Write-Console "Done" -f Green) : $null
    # Search path of newly created venv
    $p = [venv]::get_project_envpath($dir.FullName)
    if (![IO.Directory]::Exists("$p")) { throw [InvalidOperationException]::new("Failed to create a venv Object", [DirectoryNotFoundException]::new("Directory '$p' not found")) }
    return [venv]::new($p)
  }
  static hidden [venv] From([IO.DirectoryInfo]$dir, [ref]$o) {
    # .SYNOPSIS
    #  Loads the venv object from directory info
    # .DESCRIPTION
    #  Does not create a new venv, meaning it can create a valid venv object from a directory
    #  Only if that directory is a valid env directory.
    [venv]::data.set('Session', $([ref]$o.Value).Value)
    [IO.Directory]::Exists($dir.FullName) ? ($dir | Set-ItemProperty -Name Attributes -Value ([IO.FileAttributes]::Hidden)) : $null
    [venv].PsObject.Properties.Add([PsScriptproperty]::new('CONSTANTS', { return [scriptblock]::Create("@{
            # Add your constant primitives here:
            validversionregex = '^(0|[1-9]\d*)(\.(0|[1-9]\d*)){0,3}$'
          }").InvokeReturnAsIs()
        }, { throw [SetValueException]::new("CONSTANTS is read-only") }
      )
    )
    if (![venv]::IsValid($dir.FullName)) { [InvalidOperationException]::new("$dir is not a valid venv folder") | Write-Console -f LightCoral }
    $o.Value.PsObject.Properties.Add([Psscriptproperty]::new('Name', {
          $v = [venv]::IsValid($this.Path)
          $has_deact_command = $null -ne (Get-Command deactivate -ea Ignore);
          $this.PsObject.Properties.Add([Psscriptproperty]::new('State', [scriptblock]::Create("return [EnvState][int]$([int]$($has_deact_command -and $v))"), { throw [SetValueException]::new("State is read-only") }));
          $this.PsObject.Properties.Add([Psscriptproperty]::new('IsValid', [scriptblock]::Create("return [IO.Path]::Exists(`$this.Path) -and [bool]$([int]$v)"), { throw [SetValueException]::new("IsValid is read-only") }));
          return "({0}) {1}" -f [venv]::data.Manager, ($v ? $this.__name : '✖');
        }, { Param([string]$n) [string]::IsNullOrWhiteSpace("$($this.__name) ".Trim()) ? ($this.__name = $n) : $null }
      )
    )
    $o.Value.Name = $dir.Name;
    $o.Value.Path = $dir.FullName; #the exact path for the venv
    $o.Value.PsObject.Properties.Add([Psscriptproperty]::new('BinPath', { return [IO.Path]::Combine($this.Path, "bin") }, { throw [SetValueException]::new("BinPath is read-only") }))
    $o.Value.CreatedAt = [Datetime]::Now.ToString();
    [venv]::data.PsObject.Properties.Add([PsScriptproperty]::new('PythonVersions', { return [venv]::get_python_versions() }, { throw [SetValueException]::new("PythonVersions is read-only") }))
    [venv]::data.PsObject.Properties.Add([PsScriptproperty]::new('SelectedVersion', { return [version]$(python --version).Split(" ").Where({ $_ -match [venv].CONSTANTS.validversionregex })[0] }, { throw [SetValueException]::new("SelectedVersion is read-only") }))
    # $p = python -c "import pipenv; print(pipenv.__file__)"; ie: (Get-Command pipenv -Type Application -ea Ignore).Source
    [venv]::data.set('RequirementsFile', "requirements.txt")
    ![venv]::req ? ([venv]::req = [InstallRequirements][requirement]("pipenv", "Python virtualenv management tool", { Install-PipEnv } )) : $null
    ![venv]::req.resolved ? [venv]::req.Resolve() : $null
    $o.Value.PythonVersion = [venv]::data.selectedversion;
    if (![string]::IsNullOrWhiteSpace($dir.Name) -and $o.Value.IsValid) {
      $venvconfig = Read-Env -File ([IO.Path]::Combine($o.Value.Path, 'pyvenv.cfg'));
      $c = @{}; $venvconfig.Name.ForEach({ $n = $_; $c[$n] = $venvconfig.Where({ $_.Name -eq $n }).value });
      [venv]::data.Set($c)
    }
    return $o.Value
  }
  static hidden [version[]] get_python_versions() {
    if ([venv]::has_pyenv()) { Install-PyEnv }
    $vstr = (pyenv versions).Split("`n").Trim(); $versions = @()
    if ($vstr.count -gt 1) {
      $versions = ($vstr | Select-Object @{l = "version"; e = { $l = $_; if ($l.StartsWith("*")) { $l = $l.Substring(1).TrimStart().Split(' ')[0] }; $m = $l -match [venv].CONSTANTS.validversionregex; $m ? $l : "not-a-version" } } | Where-Object { $_.version -ne "not-a-version" }).version
    } elseif ($vstr -like "*system (*") {
      $versions += (python --version).Split(" ")[1] -as [version]
    }
    return $versions
  }
  static [Object[]] SetLocalVersion() {
    return [venv]::SetLocalVersion([Path]::Combine([venv]::data.ProjectPath, ".python-version"))
  }
  static [Object[]] SetLocalVersion([string]$str = "versionfile_or_version") {
    [ValidateNotNullOrWhiteSpace()][string]$str = $str; $res = $null;
    $ver = switch ($true) {
      ([IO.File]::Exists($str)) {
        $ver_in_file = Get-Content $str; $localver = pyenv local
        ($localver -ne $ver_in_file) ? $ver_in_file : $null
        break
      }
      ($str -as [version] -is [version]) { $str; break }
      Default { $null }
    }
    if ($null -ne $ver) {
      $sc = [scriptblock]::Create("pyenv install $ver")
      Write-Console "[Python v$ver] " -f SlateBlue -NoNewLine;
      $res = [progressUtil]::WaitJob("Installing", (Start-Job -Name "Install python $ver" -ScriptBlock $sc));
    }
    return $res
  }
  [string] GetActivationScript() {
    return $this.GetActivationScript($this.Path)
  }
  [string] GetActivationScript([string]$ProjectPath) {
    $s = ([venv]::IsValid($ProjectPath) ? ([IO.Path]::Combine($ProjectPath, 'bin', 'activate.ps1')) : '')
    if (![IO.File]::Exists($s)) { throw [Exception]::new("Failed to get activation script", [FileNotFoundException]::new("file '$s' not found!")) }
    return $s
  }
  static [bool] IsValid([string]$dir) {
    $v = $true; $d = [IO.DirectoryInfo]::new($dir); ("bin", "lib").ForEach{
      $_d = $d.EnumerateDirectories($_); $v = $v -and (($_d.count -eq 1) ? $true : $false)
      if ($_ -eq 'bin') { $v = $v -and (($_d[0].EnumerateFiles("activate*").Count -gt 0) ? $true : $false) }
    }; $v = $v -and (($d.EnumerateFiles("pyvenv.cfg").Count -eq 1) ? $true : $false);
    return $v
  }
  [Object[]] Activate() {
    if ($this.__Isdisposed) { throw [InvalidOperationException]::new("Activation is not possible as Environment is already disposed") }
    return & ([venv]::data.Session.GetActivationScript())
  }
  [Object[]] Verify() { return Invoke-PipEnv "verify" }
  [Object[]] Upgrade() { pip install --user --upgrade pipenv; return Invoke-PipEnv "upgrade" }
  [Object[]] Sync() { return Invoke-PipEnv "sync" }
  [Object[]] Lock() { return Invoke-PipEnv "lock" }
  [Object[]] Install() { python -m pipenv install -q; return Invoke-PipEnv "install" }
  [Object[]] Install([string]$package) { python -m pipenv install -q $package; return Invoke-PipEnv "install" }
  [Object[]] Remove() { return python -m pipenv --rm }

  static [IO.DirectoryInfo] get_project_envpath() { return Search-ProjectEnvPath }
  static [IO.DirectoryInfo] get_project_envpath([string]$ProjectPath) { return Search-ProjectEnvPath $ProjectPath }

  [bool] Clone([string]$Source, [string]$Destination) {
    try {
      if (!$this.Environments.ContainsKey($Source)) {
        throw [InvalidOperationException]::new("Source environment '$Source' does not exist!")
      }
      $sourcePath = $this.Environments[$Source]
      $destinationPath = "$sourcePath\..\$Destination"
      Copy-Item -Path "$sourcePath" -Destination $destinationPath -Recurse
      $this.Environments[$Destination] = $destinationPath
      $this.Save()
      return $true
    } catch {
      Write-Console "[✖] " -f Red -NoNewLine ; Write-Console "Failed to clone environment. $_" -f LightCoral
      return $false
    }
  }
  [bool] Export([string]$Name, [string]$OutputFile) {
    try {
      if (!$this.Environments.ContainsKey($Name)) {
        throw "Environment '$Name' does not exist."
      }
      & "$($this.Environments[$Name])/$Name/Scripts/pip.exe" freeze > $OutputFile
      return $true
    } catch {
      Write-Console "[✖] " -f Red -NoNewLine ; Write-Console "Failed to export environment. $_" -f LightCoral
      return $false
    }
  }
  [bool] Import([string]$InputFile) {
    try {
      $packages = Get-Content $InputFile
      foreach ($package in $packages) {
        $this.InstallPackage($package, $null)
      }
      return $true
    } catch {
      Write-Console "[✖] " -f Red -NoNewLine ; Write-Console "Failed to import environment. $_" -f LightCoral
      return $false
    }
  }
  [bool] CheckCompatibility([string]$Package, [string]$Version) {
    try {
      $result = pip check "$Package==$Version"
      return ($result -eq "No broken dependencies")
    } catch {
      Write-Console "[✖] " -f Red -NoNewLine ; Write-Console "Failed to check compatibility: $_" -f LightCoral
      return $false
    }
  }
  [Hashtable] GetDetails([string]$Name) {
    try {
      if (!$this.Environments.ContainsKey($Name)) {
        throw "Environment '$Name' does not exist."
      }
      $details = @{
        Name     = $Name
        Path     = $this.Environments[$Name]
        Packages = $this.ListPackages($Name)
        Active   = ($this.Name -eq $Name)
      }
      return $details
    } catch {
      Write-Console "[✖] " -f Red -NoNewLine ; Write-Console "Failed to get details. $_" -f LightCoral
      return @{}
    }
  }
  static [bool] has_pyenv() {
    return [bool](Get-Command pyenv -type Application -ea Ignore)
  }
  [bool] SyncWithGlobal([List[string]]$Exclusions) {
    try {
      if ($null -eq $this.Name) {
        throw "No environment is currently active."
      }
      $globalPackages = pip list --format=json | ConvertFrom-Json | ForEach-Object { $_.name }
      foreach ($package in $globalPackages) {
        if (!($Exclusions -contains $package)) {
          $this.InstallPackage($package, $null)
        }
      }
      return $true
    } catch {
      Write-Console "[✖] " -f Red -NoNewLine ; Write-Console "Failed to sync with global. $_" -f LightCoral
      return $false
    }
  }
  [EnvState] CheckStatus([string]$Name) {
    if (!$this.Environments.ContainsKey($Name)) { throw "Environment '$Name' does not exist." }
    $status = ''
    try {
      $status = switch ($true) {
        ($this.Name -eq $Name) { "active"; break }
        default {
          "inactive"
        }
      }
    } catch {
      throw "Failed to check status: $_"
    }
    return $status
  }
  [bool] Deactivate() {
    try {
      if ($null -eq $this.Name) {
        throw [System.InvalidOperationException]::new("No environment is currently active.")
      }
      if (!$this.__Isdisposed) {
        if ([bool](Get-Command deactivate -CommandType Function -ea Ignore)) {
          deactivate
        } else {
          & "$($this.BinPath)/deactivate.ps1"
        }
        $this.Name = $null
        return $true
      }
      Write-Console "[✖] " -f Red -NoNewLine; Write-Console "Environment is already disposed." -f LightCoral
    } catch {
      Write-Console "[✖] " -f Red -NoNewLine; Write-Console "Failed to deactivate environment. $_" -f LightCoral
    }
    return $false
  }
  [void] Save() {
    # Save environments to a configuration file or registry
    # This is a placeholder for actual implementation
    # For example, writing to a JSON file
    # $config = @{ Environments = $this.Environments }
    # $config | ConvertTo-Json | Set-Content -Path "EnvManagerConfig.json"
  }
  [string] ToString() {
    return $this.Name
  }
  [void] Delete() {
    $this.Path | Remove-Item -Force -Recurse -Verbose:$false -ea Ignore
  }
  [void] Dispose() {
    if (!$this.__Isdisposed) {
      $this.Deactivate()
      $this.Delete()
      $this.__Isdisposed = $true
    }
  }
}

#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
  [EnvManagerName],
  [EnvState],
  [venv]
)
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
foreach ($Type in $typestoExport) {
  if ($Type.FullName -in $TypeAcceleratorsClass::Get.Keys) {
    $Message = @(
      "Unable to register type accelerator '$($Type.FullName)'"
      'Accelerator already exists.'
    ) -join ' - '

    [System.Management.Automation.ErrorRecord]::new(
      [System.InvalidOperationException]::new($Message),
      'TypeAcceleratorAlreadyExists',
      [System.Management.Automation.ErrorCategory]::InvalidOperation,
      $Type.FullName
    ) | Write-Warning
  }
}
# Add type accelerators for every exportable type.
foreach ($Type in $typestoExport) {
  $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
  foreach ($Type in $typestoExport) {
    $TypeAcceleratorsClass::Remove($Type.FullName)
  }
}.GetNewClosure();

$scripts = @();
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Public

foreach ($file in $scripts) {
  Try {
    if ([string]::IsNullOrWhiteSpace($file.fullname)) { continue }
    . "$($file.fullname)"
  } Catch {
    Write-Warning "Failed to import function $($file.BaseName): $_"
    $host.UI.WriteErrorLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
  Verbose  = $false
}
Export-ModuleMember @Param
