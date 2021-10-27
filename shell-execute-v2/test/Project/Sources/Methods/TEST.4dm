//%attributes = {}
  //$processes:=GET PROCESS LIST 

/*
empty string for "association execute command (delegate)"
*/
$docPath:=Get 4D folder:C485(Current resources folder:K5:16)+"sample.pdf"
$appPath:=Find best application ($docPath)
OPEN WITH APPLICATION ($docPath;$appPath)

$docPath:=Get 4D folder:C485(Current resources folder:K5:16)+"sample.txt"
$appPath:=Find best application ($docPath)
PRINT WITH APPLICATION ($docPath;$appPath)
