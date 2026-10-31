param(
    [string]$ResultsDirectory = "$env:WORKSPACE\jmeter-results"
)

$ErrorActionPreference = "Stop"

# Training thresholds
$P95ThresholdMs = 1000
$MaxErrorRatePercent = 1.0

Write-Host "========================================"
Write-Host "JMeter Performance Acceptance Check"
Write-Host "========================================"

# Locate the newest JMeter results CSV
try {
    $csvFile = Get-ChildItem `
        -Path $ResultsDirectory `
        -Filter "*.csv" `
        -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}
catch {
    Write-Host "FAIL: Could not read results directory: $ResultsDirectory"
    exit 1
}

if ($null -eq $csvFile) {
    Write-Host "FAIL: No JMeter CSV results found in $ResultsDirectory"
    exit 1
}

Write-Host "Results file: $($csvFile.FullName)"

# Import the results
try {
    $results = @(Import-Csv -Path $csvFile.FullName -ErrorAction Stop)
}
catch {
    Write-Host "FAIL: Could not read the JMeter CSV file."
    exit 1
}

if ($results.Count -eq 0) {
    Write-Host "FAIL: The CSV file contains no result rows."
    exit 1
}

# Validate required columns
$requiredColumns = @("elapsed", "success")
$availableColumns = @($results[0].PSObject.Properties.Name)

foreach ($column in $requiredColumns) {
    if ($availableColumns -notcontains $column) {
        Write-Host "FAIL: Required CSV column '$column' was not found."
        exit 1
    }
}

# Validate and sort response times
$elapsedTimes = @(
    foreach ($row in $results) {
        $value = 0.0

        $validNumber = [double]::TryParse(
            $row.elapsed,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$value
        )

        if (-not $validNumber -or $value -lt 0) {
            Write-Host "FAIL: Invalid elapsed value found in the CSV."
            exit 1
        }

        $value
    }
) | Sort-Object

$totalSamples = $results.Count

$failedSamples = @(
    $results | Where-Object {
        $_.success -notmatch '^(?i:true)$'
    }
).Count

$errorRate = ($failedSamples / $totalSamples) * 100

# Calculate nearest-rank P95
$p95Index = [Math]::Ceiling(0.95 * $totalSamples) - 1
$p95Ms = [double]$elapsedTimes[$p95Index]

Write-Host ""
Write-Host "Total samples: $totalSamples"
Write-Host "Failed samples: $failedSamples"
Write-Host ("Error rate: {0:N2}%" -f $errorRate)
Write-Host ("P95 response time: {0:N0} ms" -f $p95Ms)
Write-Host ""

$failedChecks = 0

if ($p95Ms -ge $P95ThresholdMs) {
    Write-Host "FAIL: P95 must be below $P95ThresholdMs ms."
    $failedChecks++
}
else {
    Write-Host "PASS: P95 is below $P95ThresholdMs ms."
}

if ($errorRate -ge $MaxErrorRatePercent) {
    Write-Host "FAIL: Error rate must be below $MaxErrorRatePercent%."
    $failedChecks++
}
else {
    Write-Host "PASS: Error rate is below $MaxErrorRatePercent%."
}

if ($failedChecks -gt 0) {
    Write-Host ""
    Write-Host "RESULT: Performance acceptance check FAILED."
    exit 1
}

Write-Host ""
Write-Host "RESULT: Performance acceptance check PASSED."
exit 0