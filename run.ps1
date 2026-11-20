# Load SUPABASE_URL / SUPABASE_ANON_KEY from .env and launch the app.
$envMap = @{}
Get-Content ".env" | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $idx = $line.IndexOf("=")
        $envMap[$line.Substring(0, $idx).Trim()] = $line.Substring($idx + 1).Trim().Trim('"')
    }
}
if (-not $envMap["SUPABASE_URL"] -or -not $envMap["SUPABASE_ANON_KEY"]) {
    Write-Host ".env is missing SUPABASE_URL or SUPABASE_ANON_KEY" -ForegroundColor Red
    exit 1
}
flutter run -d chrome --web-port=8080 --dart-define=SUPABASE_URL=$($envMap["SUPABASE_URL"]) --dart-define=SUPABASE_ANON_KEY=$($envMap["SUPABASE_ANON_KEY"])
