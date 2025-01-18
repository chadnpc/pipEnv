# [pipEnv](https://www.powershellgallery.com/packages/pipEnv)

Python project environment manager using
[pipEnv](https://pipenv.pypa.io/en/latest/)

this is basically a pipenv wrapper installer and utilities for PowerShell.

## Usage

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

## FAQs

- Why make this wrapper? Why not use pipenv directly?

  ==> commands not work as expected => I got frustated => I build thing to
  patch.

  Example: The command `pipenv shell` does not always work in Powershell. but
  this wrapper deals with that, not me.

## Status

- [x] wrapper. 40% complete

- [x] utilities

- [ ] tests

- [![GitHub Release Date](https://img.shields.io/github/release/alainQtec/pipEnv.svg)](https://github.com/alainQtec/pipEnv/releases)

## License

This project is licensed under the [WTFPL License](LICENSE).
