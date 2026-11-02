#requires -Version 7.2
param(
 [Parameter(Mandatory)][ValidateSet('Export','Restore','Verify')][string]$Mode,
 [Parameter(Mandatory)][string]$BackupFile,
 [string]$ApplicationDirectory=$PSScriptRoot,
 [Security.SecureString]$Password
)
$ErrorActionPreference='Stop'
if(!$Password){$Password=Read-Host 'Backup password' -AsSecureString}
$applicationPath=[IO.Path]::GetFullPath($ApplicationDirectory)
$backupPath=[IO.Path]::GetFullPath($BackupFile)
$keyPath=Join-Path $applicationPath 'local-data/local-keys.dpapi'
function Read-LocalKeyStore {
 if(!(Test-Path -LiteralPath $keyPath)){return @{}}
 $clear=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($keyPath),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 try {return ([Text.Encoding]::UTF8.GetString($clear)|ConvertFrom-Json -AsHashtable)} finally {[Array]::Clear($clear,0,$clear.Length)}
}
function Random-Bytes([int]$Count){$value=[byte[]]::new($Count);[Security.Cryptography.RandomNumberGenerator]::Fill($value);return ,$value}
function Derive-Keys([byte[]]$Salt,[int]$Iterations){
 $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
 try {
  $plainPassword=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  $kdf=[Security.Cryptography.Rfc2898DeriveBytes]::new($plainPassword,$Salt,$Iterations,[Security.Cryptography.HashAlgorithmName]::SHA256)
  try {return ,$kdf.GetBytes(64)} finally {$kdf.Dispose();$plainPassword=$null}
 } finally {[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)}
}
$material=$null;$plain=$null
try {
 if($Mode -eq 'Export'){
  if(Test-Path -LiteralPath $backupPath){throw 'Backup destination already exists; choose a new filename.'}
  $keys=Read-LocalKeyStore
  $config=Get-Content (Join-Path $applicationPath 'offline-config.json') -Raw|ConvertFrom-Json
  foreach($field in @('library','shared_library','account_library')){
   $root=$config.$field
   if(!$root){continue}
   if(![IO.Path]::IsPathRooted($root)){$root=Join-Path $applicationPath $root}
   if(!(Test-Path (Join-Path $root 'state.json'))){continue}
   $state=Get-Content (Join-Path $root 'state.json') -Raw|ConvertFrom-Json -AsHashtable
   foreach($record in $state.files.Values){
    if(!$record.key_file){continue}
    $key=Get-Content (Join-Path $root $record.key_file) -Raw|ConvertFrom-Json
    if($key.source_sha256 -ne $record.source_sha256){throw 'Library key association mismatch.'}
    if($keys.ContainsKey($key.file_id) -and $keys[$key.file_id] -cne $key.password){throw 'Conflicting keys.'}
    $keys[$key.file_id]=$key.password
   }
  }
  $salt=Random-Bytes 32;$iv=Random-Bytes 16;$iterations=600000;$material=Derive-Keys $salt $iterations
  $plain=[Text.Encoding]::UTF8.GetBytes(($keys|ConvertTo-Json -Compress))
  $aes=[Security.Cryptography.Aes]::Create();$aes.Key=$material[0..31];$aes.IV=$iv
  try {$transform=$aes.CreateEncryptor();try{$cipher=$transform.TransformFinalBlock($plain,0,$plain.Length)}finally{$transform.Dispose()}}finally{$aes.Dispose()}
  $payload=@{format='ftecu-key-backup-v1';iterations=$iterations;salt=[Convert]::ToBase64String($salt);iv=[Convert]::ToBase64String($iv);ciphertext=[Convert]::ToBase64String($cipher)}|ConvertTo-Json -Compress
  $mac=[Security.Cryptography.HMACSHA256]::new([byte[]]$material[32..63])
  try {$tag=$mac.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))} finally {$mac.Dispose()}
  @{payload=$payload;hmac=[Convert]::ToBase64String($tag)}|ConvertTo-Json -Compress|Set-Content -LiteralPath $backupPath -Encoding utf8
  [pscustomobject]@{result='exported';key_count=$keys.Count;backup_file=$backupPath}
 }else{
  $envelope=Get-Content -LiteralPath $backupPath -Raw|ConvertFrom-Json
  $payload=$envelope.payload|ConvertFrom-Json
  if($payload.format -ne 'ftecu-key-backup-v1' -or $payload.iterations -ne 600000){throw 'Unsupported backup format.'}
  $material=Derive-Keys ([Convert]::FromBase64String($payload.salt)) $payload.iterations
  $mac=[Security.Cryptography.HMACSHA256]::new([byte[]]$material[32..63])
  try {$expected=$mac.ComputeHash([Text.Encoding]::UTF8.GetBytes($envelope.payload))} finally {$mac.Dispose()}
  $actual=[Convert]::FromBase64String($envelope.hmac);$difference=$expected.Length -bxor $actual.Length
  if($actual.Length -eq $expected.Length){for($i=0;$i -lt $expected.Length;$i++){$difference=$difference -bor ($expected[$i] -bxor $actual[$i])}}
  if($difference -ne 0){throw 'Wrong password or damaged backup.'}
  $aes=[Security.Cryptography.Aes]::Create();$aes.Key=$material[0..31];$aes.IV=[Convert]::FromBase64String($payload.iv)
  try {$cipher=[Convert]::FromBase64String($payload.ciphertext);$transform=$aes.CreateDecryptor();try{$plain=$transform.TransformFinalBlock($cipher,0,$cipher.Length)}finally{$transform.Dispose()}}finally{$aes.Dispose()}
  $imported=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json -AsHashtable
  if($Mode -eq 'Restore'){
   $keys=Read-LocalKeyStore
   foreach($id in $imported.Keys){if($keys.ContainsKey($id) -and $keys[$id] -cne $imported[$id]){throw 'Conflicting existing key; nothing restored.'};$keys[$id]=$imported[$id]}
   $merged=[Text.Encoding]::UTF8.GetBytes(($keys|ConvertTo-Json -Compress))
   try {$sealed=[Security.Cryptography.ProtectedData]::Protect($merged,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)} finally {[Array]::Clear($merged,0,$merged.Length)}
   $null=New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($keyPath))
   [IO.File]::WriteAllBytes($keyPath+'.tmp',$sealed)
   if(Test-Path $keyPath){[IO.File]::Replace($keyPath+'.tmp',$keyPath,$keyPath+'.before-restore')}else{[IO.File]::Move($keyPath+'.tmp',$keyPath)}
  }
  [pscustomobject]@{result=if($Mode -eq 'Restore'){'restored'}else{'verified'};key_count=$imported.Count}
 }
} finally {if($plain){[Array]::Clear($plain,0,$plain.Length)};if($material){[Array]::Clear($material,0,$material.Length)};$keys=$null;$imported=$null}
