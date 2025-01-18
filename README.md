# [pipEnv](https://www.powershellgallery.com/packages/pipEnv)

Python project environment manager

Uses: [pipenv.pypa.io](https://pipenv.pypa.io/en/latest/)

Note: This is an unofficial pipenv wrapper (installer, runner and utilities) for
PowerShell.

> Why not use pipenv directly?

**tldr**: Command not work => I get frustated => I build patch thing.

**ex**: The command `pipenv shell` does not always work in Powershell. But this
wrapper was created to deal with that, not manually by me everytime.

## usage

```PowerShell
Install-Module pipEnv
```

then

```PowerShell
Import-Module pipEnv
# do stuff:
New-pipEnv .
```

hint: run `deactivate` to return

## status

- [x] wrapper. 40% complete

- [x] utilities

- [ ] tests

- [![GitHub Release Date](https://img.shields.io/github/release/alainQtec/pipEnv.svg)](https://github.com/alainQtec/pipEnv/releases)

## contributing

Pull requests are welcome.

```PowerShell
git clone https://github.com/alainQtec/pipEnv
cd pipEnv
git remote add upstream https://github.com/yourUserName/pipEnv.git
git fetch upstream
# make your changes... then
# Run build.ps1 -Task Test
# If everything passes:
git add .
git commit -m 'made cool changes to abc 😊'
git push origin main
```

## license

This project is licensed under the [WTFPL License](LICENSE).
