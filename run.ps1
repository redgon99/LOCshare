param(
  [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'

function Wait-Ngrok {
  param([int]$TimeoutSec = 45)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    try {
      $resp = Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -Method Get -ErrorAction Stop
      $https = $resp.tunnels | Where-Object { $_.public_url -like 'https*' } | Select-Object -First 1
      if ($https) { return $https.public_url }
    } catch { Start-Sleep -Milliseconds 500 }
    Start-Sleep -Milliseconds 500
  }
  throw "ngrok public_url을 찾지 못했습니다."
}

# 0) 사전 체크
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Error "Node.js가 설치되어 있지 않습니다. https://nodejs.org/ 에서 설치하세요."; exit 1
}
if (-not (Test-Path -Path './server.js')) {
  Write-Error "현재 폴더에 server.js가 없습니다. 프로젝트 루트에서 실행하세요."; exit 1
}
# ngrok 실행 파일 경로 확인
$ngrokPath = ""
if (Test-Path ".\ngrok.exe") {
  $ngrokPath = ".\ngrok.exe"
} elseif (Get-Command ngrok -ErrorAction SilentlyContinue) {
  $ngrokPath = "ngrok"
} else {
  Write-Error "ngrok가 설치되어 있지 않습니다. https://ngrok.com/download 에서 설치 후 'ngrok config add-authtoken <토큰>'을 실행하세요."; exit 1
}

# 1) ngrok 시작 (warning page 비활성화)
Write-Host "[1/4] ngrok 터널 시작 중... (포트 $Port)"
$ngrok = Start-Process -FilePath $ngrokPath -ArgumentList "http", "$Port", "--host-header=rewrite" -PassThru -WindowStyle Hidden

# 2) public URL 대기 및 획득
$publicUrl = Wait-Ngrok -TimeoutSec 45
Write-Host "[2/4] ngrok HTTPS: $publicUrl"

# 3) 새 PowerShell 창에서 서버 실행 (PUBLIC_BASE_URL 설정)
Write-Host "[3/4] 서버 실행 (PUBLIC_BASE_URL=$publicUrl)"
$envCmd = "$env:PUBLIC_BASE_URL='$publicUrl'; node server.js"
Start-Process powershell -ArgumentList "-NoExit", "-Command", $envCmd | Out-Null
Start-Sleep -Seconds 2

# 4) 방 생성 및 링크 복사
Write-Host "[4/4] 방 생성 중..."
try {
  $room = Invoke-RestMethod -Uri "$publicUrl/api/rooms" -Method Post
  $roomId = $room.link.Split('/')[-1]  # localhost 링크에서 방 ID 추출
  $publicLink = "$publicUrl/r/$roomId"  # ngrok URL로 공개 링크 생성
  Set-Clipboard -Value $publicLink
  Write-Host "
공개 방 링크: $publicLink"
  Write-Host "(클립보드에 복사되었습니다. 문자/메신저로 보내세요.)
"
} catch {
  Write-Warning "방 생성 실패: $_"
  Write-Warning "브라우저에서 $publicUrl/api/rooms 로 수동 호출해 보세요."
}

Write-Host "ngrok 터널과 서버 창은 켜 둔 상태로 유지하세요. 종료 시 위치 공유도 중단됩니다."