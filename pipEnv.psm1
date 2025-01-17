#!/usr/bin/env pwsh
using namespace System.IO
using namespace System.Collections.Generic
using namespace System.Management.Automation

#Requires -RunAsAdministrator
#Requires -Modules clihelper.env, cliHelper.core
#Requires -Psedition Core

#region    Classes
class InstallException : Exception {
  InstallException() {}
  InstallException([string]$message) : base($message) {}
  InstallException([string]$message, [Exception]$innerException) : base($message, $innerException) {}
}

class InstallFailedException : InstallException {
  InstallFailedException() {}
  InstallFailedException([string]$message) : base($message) {}
  InstallFailedException([string]$message, [Exception]$innerException) : base($message, $innerException) {}
}

class Requirement {
  [string] $Name
  [version] $Version
  [string] $Description
  [string] $InstallScript

  Requirement() {}
  Requirement([array]$arr) {
    $this.Name = $arr[0]
    $this.Version = $arr.Where({ $_ -is [version] })[0]
    $this.Description = $arr.Where({ $_ -is [string] -and $_ -ne $this.Name })[0]
    $__sc = $arr.Where({ $_ -is [scriptblock] })[0]
    $this.InstallScript = ($null -ne $__sc) ? $__sc.ToString() : $arr[-1]
  }
  Requirement([string]$Name, [scriptblock]$InstallScript) {
    $this.Name = $Name
    $this.InstallScript = $InstallScript.ToString()
  }
  Requirement([string]$Name, [string]$Description, [scriptblock]$InstallScript) {
    $this.Name = $Name
    $this.Description = $Description
    $this.InstallScript = $InstallScript.ToString()
  }

  [bool] IsInstalled() {
    try {
      Get-Command $this.Name -Type Application
      return $?
    } catch [CommandNotFoundException] {
      return $false
    } catch {
      throw [InstallException]::new("Failed to check if $($this.Name) is installed", $_.Exception)
    }
  }
  [bool] Resolve() {
    return $this.Resolve($false, $false)
  }
  [bool] Resolve([switch]$Force, [switch]$What_If) {
    $is_resolved = $true
    if (!$this.IsInstalled() -or $Force.IsPresent) {
      Write-Console "[Resolve requrement] $($this.Name) " -f Green -NoNewLine
      if ($this.Description) {
        Write-Console "($($this.Description)) " -f BlueViolet -NoNewLine
      }
      Write-Console "$($this.Version) " -f Green
      if ($What_If.IsPresent) {
        Write-Console "Would install: $($this.Name)" -f Yellow
      } else {
        [ScriptBlock]::Create("$($this.InstallScript)").Invoke()
      }
      $is_resolved = $?
    }
    return $is_resolved
  }
}

Class InstallRequirements {
  [Requirement[]] $list
  [bool] $resolved = $false
  [string] $jsonPath = [IO.Path]::Combine($(Resolve-Path .).Path, 'requirements.json')

  InstallRequirements() {}
  InstallRequirements([array]$list) { $this.list = $list }
  InstallRequirements([List[array]]$list) { $this.list = $list.ToArray() }
  InstallRequirements([hashtable]$Map) { $Map.Keys | ForEach-Object { $Map[$_] ? ($this.$_ = $Map[$_]) : $null } }

  [void] Resolve() {
    $this.Resolve($false, $false)
  }
  [void] Resolve([switch]$Force, [switch]$What_If) {
    $res = $true; $this.list.ForEach({ $res = $res -and $_.Resolve($Force, $What_If) })
    $this.resolved = $res
  }
  [void] Import() {
    $this.Import($this.JsonPath, $false)
  }
  [void] Import([switch]$throwOnFail) {
    $this.Import($this.JsonPath, $throwOnFail)
  }
  [void] Import([string]$JsonPath, [switch]$throwOnFail) {
    if ([IO.File]::Exists($JsonPath)) { $this.list = Get-Content $JsonPath | ConvertFrom-Json }; return
    if ($throwOnFail) {
      throw [FileNotFoundException]::new("Requirement json file not found: $JsonPath")
    }
  }
  [void] Export() {
    $this.Export($this.JsonPath)
  }
  [void] Export([string]$JsonPath) {
    $this.list | ConvertTo-Json -Depth 1 -Verbose:$false | Out-File $JsonPath
  }
  [string] ToString() {
    return $this | ConvertTo-Json
  }
}

# .SYNOPSIS
#   python virtual environment helper class
class Venv {
  [string]$Path
  [PsRecord]$Config = @{
    defaultName = "env"
  }
  hidden [string]$__name
  Venv() {}
  Venv([IO.DirectoryInfo]$dir) {
    $this.Path = $dir.FullName;
    [IO.Directory]::Exists($this.Path) ? ($dir | Set-ItemProperty -Name Attributes -Value ([IO.FileAttributes]::Hidden)) : $null
    $this.PsObject.Properties.Add([Psscriptproperty]::new('Name', {
          $v = [Venv]::IsValid($this.Path)
          $has_deact_command = $null -ne (Get-Command deactivate -ea Ignore);
          $this.PsObject.Properties.Add([Psscriptproperty]::new('IsValid', [scriptblock]::Create("return [bool]$([int]$v)"), { throw [SetValueException]::new("IsValid is read-only") }));
          $this.PsObject.Properties.Add([Psscriptproperty]::new('IsActive', [scriptblock]::Create("return [bool]$([int]$($has_deact_command -and $v))"), { throw [SetValueException]::new("IsActive is read-only") }));
          return ($v ? $this.__name : [string]::Empty);
        }, { Param([string]$n) [string]::IsNullOrWhiteSpace("$($this.__name) ".Trim()) ? ($this.__name = $n) : $null }
      )
    )
    $this.Name = $dir.Name;
    if (![string]::IsNullOrWhiteSpace($this.Name) -and $this.IsValid) {
      $venvconfig = Read-Env -File ([IO.Path]::Combine($this.Path, 'pyvenv.cfg'));
      $c = @{}; $venvconfig.Name.ForEach({ $n = $_; $c[$n] = $venvconfig.Where({ $_.Name -eq $n }).value });
      $this.Config.Set($c)
    }
  }
  static [Venv] Create() {
    return [Venv]::Create([IO.DirectoryInfo]::new((Resolve-Path .).Path))
  }
  static [Venv] Create([string]$dir) {
    return [Venv]::Create([IO.DirectoryInfo]::new((Resolve-Path $dir).Path))
  }
  static [Venv] Create([IO.DirectoryInfo]$dir) {
    return [Venv]::Create($dir.Name, $dir.Parent)
  }
  static [Venv] Create([string]$Name, [IO.DirectoryInfo]$dir) {
    $venvPath = [IO.Path]::Combine($dir.FullName, $Name)
    if (![IO.Directory]::Exists($venvPath)) { Write-Console "Create venv $Name" -f LimeGreen; python -m venv $Name }
    $verfile = [IO.Path]::Combine($dir.FullName, ".python-version")
    if ([IO.File]::Exists($verfile)) {
      $ver = Get-Content $verfile; $localver = pyenv local
      if ($localver -ne $ver) {
        $sc = [scriptblock]::Create("pyenv install $ver")
        Write-Console "[Python version $ver] " -f LimeGreen -NoNewLine; [progressUtil]::WaitJob("Installing", (Start-Job -Name "Install python $ver" -ScriptBlock $sc));
      }
    }
    return [venv]::new((Get-Item $venvPath -Force -EA Ignore))
  }
  static [bool] IsValid([string]$dir) {
    $v = $true; $d = [IO.DirectoryInfo]::new($dir); ("bin", "lib").ForEach{
      $_d = $d.EnumerateDirectories($_); $v = $v -and (($_d.count -eq 1) ? $true : $false)
      if ($_ -eq 'bin') { $v = $v -and (($_d[0].EnumerateFiles("activate*").Count -gt 0) ? $true : $false) }
    }; $v = $v -and (($d.EnumerateFiles("pyvenv.cfg").Count -eq 1) ? $true : $false);
    return $v
  }
  [void] Activate() {
    $spath = Resolve-Path ([IO.Path]::Combine($this.Path, 'bin', 'Activate.ps1')) -ea Ignore
    if (![IO.File]::Exists($spath)) { throw [FileNotFoundException]::new("Venv activation script not found: $spath") }
    &$spath
  }
  [void] Delete() {
    $this.Path | Remove-Item -Force -Recurse -Verbose:$false -ea Ignore
  }
}

# .LINK
# [pipenv](https://github.com/pypa/pipEnv) wrapper
class pipEnv {
  [venv]$ProjectEnv
  static [PsRecord]$data = [pipEnv].data #starts $null until any instance is created
  static [InstallRequirements]$req
  [string]$bin
  pipEnv() { $this.__init__() }
  static [pipEnv] Create() { return [pipEnv]::new() }

  [void] Install() {
    & ($this.bin) install -q
  }
  [void] Install([string]$package) {
    & ($this.bin) install -q $package
  }
  [void] Upgrade() {
    pip install --user --upgrade pipenv
  }
  [void] Remove() {
    & ($this.bin) --rm
  }
  static [version[]] GetPythonVersions() {
    return ((pyenv versions).Split("`n").Trim() | Select-Object @{l = "version"; e = { $l = $_; if ($l.StartsWith("*")) { $l = $l.Substring(1).TrimStart().Split(' ')[0] }; $m = $l -match [pipEnv].CONSTANTS.validversionregex; $m ? $l : "not-a-version" } } | Where-Object { $_.version -ne "not-a-version" }).version
  }
  hidden [void] __init__() {
    # add default requirements here. each array contains ("packageName", "description", { Install_script })
    [List[array]]$_req = @(
      ("pip", "The package installer for Python", {
        switch ([pipEnv]::data.Os) {
          'Windows' { py -m ensurepip --upgrade }
          default { python -m ensurepip --upgrade }
        }
        pip install --user --upgrade pip }
      ),
      ("pyenv", "Python version manager", {
        switch ([pipEnv]::data.Os) {
          'Windows' { Write-Warning "Pyenv does not officially support Windows and does not work in Windows outside the Windows Subsystem for Linux." }
          default { curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer | bash }
        } }
      ),
      ("pipenv", "Python virtualenv management tool", {
        pip install pipenv --user
        $sitepackages = python -m site --user-site
        $sitepackages = [pipEnv]::data.Os.Equals('Windows') ? $sitepackages.Replace('site-packages', 'Scripts') : $sitepackages
        # add $sitepackages to $env:PATH
        $env:PATH = "$env:PATH;$sitepackages" }
      )
    )
    [pipEnv].PsObject.Properties.Add([PsScriptproperty]::new('CONSTANTS', { return [scriptblock]::Create("@{
            # Add your constant primitives here:
            validversionregex = '^(0|[1-9]\d*)(\.(0|[1-9]\d*)){0,3}$'
          }").InvokeReturnAsIs()
        }, { throw [SetValueException]::new("CONSTANTS is read-only") }
      )
    )
    $1st_run = $null -eq [pipEnv]::data
    if ($1st_run) {
      [pipEnv]::req = $_req; $r = [pipEnv]::req; !$r.resolved ? $r.Resolve() : $null
      [pipEnv].PsObject.Properties.Add([PsNoteproperty]::new('data', [PsRecord]::new()))
      [pipEnv].data.set(@{
          SelectedVersion = [version]$(python --version).Split(" ").Where({ $_ -match [pipEnv].CONSTANTS.validversionregex })[0]
          Instance        = $([ref]$this).Value
          Os              = [xcrypt]::Get_Host_Os()
        }
      )
    }
    [pipEnv].data.PsObject.Properties.Add([PsScriptproperty]::new('PythonVersions', { return [pipEnv]::GetPythonVersions() }, { throw [SetValueException]::new("PythonVersions is read-only") }))
    $this.bin = (Get-Command pipenv -Type Application).Source
    [pipEnv].PsObject.Properties.Add([PsNoteproperty]::new('bin', $([ref]$this.bin).Value))
    $this.ProjectEnv = [Venv]::Create()
    if ($1st_run) {
      [pipEnv]::data = ([ref][pipEnv].data).Value
    }
  }
}

#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
  [InstallRequirements],
  [Requirement],
  [pipEnv],
  [Venv]
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
