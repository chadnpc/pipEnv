#!/usr/bin/env pwsh
using namespace System.IO
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
      Write-Host "[Resolve requrement] $($this.Name) " -f Green -NoNewline
      if ($this.Description) {
        Write-Host "($($this.Description)) " -f BlueViolet -NoNewline
      }
      Write-Host "$($this.Version) " -f Green
      if ($What_If.IsPresent) {
        Write-Host "Would install: $($this.Name)" -f Yellow
      } else {
        $this.InstallScript | Invoke-Expression -Force
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
  InstallRequirements([hashtable]$Map) {
    $Map.Keys | ForEach-Object { $Map[$_] ? ($this.$_ = $Map[$_]) : $null }
  }
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
  [PsRecord]$Config
  hidden [string]$__name
  hidden Venv([IO.DirectoryInfo]$dir) {
    $this.Path = $dir.FullName;
    $this.PsObject.Properties.Add([Psscriptproperty]::new('Name', {
          $v = $true; $d = [IO.DirectoryInfo]::new($this.Path); ("bin", "lib").ForEach{
            $_d = $d.EnumerateDirectories($_); $v = $v -and (($_d.count -eq 1) ? $true : $false)
            if ($_ -eq 'bin') { $v = $v -and (($_d[0].EnumerateFiles("activate*").Count -gt 0) ? $true : $false) }
          }; $v = $v -and (($d.EnumerateFiles("pyvenv.cfg").Count -eq 1) ? $true : $false);
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
      $this.Config = $c;
    }
  }
  static [Venv] Create() {
    return [Venv]::Create([IO.DirectoryInfo](Resolve-Path .).Path)
  }
  static [Venv] Create([IO.DirectoryInfo]$rootPath) {
    return [Venv]::Create(".venv", $rootPath)
  }
  static [Venv] Create([string]$Name, [IO.DirectoryInfo]$rootPath) {
    $venvPath = [IO.Path]::Combine($rootPath.FullName, $Name)
    if (![IO.Directory]::Exists($venvPath)) { Write-Console "Create venv $Name" -f LimeGreen; python -m venv $Name }
    $verfile = [IO.Path]::Combine($rootPath.FullName, ".python-version")
    if ([IO.File]::Exists($verfile)) {
      $ver = Get-Content $verfile; $localver = pyenv local
      if ($localver -ne $ver) {
        $sc = [scriptblock]::Create("pyenv install $ver")
        Write-Console "[Python version $ver] " -f LimeGreen -NoNewLine; [progressUtil]::WaitJob("Installing", (Start-Job -Name "Install python $ver" -ScriptBlock $sc));
      }
    }
    return [venv]::new((Get-Item $venvPath -Force -EA Ignore))
  }
  [void] Activate() {
    $spath = Resolve-Path ([IO.Path]::Combine($this.Path, 'bin', 'Activate.ps1')) -ea Ignore
    if (![IO.File]::Exists($spath)) { throw [FileNotFoundException]::new("Venv activation script not found: $spath") }
    &$spath
  }
}

# https://github.com/pypa/pipEnv?tab=readme-ov-file#installation

class pipEnv {
}

#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
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
