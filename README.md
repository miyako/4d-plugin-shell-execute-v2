![version](https://img.shields.io/badge/version-17%2B-3E8B93)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm%20|%20win-64&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-shell-execute-v2)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-shell-execute-v2/total)

**Note**: for v17 and earlier, move `manifest.json` to `Contents`

# 4d-plugin-shell-execute-v2
 Commands to open or print a document with the default application.

```
application:=Find best application (document)
OPEN WITH APPLICATION (document;application)
PRINT WITH APPLICATION (document;application)
```

Parameter|Type|Description
------------|------------|----
document|TEXT|Full path of document
application|TEXT|Full path of application

```
GET PROCESS LIST (names;paths;PIDs)
```

Parameter|Type|Description
------------|------------|----
names|ARRAY TEXT|Application names
paths|ARRAY TEXT|Application paths
PIDs|ARRAY LONGINT|Process numbers

### Examples

```
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
