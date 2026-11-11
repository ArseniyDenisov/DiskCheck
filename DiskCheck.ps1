# ============================================================
#  DiskCheck 3.0 - утилита проверки дисков (SSD/HDD)
#  MARKER_DISKCHECK_V3
#
#  Показывает: SMART-атрибуты, износ, температуру, ошибки,
#  объём записи и итоговый вердикт по каждому диску.
#  Подходит для дисков любых производителей (SATA / NVMe).
#  Ничего не устанавливает и ничего не меняет в системе.
#
#  ЗАПУСК:
#    1) двойной клик по DiskCheck.bat (лежит рядом с этим файлом)
#    2) или ПКМ по этому файлу -> "Выполнить с помощью PowerShell"
#  Скрипт сам запросит права администратора (окно UAC -> "Да").
#
#  Журнал измерений копится в DiskCheck_history.csv рядом со
#  скриптом - можно следить за динамикой между запусками.
#
#  Скрытые параметры (для отладки): -SkipElevation, -NoPause
# ============================================================

param(
    [switch]$SkipElevation,
    [switch]$NoPause
)

# --- Права администратора (перезапуск с UAC) ---
$scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $SkipElevation) {
    try {
        Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', ('"' + $scriptPath + '"'))
    } catch {
        Write-Host 'Без прав администратора подробные показания недоступны.' -ForegroundColor Yellow
        Read-Host 'Нажмите Enter для выхода' | Out-Null
    }
    exit
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$Host.UI.RawUI.WindowTitle = 'DiskCheck 3.0 - проверка дисков'

# ================= ШАПКА =================
$font = @{
    'D' = @('█████','█   █','█   █','█   █','█   █','█████')
    'I' = @('██','█ ','█ ','█ ','█ ','██')
    'S' = @(' ████','█    ','█    ',' ███ ','    █','████ ')
    'K' = @('█   █','█  █ ','█ █  ','██   ','█ █  ','█  █ ')
    'C' = @(' ████','█    ','█    ','█    ','█    ',' ████')
    'H' = @('█   █','█   █','█████','█   █','█   █','█   █')
    'E' = @('█████','█    ','████ ','█    ','█    ','█████')
}
$word = 'DISK CHECK'
Write-Host ''
for ($r = 0; $r -lt 6; $r++) {
    $parts = @()
    foreach ($ch in $word.ToCharArray()) {
        if ([string]$ch -eq ' ') { $parts += '   ' } else { $parts += $font[[string]$ch][$r] }
    }
    Write-Host ('    ' + ($parts -join ' ')) -ForegroundColor Cyan
}

$os  = Get-WmiObject Win32_OperatingSystem
$cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
Write-Host ''
Write-Host ('    ' + ('═' * 62)) -ForegroundColor DarkCyan
Write-Host '    DiskCheck 3.0' -ForegroundColor Yellow -NoNewline
Write-Host '  |  диагностика дисков' -ForegroundColor White -NoNewline
Write-Host '  |  SMART / износ / температура / ошибки' -ForegroundColor DarkCyan
Write-Host '    Диски любых производителей (SATA, NVMe). Ничего не устанавливает.' -ForegroundColor DarkGray
Write-Host ('    ' + ('═' * 62)) -ForegroundColor DarkCyan
Write-Host ('    Система   : {0} (build {1})' -f $os.Caption, $os.BuildNumber) -ForegroundColor DarkGray
Write-Host ('    Процессор : {0}' -f $cpu.Name) -ForegroundColor DarkGray
Write-Host ('    Проверка  : {0}   |   PowerShell {1}' -f (Get-Date -Format 'dd.MM.yyyy HH:mm'), $PSVersionTable.PSVersion) -ForegroundColor DarkGray
if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Host '    Внимание: PowerShell 2.0 - часть таблиц будет пропущена' -ForegroundColor Yellow
}
Write-Host ''

# --- вспомогательные функции ---
function Step($msg) {
    if ($msg.Length -lt 46) { $msg = $msg + ' ' + ('.' * (45 - $msg.Length)) }
    Write-Host ('    ' + $msg + ' ') -NoNewline -ForegroundColor Gray
}
function StepOk { Write-Host '[OK]' -ForegroundColor Green }
function StepWarn($t) { Write-Host '[~~]' -ForegroundColor Yellow; Write-Host ('        ' + $t) -ForegroundColor Yellow }
function StepFail($t) { Write-Host '[!!]' -ForegroundColor Red; Write-Host ('        ' + $t) -ForegroundColor Red }
function Show-Box($msg, $color) {
    $w = 64
    Write-Host ''
    Write-Host ('    ╔' + ('═' * $w) + '╗') -ForegroundColor $color
    Write-Host ('    ║ ' + $msg.PadRight($w - 2) + '║') -ForegroundColor $color
    Write-Host ('    ╚' + ('═' * $w) + '╝') -ForegroundColor $color
    Write-Host ''
}

# ================= ШАГ 1: СПИСОК ДИСКОВ =================
Step 'Определение дисков в системе'
$physDisks = $null
try { $physDisks = @(Get-PhysicalDisk -ErrorAction Stop) } catch { }
if ($physDisks) {
    StepOk
    $physDisks |
        Select-Object @{N='N';E={$_.DeviceId}}, FriendlyName, MediaType, BusType,
            @{N='Gb';E={[math]::Round($_.Size/1GB)}}, HealthStatus |
        Format-Table -AutoSize | Out-String -Width 90 | ForEach-Object { Write-Host $_ }
} else {
    StepWarn 'Storage API недоступен (старая система?), беру список из WMI'
    Get-WmiObject Win32_DiskDrive |
        Select-Object @{N='Idx';E={$_.Index}}, @{N='Model';E={$_.Model}},
            @{N='Gb';E={[math]::Round($_.Size/1GB)}}, @{N='Status';E={$_.Status}} |
        Format-Table -AutoSize | Out-String -Width 90 | ForEach-Object { Write-Host $_ }
}

# ================= ШАГ 2: ПРОШИВКА И СЕРИЙНИКИ =================
Step 'Прошивка и серийные номера'
$diskByNum = @{}
$gd = $null
try { $gd = @(Get-Disk -ErrorAction Stop) } catch { }
if ($gd) {
    StepOk
    $gd | Select-Object @{N='N';E={$_.Number}}, FriendlyName, FirmwareVersion, SerialNumber, BusType |
        Format-Table -AutoSize | Out-String -Width 90 | ForEach-Object { Write-Host $_ }
    foreach ($dk in $gd) { $diskByNum[[int]$dk.Number] = $dk }
} else {
    StepWarn 'Get-Disk недоступен, беру данные из WMI'
    foreach ($wd in (Get-WmiObject Win32_DiskDrive)) {
        $diskByNum[[int]$wd.Index] = $wd
    }
    Get-WmiObject Win32_DiskDrive |
        Select-Object @{N='Idx';E={$_.Index}}, @{N='Model';E={$_.Model}},
            @{N='Firmware';E={$_.FirmwareRevision}}, @{N='Serial';E={$_.SerialNumber}} |
        Format-Table -AutoSize | Out-String -Width 90 | ForEach-Object { Write-Host $_ }
}

# ================= ШАГ 3: ПОКАЗАТЕЛИ НАДЁЖНОСТИ =================
Step 'Показатели надёжности (Storage API)'
$relByDisk = @{}
$relCount = 0
try {
    Get-PhysicalDisk | Get-StorageReliabilityCounter -ErrorAction Stop |
        ForEach-Object { $relByDisk[[int]$_.DeviceId] = $_; $relCount++ }
} catch { }
if ($relCount -gt 0) {
    StepOk
    Get-PhysicalDisk | Get-StorageReliabilityCounter |
        Select-Object @{N='N';E={$_.DeviceId}},
            @{N='Iznos, %';E={ if ($null -ne $_.Wear) { $_.Wear } else { '-' } }},
            @{N='Temp, C';E={ $t = $_.Temperature; if ($null -eq $t) { '-' } elseif ($t -ge 1000) { [math]::Round($t/10 - 273.15) } elseif ($t -ge 100) { [math]::Round($t - 273.15) } else { $t } }},
            @{N='Narabotka, ch';E={ if ($null -ne $_.PowerOnHours) { $_.PowerOnHours } else { '-' } }},
            @{N='Oshibki chteniya';E={ if ($null -ne $_.ReadErrorsTotal) { $_.ReadErrorsTotal } else { '-' } }},
            @{N='Oshibki zapisi';E={ if ($null -ne $_.WriteErrorsTotal) { $_.WriteErrorsTotal } else { '-' } }} |
        Format-Table -AutoSize | Out-String -Width 90 | ForEach-Object { Write-Host $_ }
} else {
    StepWarn 'Storage API недоступен - обойдусь без него'
}

# ================= ШАГ 4: SMART =================
Step 'Чтение SMART-таблицы через WMI'
$smartStatus = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
$smartData   = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictData -ErrorAction SilentlyContinue
$predictByInst = @{}
if ($smartStatus) { foreach ($s in $smartStatus) { $predictByInst[$s.InstanceName] = $s.PredictFailure } }
if ($smartData) { StepOk } else { StepFail 'сырой SMART недоступен на этой машине' }

$smartNames = @{
    1='Read Error Rate'; 5='Reallocated Sectors'; 9='Power-On Hours'; 12='Power Cycle Count';
    170='Reserved Block Count'; 171='Program Fail Count'; 172='Erase Fail Count';
    173='Wear Leveling Count'; 174='Unexpected Power Loss'; 177='Wear Range Delta';
    181='Program Fail (total)'; 182='Erase Fail (total)'; 183='Runtime Bad Blocks';
    187='Reported Uncorrectable'; 188='Command Timeout'; 192='Unsafe Shutdowns';
    194='Temperature'; 195='ECC Error Rate'; 196='Reallocation Events';
    197='Current Pending Sectors'; 198='Offline Uncorrectable'; 199='UltraDMA CRC Errors';
    231='SSD Life Left'; 233='Media Wearout (P/E)'; 241='Total LBAs Written';
    242='Total LBAs Read'; 249='NAND GB Written'
}

$histLines = @()
$totalProblems = 0
$disksChecked = 0

if ($smartData) {
    foreach ($d in $smartData) {
        $diskNum = 0
        if ($d.InstanceName -match '_(\d+)$') { $diskNum = [int]$Matches[1] }
        $dk = $diskByNum[$diskNum]
        $label = if ($dk) { $dk.FriendlyName } else { 'диск ' + $diskNum }

        Write-Host ''
        Write-Host ('  ── ДИСК {0}: {1} ─────────────────────────────────────────' -f $diskNum, $label) -ForegroundColor Cyan
        if ($predictByInst.ContainsKey($d.InstanceName) -and $predictByInst[$d.InstanceName]) {
            Write-Host '  Прогноз сбоя SMART: ДА - диск предсказывает отказ!' -ForegroundColor Red
        } else {
            Write-Host '  Прогноз сбоя SMART: нет' -ForegroundColor DarkGray
        }

        $stats = @{ HostWritesGB = $null; HostReadsGB = $null; NandGB = $null; Reallocated = $null
                    Pending = $null; Uncorr = $null; CRC = $null; TempC = $null; Hours = $null }
        $v = $d.VendorSpecific

        $fmt = '      {0,-4} {1,-32} {2,4} {3,4} {4,12}  {5}'
        Write-Host ($fmt -f 'ID', 'Атрибут', 'val', 'wrst', 'raw', 'примечание') -ForegroundColor DarkCyan
        Write-Host ('      ' + ('-' * 78)) -ForegroundColor DarkGray
        for ($i = 0; $i -lt 30; $i++) {
            $off = 2 + $i * 12
            $id = [int]$v[$off]
            if ($id -eq 0) { continue }
            $value = [int]$v[$off + 3]
            $worst = [int]$v[$off + 4]
            $raw = [uint64]0
            for ($b = 5; $b -ge 0; $b--) { $raw = $raw * 256 + [uint64]$v[$off + 5 + $b] }
            $name = if ($smartNames.ContainsKey($id)) { $smartNames[$id] } else { 'Vendor-specific' }
            $note = ''
            switch ($id) {
                9   { $stats.Hours = $raw; $note = ('{0} часов' -f $raw) }
                12  { $note = 'циклов питания' }
                194 { $stats.TempC = $raw; $note = ('{0} C' -f $raw) }
                231 { $note = ('{0}% запаса ресурса' -f $value) }
                5   { $stats.Reallocated = $raw }
                197 { $stats.Pending = $raw }
                198 { $stats.Uncorr = $raw }
                199 { $stats.CRC = $raw }
                241 { $stats.HostWritesGB = [math]::Round($raw / 32, 1); $note = ('~{0} ГБ записано хостом (блоки 32 МБ)' -f $stats.HostWritesGB) }
                242 { $stats.HostReadsGB = [math]::Round($raw / 32, 1); $note = ('~{0} ГБ прочитано (блоки 32 МБ)' -f $stats.HostReadsGB) }
                249 { $stats.NandGB = $raw; $note = ('{0} ГБ записано в NAND' -f $raw) }
            }
            Write-Host ($fmt -f ('{0:X2}' -f $id), $name, $value, $worst, $raw, $note)
        }

        if ($stats.HostWritesGB -and $stats.NandGB) {
            $waf = [math]::Round($stats.NandGB / $stats.HostWritesGB, 2)
            Write-Host ''
            Write-Host ('  Записано хостом: {0} ГБ | в NAND: {1} ГБ | WAF: {2}' -f $stats.HostWritesGB, $stats.NandGB, $waf) -ForegroundColor DarkCyan
        }

        # --- Вердикт ---
        $rel = $relByDisk[$diskNum]
        $problems = @()
        if ($stats.Reallocated -and $stats.Reallocated -gt 0) { $problems += ('переназначенные секторы (05): ' + $stats.Reallocated) }
        if ($stats.Pending -and $stats.Pending -gt 0) { $problems += ('секторы-кандидаты на замену (C5): ' + $stats.Pending) }
        if ($stats.Uncorr -and $stats.Uncorr -gt 0) { $problems += ('неисправимые ошибки (C6): ' + $stats.Uncorr) }
        if ($stats.CRC -and $stats.CRC -gt 0) { $problems += ('CRC-ошибки SATA (C7): ' + $stats.CRC + ' - проверить кабель/порт') }
        if ($stats.TempC -and $stats.TempC -ge 60) { $problems += ('температура ' + $stats.TempC + ' C') }
        if ($rel -and $null -ne $rel.Wear -and $rel.Wear -ge 50) { $problems += ('износ ' + $rel.Wear + '%') }
        if ($rel -and $null -ne $rel.ReadErrorsTotal -and $rel.ReadErrorsTotal -gt 0) { $problems += ('ошибки чтения (Storage API): ' + $rel.ReadErrorsTotal) }

        $disksChecked++
        if ($problems.Count -eq 0) {
            Show-Box ('ДИСК {0} ({1}): ЗДОРОВ - критичных проблем не найдено' -f $diskNum, $label) 'Green'
        } else {
            $totalProblems += $problems.Count
            Show-Box ('ДИСК {0} ({1}): ЕСТЬ ЗАМЕЧАНИЯ ({2})' -f $diskNum, $label, $problems.Count) 'Yellow'
            foreach ($p in $problems) { Write-Host ('      - ' + $p) -ForegroundColor Yellow }
        }

        # --- строка журнала ---
        $verdict = if ($problems.Count) { 'ЗАМЕЧАНИЯ: ' + ($problems -join '; ') } else { 'ЗДОРОВ' }
        $histLines += ((@((Get-Date -Format 'yyyy-MM-dd HH:mm'), $label,
            $(if ($dk) { $dk.SerialNumber } else { '' }),
            $(if ($rel -and $null -ne $rel.Wear) { $rel.Wear } else { '' }),
            $(if ($stats.TempC) { $stats.TempC } else { '' }),
            $(if ($stats.Hours) { $stats.Hours } else { '' }),
            $stats.HostWritesGB, $stats.NandGB,
            $stats.Reallocated, $stats.Pending, $stats.CRC, $verdict) |
            ForEach-Object { '"' + ([string]$_).Replace('"','""') + '"' }) -join ';')
    }
}

# --- запасной вердикт, если SMART недоступен, но Storage API есть ---
if (-not $smartData -and $relCount -gt 0) {
    foreach ($num in $relByDisk.Keys) {
        $rel = $relByDisk[$num]
        $dk = $diskByNum[$num]
        $label = if ($dk) { $dk.FriendlyName } else { 'диск ' + $num }
        $problems = @()
        if ($rel.Wear -ne $null -and $rel.Wear -ge 50) { $problems += ('износ ' + $rel.Wear + '%') }
        if ($rel.ReadErrorsTotal -ne $null -and $rel.ReadErrorsTotal -gt 0) { $problems += ('ошибки чтения: ' + $rel.ReadErrorsTotal) }
        $disksChecked++
        if ($problems.Count -eq 0) {
            Show-Box ('ДИСК {0} ({1}): показания в норме' -f $num, $label) 'Green'
        } else {
            $totalProblems += $problems.Count
            Show-Box ('ДИСК {0} ({1}): ЕСТЬ ЗАМЕЧАНИЯ' -f $num, $label) 'Yellow'
            foreach ($p in $problems) { Write-Host ('      - ' + $p) -ForegroundColor Yellow }
        }
    }
}

# ================= ШАГ 5: ЖУРНАЛ =================
if ($histLines.Count -gt 0) {
    Step 'Сохранение журнала измерений'
    $baseDir = if ($PSScriptRoot) { $PSScriptRoot } else { $env:USERPROFILE }
    $histPath = Join-Path $baseDir 'DiskCheck_history.csv'
    $histHeader = 'Дата;Диск;Серийник;Износ %;Темп C;Наработка ч;Хост записано ГБ;NAND записано ГБ;Reallocated 05;Pending C5;CRC C7;Вердикт'
    try {
        if (-not (Test-Path -LiteralPath $histPath)) { Set-Content -LiteralPath $histPath -Value $histHeader -Encoding UTF8 }
        Add-Content -LiteralPath $histPath -Value $histLines -Encoding UTF8
        StepOk
        Write-Host ('        журнал: ' + $histPath) -ForegroundColor DarkGray
    } catch {
        try {
            $histPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'DiskCheck_history.csv'
            if (-not (Test-Path -LiteralPath $histPath)) { Set-Content -LiteralPath $histPath -Value $histHeader -Encoding UTF8 }
            Add-Content -LiteralPath $histPath -Value $histLines -Encoding UTF8
            StepWarn ('журнал сохранён в Документы: ' + $histPath)
        } catch {
            StepFail 'не удалось сохранить журнал (нет прав на запись)'
        }
    }
}

# ================= ИТОГ =================
$sw.Stop()
if ($disksChecked -eq 0) {
    Show-Box 'НЕ УДАЛОСЬ ПРОЧИТАТЬ НИ ОДИН ДИСК' 'Red'
    Write-Host '    Попробуйте запустить от имени администратора или на другой машине.' -ForegroundColor DarkGray
} elseif ($totalProblems -eq 0) {
    Show-Box ('ИТОГ ПРОВЕРКИ: ВСЕ ДИСКИ ЗДОРОВЫ  (проверено дисков: {0})' -f $disksChecked) 'Green'
} else {
    Show-Box ('ИТОГ ПРОВЕРКИ: ЕСТЬ ЗАМЕЧАНИЯ  (дисков: {0}, замечаний: {1})' -f $disksChecked, $totalProblems) 'Yellow'
}
Write-Host ('    Проверка заняла {0:f1} с   |   DiskCheck 3.0' -f $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray

Write-Host ''
Write-Host '  Подсказки:' -ForegroundColor DarkGray
Write-Host '    - износ 0-10% отлично, 10-50% норма, выше 50% - резервные копии' -ForegroundColor DarkGray
Write-Host '    - температура до 60 C - норма; 05 / C5 / C6 / C7 должны быть 0' -ForegroundColor DarkGray
Write-Host '    - счётчики записи 241/242 обычно в блоках 32 МБ; WAF 1.0-2.0 - норма' -ForegroundColor DarkGray
Write-Host '    - журнал DiskCheck_history.csv (разделитель ;, открывается в Excel)' -ForegroundColor DarkGray
Write-Host ''

if (-not $NoPause) { Read-Host '  Нажмите Enter для выхода' | Out-Null }
