# Allow HomeShare ports through Windows Firewall (run as Administrator)
$ErrorActionPreference = "Stop"
New-NetFirewallRule -DisplayName "HomeShare P2P TCP" -Direction Inbound -Protocol TCP -LocalPort 45838 -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "HomeShare Discovery UDP" -Direction Inbound -Protocol UDP -LocalPort 45837 -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "HomeShare Agent" -Direction Inbound -Protocol TCP -LocalPort 47831 -RemoteAddress LocalSubnet -Action Allow -ErrorAction SilentlyContinue
Write-Host "Firewall rules added for HomeShare."
