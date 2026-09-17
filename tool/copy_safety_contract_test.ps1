# Fake adb executable and fake Dart verifier; never invokes an Android device.
$ErrorActionPreference = 'Stop'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('jax-copy-safety-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temp | Out-Null
$env:JAX_COPY_TEST_ROOT=$temp
$code = @'
using System;
using System.IO;
using System.Linq;
class FakeAdb {
 static string R { get { return Environment.GetEnvironmentVariable("JAX_COPY_TEST_ROOT"); } }
 static int Main(string[] a) {
  string call=String.Join(" ",a); File.AppendAllText(Path.Combine(R,"calls.log"),call+"\n");
  if (call=="devices") { Console.WriteLine("List of devices attached\nfixture-device\tdevice"); if(Environment.GetEnvironmentVariable("JAX_COPY_MULTIPLE")=="1") Console.WriteLine("second-device\tdevice"); return 0; }
  if(call.Contains("pm list packages")) {Console.WriteLine("package:com.jarrett.jax");return 0;}
  if(call.EndsWith("run-as com.jarrett.jax pwd")){Console.WriteLine("/data/user/0/com.jarrett.jax");return 0;}
  if(call.Contains(" test -f ")) return call.EndsWith("databases/jax.db") ? 0 : 1;
  if(call.Contains("exec-out")) {
   if(Environment.GetEnvironmentVariable("JAX_COPY_BACKUP_FAIL")=="1") return 1;
   byte[] b=File.ReadAllBytes(Path.Combine(R,"target.db")); Console.OpenStandardOutput().Write(b,0,b.Length);return 0;
  }
  if(a.Length>3 && a[2]=="push") {File.Copy(a[3],Path.Combine(R,"pushed.db"),true);return 0;}
  if(call.Contains("cat > databases/jax.db.import")){File.Copy(Path.Combine(R,"pushed.db"),Path.Combine(R,"staged.db"),true);return 0;}
  if(call.Contains(" mv ")) { File.Copy(Path.Combine(R,"staged.db"),Path.Combine(R,"target.db"),true);return 0; }
  if(call.Contains("force-stop") || call.Contains(" rm ") || call.Contains(" chmod ")) return 0;
  Console.Error.WriteLine("Unexpected fake ADB operation"); return 2;
 }
}
'@
$source=Join-Path $temp 'fake.cs'; Set-Content -LiteralPath $source -Value $code
$adb=Join-Path $temp 'adb.exe'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path $compiler)) { throw 'Fixture compiler unavailable; copy tests not executed.' }
& $compiler /nologo /out:$adb $source
if ($LASTEXITCODE -ne 0) { throw 'Fake ADB compilation failed.' }
$dart=Join-Path $temp 'dart.ps1'
Set-Content -LiteralPath $dart -Value @'
$global:LASTEXITCODE=0
$mode=$args[2]; $inputFile=$args[3]
if ($env:JAX_COPY_SCHEMA_FAIL -eq '1') { $global:LASTEXITCODE=1; return }
if ($mode -like 'snapshot*') { Copy-Item -LiteralPath $inputFile -Destination $args[4]; return }
if ($mode -like 'verify*') {
 if ($env:JAX_COPY_VERIFY_FAIL -eq '1' -and (Get-Content -LiteralPath $inputFile -Raw) -eq 'new') { $global:LASTEXITCODE=1 }
 return
}
throw 'Unexpected fake Dart operation'
'@
$sourceDb=Join-Path $temp 'source.db'; [IO.File]::WriteAllText($sourceDb,'new')
$target=Join-Path $temp 'target.db'
$copy=Join-Path $PSScriptRoot 'copy_windows_data_to_android.ps1'
$common=@{SourceDatabase=$sourceDb;Device='fixture-device';Package='com.jarrett.jax';AdbPath=$adb;DartPath=$dart;BackupRoot=(Join-Path $temp 'backups')}
function Assert([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
foreach($case in @('dry','wrong-package','backup-fail','schema-fail','success','verify-fail')) {
 [IO.File]::WriteAllText($target,'old')
 foreach($name in @('JAX_COPY_BACKUP_FAIL','JAX_COPY_SCHEMA_FAIL','JAX_COPY_VERIFY_FAIL')){[Environment]::SetEnvironmentVariable($name,'0')}
 if($case -eq 'backup-fail'){$env:JAX_COPY_BACKUP_FAIL='1'}
 if($case -eq 'schema-fail'){$env:JAX_COPY_SCHEMA_FAIL='1'}
 if($case -eq 'verify-fail'){$env:JAX_COPY_VERIFY_FAIL='1'}
 $params=$common.Clone();if($case -eq 'wrong-package'){$params.Package='not.jax'}
 $failed=$false
 try { if($case -eq 'dry'){ & $copy @params | Out-Null }else{ & $copy @params -Apply -ConfirmOverwrite | Out-Null } }
 catch { $failed=$true }
 Assert ($failed -eq ($case -notin @('dry','success'))) "Unexpected result: $case"
 $expected=if($case -eq 'success'){'new'}else{'old'}
 Assert (([IO.File]::ReadAllText($target)) -eq $expected) "Target/rollback mismatch: $case"
}
. (Join-Path $PSScriptRoot 'tool_locator.ps1')
$env:JAX_COPY_MULTIPLE='1';$failed=$false
try { Select-JaxDevice $adb '' | Out-Null } catch {$failed=$true}
Assert $failed 'Ambiguous device was selected'
$calls=Get-Content -LiteralPath (Join-Path $temp 'calls.log') -Raw
Assert ($calls -notmatch 'uninstall|pm clear| install ') 'Forbidden device operation'
foreach($name in @('JAX_COPY_TEST_ROOT','JAX_COPY_BACKUP_FAIL','JAX_COPY_SCHEMA_FAIL','JAX_COPY_VERIFY_FAIL','JAX_COPY_MULTIPLE')){[Environment]::SetEnvironmentVariable($name,$null)}
Write-Output 'PASS: copy dry-run, package rejection, backup/schema failure, verified copy, rollback and ambiguous devices. Fake devices only.'
