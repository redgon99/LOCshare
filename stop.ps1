Get-Process -Name ngrok -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name node  -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "ngrok / node 프로세스를 종료했습니다."