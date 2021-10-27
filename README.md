![version](https://img.shields.io/badge/version-17%2B-3E8B93)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm%20|%20win-64&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-shell-execute-v2)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-shell-execute-v2/total)

**Note**: for v17 and earlier, move `manifest.json` to `Contents`

# 4d-plugin-shell-execute-v2
 Commands to open or print a document with the default application.

```4d
application:=Find best application (document)
OPEN WITH APPLICATION (document;application)
PRINT WITH APPLICATION (document;application)
```

Parameter|Type|Description
------------|------------|----
document|TEXT|Full path of document
application|TEXT|Full path of application

```4d
$processes:=GET PROCESS LIST
```

`$processes` is a collection of objects.

Parameter|Type|Description
------------|------------|----
name|TEXT|Application name
path|TEXT|Application path
pid|LONGINT|Process number

### Examples

```4d
  //full path of best application to open given document
$docPath:=Get 4D folder(Current resources folder)+"sample.pdf"
$appPath:=Find best application ($docPath)

  //OPEN WITH APPLICATION ($docPath;$appPath)
PRINT WITH APPLICATION ($docPath;$appPath)
```

### Remarks

on windows, only 3rd party apps registered the "normal way" are reported.

<img width="542" alt="スクリーンショット 2019-06-07 1 39 13" src="https://user-images.githubusercontent.com/1725068/59051497-fb730780-88c7-11e9-93c7-fecd7ea042fc.png">

for instance, a delegate executable (Edge for ``.pdf``) are not reported.

you can open or print the document even if "" (assocation execute command) is returned. you just don't know which app will be used.
