#requires -Version 7.0

param(
    [string]$CheckDirectory,
    [int]$InitialSample = 0,
    [switch]$ShowInformation
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'Run this preview with pwsh -STA.'
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class SubtitlePreviewWindow {
    private const int ExtendedStyle = -20;
    private const int NoActivate = 0x08000000;
    private const int Transparent = 0x00000020;
    private const int ToolWindow = 0x00000080;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetWindowLong(IntPtr window, int index);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern int SetWindowLong(IntPtr window, int index, int value);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    public static void MakePassive(IntPtr window) {
        int style = GetWindowLong(window, ExtendedStyle);
        SetWindowLong(window, ExtendedStyle, style | NoActivate | Transparent | ToolWindow);
        if (!IsPassive(window)) throw new Win32Exception();
    }

    public static bool IsPassive(IntPtr window) {
        int required = NoActivate | Transparent | ToolWindow;
        return (GetWindowLong(window, ExtendedStyle) & required) == required;
    }
}
'@

function Read-Fixture([string]$RelativePath) {
    $path = Join-Path $PSScriptRoot "../test/fixtures/$RelativePath"
    Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -Depth 80
}

function Read-JmaTelegrams {
    $path = Join-Path $PSScriptRoot '../test/fixtures/jma_cancellation_20261016/original_telegrams.zip'
    $archive = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.Name -notlike '*.json') { continue }
            $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8)
            try {
                $reader.ReadToEnd() | ConvertFrom-Json -Depth 80
            } finally {
                $reader.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
}

function New-Sample($Label, $Title, $Body, $Details, [string[]]$Areas, $Font, [switch]$IsWarning) {
    [pscustomobject]@{
        Label = $Label
        Title = $Title
        Body = $Body
        Details = $Details
        Areas = $Areas
        Font = $Font
        IsWarning = [bool]$IsWarning
        Prefectures = [string[]]@()
        Zones = [string[]]@()
    }
}

function Format-QuakeDetails($Magnitude, $Depth, [switch]$Japanese) {
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $style = [Globalization.NumberStyles]::Float
    $number = 0.0
    $parts = @(
        if ([double]::TryParse([string]$Magnitude, $style, $culture, [ref]$number) -and
            [double]::IsFinite($number) -and $number -ge 0) {
            'M' + $number.ToString('0.0', $culture)
        }
        if ([double]::TryParse([string]$Depth, $style, $culture, [ref]$number) -and
            [double]::IsFinite($number) -and $number -ge 0) {
            if ($Japanese -and $number -eq 0) {
                'ごく浅い'
            } else {
                $label = if ($Japanese) { '深さ' } else { '深度' }
                $km = [Math]::Round($number, [MidpointRounding]::AwayFromZero)
                "$label $km km"
            }
        }
    )
    $parts -join '　'
}

function New-WolfxJmaSample($Report, [string]$Label = 'JMA 预报') {
    $areas = @($Report.WarnArea.Chiiki | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $detailText = if (-not $areas.Count) {
        Format-QuakeDetails ($Report.Magunitude ?? $Report.Magnitude) $Report.Depth -Japanese
    }
    New-Sample $Label $Report.Title "$($Report.Hypocenter)で地震" $detailText $areas 'Yu Gothic UI' `
        -IsWarning:($Report.isWarn -eq $true)
}

function New-JmaTelegramSample($Report, [string]$Label) {
    $isWarning = $Report.body.isWarning -eq $true
    $titleText = if ($isWarning) { '緊急地震速報（警報）' } else { $Report.title }
    $bodyText = "$($Report.body.earthquake.hypocenter.name)で地震"
    if ($Report.body.comments.warning.text) { $bodyText += "　$($Report.body.comments.warning.text)" }
    $areas = @($Report.body.intensity.regions | Where-Object {
        $_.name -and (-not $isWarning -or $_.isWarning)
    } | ForEach-Object name)
    $sample = New-Sample $Label $titleText $bodyText '' $areas 'Yu Gothic UI' -IsWarning:$isWarning
    $sample.Prefectures = [string[]]@($Report.body.prefectures | Where-Object name | ForEach-Object name)
    $sample.Zones = [string[]]@($Report.body.zones | Where-Object name | ForEach-Object name)
    $sample
}

function New-CwaSample($Report) {
    New-Sample '台湾 CWA 预警' $Report.titleText "$($Report.hypocenter)發生地震" `
        (Format-QuakeDetails $Report.magnitude $Report.depth) @() 'Microsoft JhengHei UI' `
        -IsWarning:($Report.isWarn -eq $true)
}

function New-GqSample($Report, [string]$Label = 'GlobalQuake（GQ）') {
    New-Sample $Label $Report.titleText "$($Report.hypocenter)发生地震" `
        (Format-QuakeDetails $Report.magnitude $Report.depth) @() 'Microsoft YaHei UI' `
        -IsWarning:($Report.isWarn -eq $true)
}

$mainlandTitle = '中国地震台网地震预警'
$mainlandLabels = [ordered]@{
    cea = 'CEA'
    'cea-pr' = 'CEA-PR'
    sc_eew = '四川'
    cq_eew = '重庆'
    fj_eew = '福建'
}

function New-MainlandSample($Record) {
    # Wolfx's cenc_eew is routed to ceaEew by the application adapter.
    $source = if ($Record.source -eq 'cenc_eew') { 'cea' } else { $Record.source }
    if (-not $mainlandLabels.Contains($source)) { return }

    $location = $Record.raw.HypoCenter ?? $Record.raw.placeName
    $magnitude = $Record.raw.Magunitude ?? $Record.raw.Magnitude
    $detailText = Format-QuakeDetails $magnitude $Record.raw.Depth
    New-Sample "中国地震台网 · $($mainlandLabels[$source])" $mainlandTitle `
        "${location}发生地震" $detailText @() 'Microsoft YaHei UI'
}

$jmaReports = @(Read-JmaTelegrams | Sort-Object @{ Expression = { [DateTimeOffset]$_.reportDateTime } },
    @{ Expression = { [int]$_.serialNo } })
$jmaReplayIndex = 0
$jmaReplayLabel = 'JMA · 10 月 16 日完整回放'
$jmaFirstReportTime = [DateTimeOffset]$jmaReports[0].reportDateTime
$jmaFirstWarning = $jmaReports | Where-Object { $_.body.isWarning -eq $true } | Select-Object -First 1
# The same-event NHK recording switches from the horizontal panel to a side panel after about 88 seconds.
$jmaSubtitleEnd = ([DateTimeOffset]$jmaFirstWarning.reportDateTime - $jmaFirstReportTime).Add(
    [TimeSpan]::FromSeconds(88))
$jmaCancellationLead = [TimeSpan]::FromSeconds(20)
$records = Read-Fixture 'eew_identity_20261013/reports.original.json'
$forecast = ($records | Where-Object { $_.source -eq 'jma_eew' -and $_.api -eq 'wolfx' } | Select-Object -First 1).raw
$kma = ($records | Where-Object { $_.source -eq 'kma_eew' } | Select-Object -First 1).raw
$cwaReports = (Read-Fixture 'history_replay/cwa_1150076_cloud_original_reports.json')[0].reports
$cwaUpdates = @($cwaReports | Select-Object -Skip 1 | ForEach-Object { New-CwaSample $_ })
$mainlandSamples = @(
    foreach ($source in $mainlandLabels.Keys) {
        $record = $records | Where-Object {
            $_.source -eq $source -and ($_.api -ne 'jian')
        } | Select-Object -First 1
        if (-not $record) { throw "Missing original preview sample: $source" }
        New-MainlandSample $record
    }
)
$gq = Read-Fixture 'eew_camera_20261101/gq_jan_mayen_report4.original.json'
$gqReports = (Read-Fixture 'global_quake/captured_report_only_20261018.json').reports
$gqUpdateLabel = 'GlobalQuake · 续报回放'
$sa = ($records | Where-Object source -eq 'sa_eew' | Select-Object -First 1).raw
$sasmex = (Read-Fixture 'sasmex_firestore_20261017.relay.json').Data
$sasmexTitle = if ($sasmex.severity -eq 'Severe') { 'SASMEX 地震警报' } else { 'SASMEX 地震检出' }
$sasmexDetails = "类型：$($sasmex.msgType ?? '未知') · 严重性：$($sasmex.severity ?? '未知')"
# KMA uses zero as the unknown-depth sentinel.
$kmaDepth = if ($kma.depth -ne 0) { $kma.depth }

$samples = @(
    (New-JmaTelegramSample $jmaReports[0] $jmaReplayLabel)
    (New-WolfxJmaSample $forecast)
    (New-CwaSample $cwaReports[0])
    (New-Sample '韩国 KMA 预警' '韩国气象厅地震预警' "$($kma.placename_zh)发生地震" `
        (Format-QuakeDetails $kma.magnitude $kmaDepth) @() 'Microsoft YaHei UI' `
        -IsWarning:($kma.isWarn -eq $true))
) + $mainlandSamples + @(
    (New-GqSample $gq)
    (New-Sample '美国 ShakeAlert（SA）' 'ShakeAlert 地震预警' `
        "$($sa.placeName)发生地震" (Format-QuakeDetails $sa.magnitude $sa.depth) @() 'Microsoft YaHei UI')
    (New-Sample '墨西哥 SASMEX' $sasmexTitle $sasmex.region $sasmexDetails @() 'Microsoft YaHei UI' `
        -IsWarning:($sasmex.severity -eq 'Severe'))
    (New-GqSample $gqReports[2] $gqUpdateLabel)
)
if ($InitialSample -lt 0 -or $InitialSample -ge $samples.Count) {
    throw "InitialSample must be between 0 and $($samples.Count - 1)."
}

$gqUpdateIndex = $samples.Count - 1
$sampleUpdates = @{
    2 = $cwaUpdates
    $gqUpdateIndex = @((New-GqSample $gqReports[3] $gqUpdateLabel))
}

function Format-InformationTime([DateTimeOffset]$Origin, [switch]$Japanese) {
    $clock = $Origin.ToLocalTime()
    $period = if ($clock.Hour -lt 12) {
        if ($Japanese) { '午前' } else { '上午' }
    } else {
        if ($Japanese) { '午後' } else { '下午' }
    }
    $hour = $clock.Hour % 12
    if ($Japanese) { return "${period}${hour}時$($clock.Minute)分ごろ" }
    if ($hour -eq 0) { $hour = 12 }
    "${period}${hour}时$($clock.Minute)分左右"
}

function New-InformationPage([string]$Text, [string]$SecondLine, [string]$Intensity) {
    [pscustomobject]@{ Text = $Text; SecondLine = $SecondLine; Intensity = $Intensity }
}

function New-JmaInformation($Event, $Report) {
    $place = if ($null -ne $Report.hypocenter) { $Event.hypocenters[$Report.hypocenter] }
    $observation = $Report.observation
    $intensity = ([string]$observation.maxIntensity).Replace('-', '弱').Replace('+', '強')
    $region = if ($place) { $place.name } else {
        @($observation.prefs | Where-Object int -eq $observation.maxIntensity | ForEach-Object name) -join '・'
    }
    $time = Format-InformationTime ($Report.originTime ?? $Report.arrivalTime) -Japanese
    $headline = if ($intensity) { "${time}${region}で震度${intensity}" } else { "${time}${region}で地震" }
    $tsunami = ($Report.comments.forecast -split "`n" | Where-Object { $_.Contains('津波') } | Select-Object -First 1)
    $pages = @(
        New-InformationPage $headline $tsunami
        foreach ($group in ($observation.areas | Group-Object int | Sort-Object {
            ([string]$_.Name).Replace('-', '0').Replace('+', '1').PadRight(2, '0')
        } -Descending)) {
            $label = $group.Name.Replace('-', '弱').Replace('+', '強')
            $names = @($group.Group | ForEach-Object name)
            for ($index = 0; $index -lt $names.Count; $index += 3) {
                New-InformationPage (($names | Select-Object -Skip $index -First 3) -join '　') '' "震度$label"
            }
        }
        if ($place) {
            $depth = if ($null -ne $place.depth) { "深さ$($place.depth)キロ" }
            $mag = if ($null -ne $Report.magnitude) { "マグニチュード$($Report.magnitude)" }
            New-InformationPage "震源は$($place.name)" (@($depth, $mag) | Where-Object { $_ } | Join-String -Separator '　')
        }
    )
    New-Information 'JMA' $Event.eventId $Report.issuedAt $pages
}

function New-Information([string]$Source, [string]$Id, [DateTimeOffset]$Revision, $Pages) {
    [pscustomobject]@{ Key = "$Source|$Id"; Source = $Source; Revision = $Revision; Pages = @($Pages) }
}

$cwaDetail = Read-Fixture 'source_estimation/cwa_report_115068_original.json'
$cwaTime = [DateTimeOffset]::FromUnixTimeMilliseconds($cwaDetail.time)
$cwaPlaces = [regex]::Match($cwaDetail.loc, '\((位於.+)\)').Groups[1].Value -replace '^位於', ''
$cwaAreas = @($cwaDetail.list.PSObject.Properties | Where-Object { $_.Value.int -gt 0 })
$cwaMax = ($cwaAreas | ForEach-Object { $_.Value.int } | Measure-Object -Maximum).Maximum
$cwaPages = @(
    New-InformationPage "$(Format-InformationTime $cwaTime)$cwaPlaces發生地震" "最大震度$cwaMax"
    foreach ($group in ($cwaAreas | Group-Object { $_.Value.int } | Sort-Object { [int]$_.Name } -Descending)) {
        New-InformationPage (($group.Group.Name) -join '　') '' "震度$($group.Name)"
    }
    New-InformationPage $cwaDetail.loc (Format-QuakeDetails $cwaDetail.mag $cwaDetail.depth)
)
$jmaDetail = (Read-Fixture 'wolfx_jma_detail_20261119/jma_earthquake_detail.original.json').events |
    Where-Object eventId -eq '20261119022225' | Select-Object -First 1
$jmaObserved = New-JmaInformation $jmaDetail ($jmaDetail.reports | Where-Object product -eq 'VXSE51')
$jmaDetailed = New-JmaInformation $jmaDetail ($jmaDetail.reports | Where-Object product -eq 'VXSE53')
$cencDetail = (Read-Fixture 'cenc_history_20261014/wolfx.original.json').PSObject.Properties.Value |
    Where-Object EventID -eq 'CC.20261013162547.1' | Select-Object -First 1
$cencPages = @(
    New-InformationPage "$(Format-InformationTime "$($cencDetail.time) +08:00")$($cencDetail.placeName)发生地震"
    New-InformationPage "震源地为$($cencDetail.placeName)" (Format-QuakeDetails $cencDetail.magnitude $cencDetail.depth)
)
$usgsDetail = Read-Fixture 'usgs_shakemap/us6000u0xi.detail.original.geojson'
$usgsTime = [DateTimeOffset]::FromUnixTimeMilliseconds($usgsDetail.properties.time)
$usgsPages = @(
    New-InformationPage "$(Format-InformationTime $usgsTime)发生地震" $usgsDetail.properties.place
    New-InformationPage $usgsDetail.properties.place (Format-QuakeDetails $usgsDetail.properties.mag $usgsDetail.geometry.coordinates[2])
)
$informationSamples = @(
    (New-Information 'CWA' $cwaDetail.id $cwaTime $cwaPages)
    $jmaObserved
    (New-Information 'CENC' $cencDetail.EventID "$($cencDetail.ReportTime) +08:00" $cencPages)
    (New-Information 'USGS' $usgsDetail.id ([DateTimeOffset]::FromUnixTimeMilliseconds($usgsDetail.properties.updated)) $usgsPages)
)

function New-Text($Size, $Color) {
    $text = [Windows.Controls.TextBlock]::new()
    $text.FontSize = $Size
    $text.FontWeight = [Windows.FontWeights]::SemiBold
    $text.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    $text.TextAlignment = 'Center'
    $text.TextWrapping = 'Wrap'
    $text
}

function New-Background($Color, $Child, $Padding) {
    $border = [Windows.Controls.Border]::new()
    $border.Background = [Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    $border.Padding = $Padding
    $border.Child = $Child
    $border
}

$workArea = [Windows.SystemParameters]::WorkArea
$overlayWidth = [Math]::Min(660, $workArea.Width - 32)
$overlay = [Windows.Window]::new()
$overlay.Title = 'RhythmQuake EEW Subtitle Preview'
$overlay.Width = $overlayWidth
$overlay.Left = $workArea.Left + ($workArea.Width - $overlayWidth) / 2
$overlay.Top = $workArea.Top + 38
$overlay.SizeToContent = 'Height'
$overlay.ResizeMode = 'NoResize'
$overlay.WindowStyle = 'None'
$overlay.AllowsTransparency = $true
$overlay.Background = [Windows.Media.Brushes]::Transparent
$overlay.Topmost = $true
$overlay.ShowActivated = $false
$overlay.ShowInTaskbar = $false
$overlay.Add_SourceInitialized({
    $handle = [Windows.Interop.WindowInteropHelper]::new($overlay).Handle
    [SubtitlePreviewWindow]::MakePassive($handle)
})

$informationOverlay = [Windows.Window]::new()
$informationOverlay.Title = 'RhythmQuake Earthquake Information Preview'
$informationOverlay.Width = $overlayWidth
$informationOverlay.Left = $overlay.Left
$informationOverlay.SizeToContent = 'Height'
$informationOverlay.ResizeMode = 'NoResize'
$informationOverlay.WindowStyle = 'None'
$informationOverlay.AllowsTransparency = $true
$informationOverlay.Background = [Windows.Media.Brushes]::Transparent
$informationOverlay.Topmost = $true
$informationOverlay.ShowActivated = $false
$informationOverlay.ShowInTaskbar = $false
$informationOverlay.Add_SourceInitialized({
    $handle = [Windows.Interop.WindowInteropHelper]::new($informationOverlay).Handle
    [SubtitlePreviewWindow]::MakePassive($handle)
})
$informationSurface = [Windows.Controls.StackPanel]::new()
$informationSurface.Margin = [Windows.Thickness]::new(8, 4, 8, 4)
$informationOverlay.Content = $informationSurface
$informationPageInterval = [TimeSpan]::FromSeconds(4)
$informationBelowEew = 202

function New-OutlinedInformationText([string]$Text, $Typeface, [double]$Width) {
    $formatted = [Windows.Media.FormattedText]::new(
        $Text, [Globalization.CultureInfo]::CurrentUICulture, [Windows.FlowDirection]::LeftToRight,
        $Typeface, 23, [Windows.Media.Brushes]::White,
        [Windows.Media.VisualTreeHelper]::GetDpi($informationOverlay).PixelsPerDip)
    $formatted.MaxTextWidth = $Width
    $geometry = $formatted.BuildGeometry([Windows.Point]::new(0, 0))
    $drawing = [Windows.Media.DrawingGroup]::new()
    $stroke = [Windows.Media.Pen]::new([Windows.Media.Brushes]::Black, 4)
    $stroke.LineJoin = 'Round'
    [void]$drawing.Children.Add([Windows.Media.GeometryDrawing]::new($null, $stroke, $geometry))
    [void]$drawing.Children.Add([Windows.Media.GeometryDrawing]::new([Windows.Media.Brushes]::White, $null, $geometry))
    $drawing.Freeze()
    $textImage = [Windows.Controls.Image]::new()
    $textImage.Source = [Windows.Media.DrawingImage]::new($drawing)
    $textImage.Stretch = 'None'
    $textImage.Margin = [Windows.Thickness]::new(0, 3, 0, 3)
    [Windows.Automation.AutomationProperties]::SetName($textImage, $Text)
    $textImage
}

$surface = [Windows.Controls.StackPanel]::new()
$overlay.Content = $surface
$firstReportBlinkCount = 3
$updateBlinkCount = 2
$blinkVisibleMs = 600
$blinkHiddenMs = 550
$blinkCycleMs = $blinkVisibleMs + $blinkHiddenMs
$firstAreaPageMs = $firstReportBlinkCount * $blinkCycleMs + $blinkVisibleMs
$areaPageMs = 2800
$firstReportBlink = [Windows.Media.Animation.DoubleAnimationUsingKeyFrames]::new()
$firstReportBlink.FillBehavior = 'Stop'
for ($cycle = 0; $cycle -lt $firstReportBlinkCount; $cycle++) {
    $hideAt = [TimeSpan]::FromMilliseconds($cycle * $blinkCycleMs + $blinkVisibleMs)
    $showAt = [TimeSpan]::FromMilliseconds(($cycle + 1) * $blinkCycleMs)
    [void]$firstReportBlink.KeyFrames.Add([Windows.Media.Animation.DiscreteDoubleKeyFrame]::new(
        0, [Windows.Media.Animation.KeyTime]::FromTimeSpan($hideAt)
    ))
    [void]$firstReportBlink.KeyFrames.Add([Windows.Media.Animation.DiscreteDoubleKeyFrame]::new(
        1, [Windows.Media.Animation.KeyTime]::FromTimeSpan($showAt)
    ))
}
$updateBlink = [Windows.Media.Animation.DoubleAnimationUsingKeyFrames]::new()
$updateBlink.FillBehavior = 'Stop'
for ($cycle = 0; $cycle -lt $updateBlinkCount; $cycle++) {
    $hideAt = [TimeSpan]::FromMilliseconds($cycle * $blinkCycleMs)
    $showAt = $hideAt + [TimeSpan]::FromMilliseconds($blinkHiddenMs)
    [void]$updateBlink.KeyFrames.Add([Windows.Media.Animation.DiscreteDoubleKeyFrame]::new(
        0, [Windows.Media.Animation.KeyTime]::FromTimeSpan($hideAt)
    ))
    [void]$updateBlink.KeyFrames.Add([Windows.Media.Animation.DiscreteDoubleKeyFrame]::new(
        1, [Windows.Media.Animation.KeyTime]::FromTimeSpan($showAt)
    ))
}
$title = New-Text 28 '#FFFFFF'
$title.FontWeight = [Windows.FontWeights]::Bold
$titleRow = [Windows.Controls.Grid]::new()
$titleSurface = New-Background '#DB1017' $title ([Windows.Thickness]::new(16, 4, 16, 5))
$titleSurface.HorizontalAlignment = 'Center'
[void]$titleRow.Children.Add($titleSurface)
$testLabel = New-Text 11 '#FFFFFF'
$testLabel.FontFamily = [Windows.Media.FontFamily]::new('Microsoft YaHei UI')
$testLabel.Text = '显示测试'
$testBadge = New-Background '#3A3A3A' $testLabel ([Windows.Thickness]::new(6, 3, 6, 3))
$testBadge.HorizontalAlignment = 'Right'
$testBadge.VerticalAlignment = 'Center'
$testBadge.Margin = [Windows.Thickness]::new(0, 0, 8, 0)
[void]$titleRow.Children.Add($testBadge)
[void]$surface.Children.Add($titleRow)

$body = New-Text 23 '#FFFFFF'
$bodySurface = New-Background 'Transparent' $body ([Windows.Thickness]::new(16, 7, 16, 7))
$bodySurface.Margin = [Windows.Thickness]::new(0, 4, 0, 0)
[void]$surface.Children.Add($bodySurface)
$details = New-Text 20 '#FFFFFF'
$detailPadding = [Windows.Thickness]::new(16, 7, 16, 7)
$detailSurface = New-Background 'Transparent' $details $detailPadding
[void]$surface.Children.Add($detailSurface)
$areaBoxWidth = [Math]::Min(410, $overlayWidth)
$areaTextWidth = $areaBoxWidth - $detailPadding.Left - $detailPadding.Right
$areaLineHeight = 27
$areaLinesPerPage = 3

# JMA area-name table, appendix 4. Keep the Hokkaido divisions and Niigata visible.
# https://www.data.jma.go.jp/suishin/catalogue/format/SvdEto_KinkyuJishintest.1_format.pdf
$jmaZonePrefectures = @{
    '東北' = @('青森', '岩手', '宮城', '秋田', '山形', '福島')
    '関東' = @('茨城', '栃木', '群馬', '埼玉', '千葉', '東京', '神奈川')
    '北陸' = @('富山', '石川', '福井')
    '甲信' = @('山梨', '長野')
    '東海' = @('岐阜', '静岡', '愛知', '三重')
    '近畿' = @('滋賀', '京都', '大阪', '兵庫', '奈良', '和歌山')
    '中国' = @('鳥取', '島根', '岡山', '広島', '山口')
    '四国' = @('徳島', '香川', '愛媛', '高知')
    '九州' = @('福岡', '佐賀', '長崎', '熊本', '大分', '宮崎', '鹿児島')
    '沖縄' = @('沖縄本島', '大東島', '宮古島', '八重山')
}

function Split-AreaPages([string[]]$Areas, [string]$Font) {
    if (-not $Areas.Count) { return }

    $measure = New-Text $details.FontSize '#FFFFFF'
    $measure.FontFamily = [Windows.Media.FontFamily]::new($Font)
    $measure.TextWrapping = 'NoWrap'
    $room = [Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity)
    $page = [Collections.Generic.List[string]]::new()
    $line = ''
    foreach ($area in $Areas) {
        $candidate = if ($line) { "$line　$area" } else { $area }
        $measure.Text = $candidate
        $measure.Measure($room)
        if ($line -and $measure.DesiredSize.Width -gt $areaTextWidth) {
            $page.Add($line)
            if ($page.Count -eq $areaLinesPerPage) {
                $page -join "`n"
                $page.Clear()
            }
            $line = $area
        } else {
            $line = $candidate
        }
    }
    $page.Add($line)
    $page -join "`n"
}

function Get-AreaPages($Sample) {
    if (-not $Sample.Prefectures.Count) {
        $areas = if ($Sample.Areas.Count) { $Sample.Areas } else { $Sample.Zones }
        Split-AreaPages $areas $Sample.Font
        return
    }

    $pages = @(Split-AreaPages $Sample.Prefectures $Sample.Font)
    if ($pages.Count -le 1 -or -not $Sample.Zones.Count) {
        $pages
        return
    }

    $zoneByPrefecture = @{}
    foreach ($zone in $Sample.Zones) {
        $members = @($Sample.Prefectures | Where-Object { $_ -cin $jmaZonePrefectures[$zone] })
        if ($members.Count -lt 2) { continue }
        foreach ($prefecture in $members) { $zoneByPrefecture[$prefecture] = $zone }
    }
    $displayAreas = @(
        foreach ($prefecture in $Sample.Prefectures) { $zoneByPrefecture[$prefecture] ?? $prefecture }
    ) | Select-Object -Unique
    Split-AreaPages $displayAreas $Sample.Font
}

function Show-Subtitle($Sample, [switch]$ShowContent, [string]$AreaPage) {
    $font = [Windows.Media.FontFamily]::new($Sample.Font)
    $title.FontFamily = $font
    $body.FontFamily = $font
    $details.FontFamily = $font
    $title.Text = $Sample.Title
    $body.Text = if ($ShowContent) { $Sample.Body } else { '' }
    $hasAreaText = $ShowContent -and $AreaPage
    $detailSurface.Width = if ($hasAreaText) { $areaBoxWidth } else { [double]::NaN }
    $details.Height = if ($hasAreaText) { $areaLineHeight * $areaLinesPerPage } else { [double]::NaN }
    $details.LineHeight = if ($hasAreaText) { $areaLineHeight } else { [double]::NaN }
    $details.LineStackingStrategy = if ($hasAreaText) { 'BlockLineHeight' } else { 'MaxHeight' }
    $details.TextAlignment = if ($hasAreaText) { 'Left' } else { 'Center' }
    $details.TextWrapping = if ($hasAreaText) { 'NoWrap' } else { 'Wrap' }
    $details.Text = if (-not $ShowContent) { '' } elseif ($hasAreaText) { $AreaPage } else { $Sample.Details ?? '' }
    $bodySurface.Visibility = if ($body.Text) { 'Visible' } else { 'Collapsed' }
    $detailSurface.Visibility = if ($details.Text) { 'Visible' } else { 'Collapsed' }
}

function Start-UpdateBlink($Target) {
    $clock = [Windows.Media.Animation.AnimationClock]$updateBlink.CreateClock([bool]$CheckDirectory)
    $Target.ApplyAnimationClock([Windows.UIElement]::OpacityProperty, $clock)
    if ($CheckDirectory) {
        $clock.Controller.Pause()
        $script:checkedUpdateClocks[$Target] = $clock
    }
}

function Reset-UpdateBlinks {
    foreach ($target in @($titleSurface, $bodySurface, $detailSurface)) {
        $target.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    }
}

$app = [Windows.Application]::new()
$app.ShutdownMode = 'OnExplicitShutdown'

function Save-PreviewFrame([string]$FileName, $Window = $overlay, $Visual = $surface) {
    $Window.UpdateLayout()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(
        [int][Math]::Ceiling($Visual.ActualWidth), [int][Math]::Ceiling($Visual.ActualHeight),
        96, 96, [Windows.Media.PixelFormats]::Pbgra32
    )
    $bitmap.Render($Visual)
    $png = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $png.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $file = [IO.File]::Create((Join-Path $CheckDirectory $FileName))
    try { $png.Save($file) } finally { $file.Dispose() }
}

function Test-PreviewFrames {
    [void][IO.Directory]::CreateDirectory($CheckDirectory)
    Show-Subtitle $samples[0]
    $foreground = [SubtitlePreviewWindow]::GetForegroundWindow()
    $overlay.Show()
    $handle = [Windows.Interop.WindowInteropHelper]::new($overlay).Handle
    if (-not [SubtitlePreviewWindow]::IsPassive($handle) -or -not $overlay.Topmost -or
        [SubtitlePreviewWindow]::GetForegroundWindow() -ne $foreground) {
        throw 'Subtitle window is not passive and topmost.'
    }
    if ($bodySurface.Background.Color.A -ne 0 -or $detailSurface.Background.Color.A -ne 0 -or
        $titleSurface.Background.Color.A -ne 255) {
        throw 'The subtitle body must be transparent and the red title must be opaque.'
    }
    $wolfxPages = @(Get-AreaPages $wolfxSample)
    if (($wolfxPages -join "`n").Replace("`n", '　') -cne ($wolfxWarning.WarnArea.Chiiki -join '　') -or
        $samples[1].Details -cne 'M3.3　深さ 10 km') {
        throw 'Wolfx JMA must use every upstream region when present, or magnitude and depth otherwise.'
    }
    $kmaSample = $samples[3]
    if ($kmaSample.Title -cne '韩国气象厅地震预警' -or
        -not $kmaSample.Body.StartsWith($kma.placename_zh, [StringComparison]::Ordinal) -or
        $kmaSample.Details -cne 'M5.3' -or
        ($kmaSample.Title + $kmaSample.Body + $kmaSample.Details) -match '[\uAC00-\uD7A3]') {
        throw 'KMA preview strings are not fully localized.'
    }
    if ($mainlandSamples.Count -ne $mainlandLabels.Count -or
        @($mainlandSamples | Where-Object Title -CNE $mainlandTitle).Count -or
        @($records | Where-Object source -eq 'icl' | ForEach-Object { New-MainlandSample $_ }).Count) {
        throw 'Mainland subtitles must share the CENC title and exclude ICL.'
    }
    $wolfxCencRecord = $records | Where-Object source -eq 'cenc_eew' | Select-Object -First 1
    $wolfxCencSample = New-MainlandSample $wolfxCencRecord
    if ($wolfxCencSample.Label -cne '中国地震台网 · CEA' -or
        $wolfxCencSample.Title -cne $mainlandTitle -or
        $wolfxCencSample.Details -cne 'M4.9' -or
        @($mainlandSamples | Where-Object Label -like '* · CENC').Count) {
        throw 'Wolfx CENC EEW must use the CEA subtitle entry.'
    }
    if ($samples[-4].Title -cne $gq.titleText -or $samples[-4].Details -cne 'M4.5　深度 10 km' -or
        $samples[-3].Details -cne 'M4.2　深度 28 km' -or
        $samples[-2].Details -cne '类型：Alert · 严重性：Minor') {
        throw 'International samples must use only the fields reported by their own feeds.'
    }
    $broadcastPage = @(Get-AreaPages (New-JmaTelegramSample $jmaReports[34] $jmaReplayLabel))
    $broadcastNames = ($broadcastPage -join "`n") -split '[\n　]'
    $expectedNames = @(
        '北海道道東', '北海道道北', '北海道道央', '北海道道南', '東北',
        '関東', '新潟', '北陸', '甲信', '東海', '伊豆諸島'
    )
    if ($broadcastPage.Count -ne 1 -or (($broadcastNames | Sort-Object) -join '|') -cne
        (($expectedNames | Sort-Object) -join '|')) {
        throw 'The broad warning must use the official prefecture and regional names in one page.'
    }
    foreach ($index in 0..($samples.Count - 1)) {
        $sample = $samples[$index]
        $pages = @(Get-AreaPages $sample)
        if ($sample.Areas.Count -and -not $sample.Prefectures.Count -and
            ($pages -join "`n").Replace("`n", '　') -cne ($sample.Areas -join '　')) {
            throw "Area pagination changed the original region list of sample $index."
        }
        foreach ($step in 0..1) {
            Show-Subtitle $sample -ShowContent:($step -eq 1) -AreaPage $pages[0]
            $overlay.UpdateLayout()
            if ($title.Text -cne $samples[$index].Title -or
                ($bodySurface.Visibility -eq 'Visible') -ne ($step -eq 1) -or
                ($detailSurface.Visibility -eq 'Visible') -ne ($step -eq 1 -and ($sample.Areas.Count -or $sample.Details))) {
                throw "Unexpected subtitle layout at sample $index, step $step. Title: $($title.Text), body: $($bodySurface.Visibility), details: $($detailSurface.Visibility), area pages: $($pages.Count)."
            }
            if ($step -eq 1 -and $sample.Areas.Count) {
                if ($details.Text -cne $pages[0] -or
                    $detailSurface.ActualWidth -ne $areaBoxWidth -or
                    $details.ActualHeight -ne $areaLineHeight * $areaLinesPerPage -or
                    $overlay.Top + $surface.ActualHeight -gt $workArea.Bottom) {
                    throw "Sample $index does not fit the JMA area box."
                }
                foreach ($page in $pages) {
                    $lines = $page -split "`n"
                    $measure = New-Text $details.FontSize '#FFFFFF'
                    $measure.FontFamily = $details.FontFamily
                    $measure.TextWrapping = 'NoWrap'
                    $measure.Text = $page
                    $measure.Measure([Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
                    if ($lines.Count -gt $areaLinesPerPage -or $measure.DesiredSize.Width -gt $areaTextWidth) {
                        throw "Sample $index contains a page exceeding the JMA area box."
                    }
                }
            }
            Save-PreviewFrame "sample-$index-step-$step.png"
        }
    }
    "Verified $($samples.Count) EEW samples, $($samples.Count * 2) frames, transparent subtitle bodies, a shared mainland title, ICL exclusion, and the three-line JMA area box."
}

$control = [Windows.Window]::new()
$control.Title = 'RhythmQuake 字幕显示测试'
$control.Width = 365
$control.SizeToContent = 'Height'
$control.ResizeMode = 'NoResize'
$control.Left = $workArea.Left + 24
$control.Top = $workArea.Top + 185
$control.Background = [Windows.Media.Brushes]::White
$control.Topmost = $true
$control.Add_Deactivated({ $control.Topmost = $false })
$controls = [Windows.Controls.StackPanel]::new()
$controls.Margin = [Windows.Thickness]::new(18)
$control.Content = $controls
$description = New-Text 15 '#222222'
$description.Text = '选择预警样例 · 字幕显示在屏幕顶部'
[void]$controls.Children.Add($description)

$select = [Windows.Controls.ComboBox]::new()
$select.FontSize = 15
$select.Margin = [Windows.Thickness]::new(0, 12, 0, 10)
$select.ItemsSource = @($samples.Label)
$select.SelectedIndex = $InitialSample
[void]$controls.Children.Add($select)

$buttons = [Windows.Controls.Primitives.UniformGrid]::new()
$buttons.Columns = 2
[void]$controls.Children.Add($buttons)
$replay = [Windows.Controls.Button]::new()
$replay.Content = '重播开场'
$replay.Margin = [Windows.Thickness]::new(0, 0, 4, 0)
$replay.Padding = [Windows.Thickness]::new(8)
[void]$buttons.Children.Add($replay)
$pause = [Windows.Controls.Button]::new()
$pause.Content = '暂停'
$pause.Margin = [Windows.Thickness]::new(4, 0, 0, 0)
$pause.Padding = [Windows.Thickness]::new(8)
[void]$buttons.Children.Add($pause)
$update = [Windows.Controls.Button]::new()
$update.Content = '更新一报'
$update.Margin = [Windows.Thickness]::new(0, 8, 4, 0)
$update.Padding = [Windows.Thickness]::new(8)
[void]$buttons.Children.Add($update)
$end = [Windows.Controls.Button]::new()
$end.Content = '结束 EEW'
$end.Margin = [Windows.Thickness]::new(4, 8, 0, 0)
$end.Padding = [Windows.Thickness]::new(8)
[void]$buttons.Children.Add($end)

$informationSelect = [Windows.Controls.ComboBox]::new()
$informationSelect.FontSize = 15
$informationSelect.Margin = [Windows.Thickness]::new(0, 14, 0, 8)
$informationSelect.ItemsSource = @($informationSamples | ForEach-Object { "$($_.Source) · 地震情报" })
$informationSelect.SelectedIndex = 2
[void]$controls.Children.Add($informationSelect)
$informationButtons = [Windows.Controls.Primitives.UniformGrid]::new()
$informationButtons.Columns = 2
[void]$controls.Children.Add($informationButtons)
$playInformation = [Windows.Controls.Button]::new()
$playInformation.Content = '播放情报'
$playInformation.Padding = [Windows.Thickness]::new(8)
$playInformation.Margin = [Windows.Thickness]::new(0, 0, 4, 0)
[void]$informationButtons.Children.Add($playInformation)
$updateInformation = [Windows.Controls.Button]::new()
$updateInformation.Content = '更新情报'
$updateInformation.Padding = [Windows.Thickness]::new(8)
$updateInformation.Margin = [Windows.Thickness]::new(4, 0, 0, 0)
$updateInformation.IsEnabled = $false
[void]$informationButtons.Children.Add($updateInformation)

$informationTimer = [Windows.Threading.DispatcherTimer]::new()
$informationTimer.Interval = $informationPageInterval
$script:currentInformation = $null
$script:informationPage = 0
$script:pendingInformation = [Collections.Specialized.OrderedDictionary]::new()
$script:informationVersions = @{}

function Show-InformationPage {
    $page = $script:currentInformation.Pages[$script:informationPage]
    $family = if ($script:currentInformation.Source -eq 'JMA') { 'Yu Gothic UI' }
        elseif ($script:currentInformation.Source -eq 'CWA') { 'Microsoft JhengHei UI' }
        else { 'Microsoft YaHei UI' }
    $typeface = [Windows.Media.Typeface]::new(
        [Windows.Media.FontFamily]::new($family), [Windows.FontStyles]::Normal,
        [Windows.FontWeights]::SemiBold, [Windows.FontStretches]::Normal)
    $available = $overlayWidth - 28
    $informationSurface.Children.Clear()
    if ($page.Intensity) {
        $row = [Windows.Controls.StackPanel]::new()
        $row.Orientation = 'Horizontal'
        $row.HorizontalAlignment = 'Center'
        $label = New-OutlinedInformationText $page.Intensity $typeface 105
        $badge = New-Background '#08862D' $label ([Windows.Thickness]::new(8, 0, 8, 0))
        $badge.VerticalAlignment = 'Top'
        $badge.Margin = [Windows.Thickness]::new(0, 0, 8, 0)
        [void]$row.Children.Add($badge)
        [void]$row.Children.Add((New-OutlinedInformationText $page.Text $typeface ($available - 130)))
        [void]$informationSurface.Children.Add($row)
    } else {
        [void]$informationSurface.Children.Add((New-OutlinedInformationText $page.Text $typeface $available))
    }
    if ($page.SecondLine) {
        [void]$informationSurface.Children.Add((New-OutlinedInformationText $page.SecondLine $typeface $available))
    }
}

function Start-Information($Bulletin) {
    $script:currentInformation = $Bulletin
    $script:informationPage = 0
    $informationOverlay.Top = $overlay.Top + $(if ($overlay.IsVisible) { $informationBelowEew } else { 0 })
    Show-InformationPage
    if (-not $informationOverlay.IsVisible) { $informationOverlay.Show() }
    $updateInformation.IsEnabled = $Bulletin.Key -eq $jmaObserved.Key -and $Bulletin.Revision -lt $jmaDetailed.Revision
    $informationTimer.Start()
}

function Receive-Information($Bulletin, [switch]$Replay) {
    if ($Bulletin.Source -cnotin $informationSamples.Source -or $Bulletin.Pages.Count -eq 0) { return }
    $known = $script:informationVersions[$Bulletin.Key]
    if ($known -and $Bulletin.Revision -le $known -and (-not $Replay -or $script:currentInformation)) { return }
    $script:informationVersions[$Bulletin.Key] = $Bulletin.Revision

    if (-not $script:currentInformation) {
        Start-Information $Bulletin
    } elseif ($script:currentInformation.Key -eq $Bulletin.Key) {
        $script:currentInformation = $Bulletin
        $script:informationPage = [Math]::Min($script:informationPage, $Bulletin.Pages.Count - 1)
        Show-InformationPage
        $updateInformation.IsEnabled = $false
    } else {
        $script:pendingInformation[$Bulletin.Key] = $Bulletin
    }
}

function Advance-Information {
    $informationTimer.Stop()
    $script:informationPage++
    if ($script:informationPage -lt $script:currentInformation.Pages.Count) {
        Show-InformationPage
        $informationTimer.Start()
    } elseif ($script:pendingInformation.Count) {
        $next = $script:pendingInformation[0]
        $script:pendingInformation.RemoveAt(0)
        Start-Information $next
    } else {
        $script:currentInformation = $null
        $updateInformation.IsEnabled = $false
        $informationOverlay.Hide()
    }
}

$informationTimer.Add_Tick({ Advance-Information })
$playInformation.Add_Click({ Receive-Information $informationSamples[$informationSelect.SelectedIndex] -Replay })
$updateInformation.Add_Click({ Receive-Information $jmaDetailed })

$timer = [Windows.Threading.DispatcherTimer]::new()
$jmaReplayTimer = [Windows.Threading.DispatcherTimer]::new()
$jmaReplayClock = [Diagnostics.Stopwatch]::new()
$script:activeSample = $null
$script:areaPages = @()
$script:areaPageIndex = 0
$script:opening = $false
$script:firstReportBlinkPending = $false
$script:paused = $false
$script:resumeAreaTimer = $false
$script:nextUpdate = 0
$script:nextJmaReport = 1
$script:jmaSubtitleEnded = $false

function Schedule-Preview([int]$DelayMs) {
    $timer.Interval = [TimeSpan]::FromMilliseconds($DelayMs)
    $pause.IsEnabled = $true
    if (-not $script:paused) { $timer.Start() }
}

function Get-JmaReplayOffset($Report) {
    $offset = [DateTimeOffset]$Report.reportDateTime - $jmaFirstReportTime
    if ($Report.body.isCanceled -eq $true) {
        return $offset.Subtract($jmaCancellationLead)
    }
    $offset
}

function Schedule-JmaReplay {
    $offset = Get-JmaReplayOffset $jmaReports[$script:nextJmaReport]
    if (-not $script:jmaSubtitleEnded -and $jmaSubtitleEnd -lt $offset) {
        $offset = $jmaSubtitleEnd
    }
    $remainingMs = [Math]::Ceiling($offset.TotalMilliseconds - $jmaReplayClock.Elapsed.TotalMilliseconds)
    $jmaReplayTimer.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(1, $remainingMs))
    $jmaReplayTimer.Start()
    $pause.IsEnabled = $true
}

function Start-Preview($Sample = $samples[$select.SelectedIndex]) {
    $timer.Stop()
    $jmaReplayTimer.Stop()
    $jmaReplayClock.Reset()
    $surface.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    Reset-UpdateBlinks
    $script:activeSample = $Sample
    $script:areaPages = @(Get-AreaPages $script:activeSample)
    $script:areaPageIndex = 0
    $script:opening = $true
    $script:firstReportBlinkPending = $true
    $script:paused = $false
    $script:nextUpdate = 0
    $script:nextJmaReport = 1
    $script:jmaSubtitleEnded = $false
    $isJmaReplay = $select.SelectedIndex -eq $jmaReplayIndex
    $pause.Content = '暂停'
    $update.Content = if ($isJmaReplay) { "第 $($jmaReports[0].serialNo) 报 · 1/$($jmaReports.Count)" } else { '更新一报' }
    $update.IsEnabled = $false
    $update.ToolTip = if ($isJmaReplay) {
        '按原始发布时间自动播放，预览撤销提前 20 秒'
    } elseif ($select.SelectedIndex -eq $gqUpdateIndex) {
        "同一事件原始报文 · $($gqReports[2].reportNumText) → $($gqReports[3].reportNumText)"
    } elseif ($sampleUpdates.ContainsKey($select.SelectedIndex)) {
        '播放台湾 CWA 样例的原始续报'
    }
    $end.IsEnabled = $true
    Show-Subtitle $script:activeSample
    if (-not $overlay.IsVisible) { $overlay.Show() }
    if ($informationOverlay.IsVisible -and $informationOverlay.Top -eq $overlay.Top) {
        $informationOverlay.Top = $overlay.Top + $informationBelowEew
    }
    Schedule-Preview 500
    if ($isJmaReplay) {
        $jmaReplayClock.Start()
        Schedule-JmaReplay
    }
}

function Advance-Preview {
    $timer.Stop()
    $sample = $script:activeSample
    if (-not $sample) { return }
    $pause.IsEnabled = $jmaReplayTimer.IsEnabled
    $delayMs = $areaPageMs
    if ($script:opening) {
        $script:opening = $false
        Show-Subtitle $sample -ShowContent -AreaPage $script:areaPages[$script:areaPageIndex]
        $update.IsEnabled = $script:nextUpdate -lt $sampleUpdates[$select.SelectedIndex].Count
        if ($script:firstReportBlinkPending) {
            $script:firstReportBlinkPending = $false
            $surface.BeginAnimation([Windows.UIElement]::OpacityProperty, $firstReportBlink)
            $delayMs = $firstAreaPageMs
        }
    } elseif ($script:areaPages.Count -gt 1) {
        $script:areaPageIndex = ($script:areaPageIndex + 1) % $script:areaPages.Count
        $details.Text = $script:areaPages[$script:areaPageIndex]
    }
    if ($script:areaPages.Count -gt 1) {
        Schedule-Preview $delayMs
    }
}

function Update-Preview($Sample) {
    $previous = $script:activeSample
    if (-not $previous) { return }

    $titleChanged = $previous.Title -cne $Sample.Title
    $bodyChanged = $previous.Body -cne $Sample.Body
    $detailChanged = $previous.Details -cne $Sample.Details
    $warningChanged = $previous.IsWarning -ne $Sample.IsWarning
    $newAreas = @($Sample.Areas | Where-Object { $_ -cnotin $previous.Areas })
    $newPrefectures = @($Sample.Prefectures | Where-Object { $_ -cnotin $previous.Prefectures })
    $newZones = @($Sample.Zones | Where-Object { $_ -cnotin $previous.Zones })
    $areasChanged = $newAreas.Count -or $previous.Areas.Count -ne $Sample.Areas.Count -or
        $newPrefectures.Count -or $previous.Prefectures.Count -ne $Sample.Prefectures.Count -or
        $newZones.Count -or $previous.Zones.Count -ne $Sample.Zones.Count
    if (-not ($titleChanged -or $bodyChanged -or $detailChanged -or $warningChanged -or $areasChanged)) {
        return
    }
    $script:firstReportBlinkPending = $false
    $surface.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    $script:activeSample = $Sample

    if ($areasChanged -or $warningChanged) {
        $script:areaPages = @(Get-AreaPages $Sample)
        $script:areaPageIndex = 0
        if (-not $script:opening) {
            $timer.Stop()
            $pause.IsEnabled = $false
            if ($script:areaPages.Count -gt 1) {
                Schedule-Preview $areaPageMs
            }
        }
    }
    Show-Subtitle $Sample -ShowContent:(-not $script:opening) -AreaPage $script:areaPages[$script:areaPageIndex]
    if ($script:opening) { return }
    if ($titleChanged -or $warningChanged) { Start-UpdateBlink $titleSurface }
    if ($bodyChanged) { Start-UpdateBlink $bodySurface }
    if ($detailChanged -or $areasChanged) { Start-UpdateBlink $detailSurface }
}

function Hide-PreviewSubtitle {
    $timer.Stop()
    $surface.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    Reset-UpdateBlinks
    $script:activeSample = $null
    $overlay.Hide()
}

function End-Preview {
    $jmaReplayTimer.Stop()
    $jmaReplayClock.Stop()
    Hide-PreviewSubtitle
    $pause.IsEnabled = $false
    $update.IsEnabled = $false
    $end.IsEnabled = $false
}

function Advance-JmaReplay([TimeSpan]$Elapsed = $jmaReplayClock.Elapsed) {
    $jmaReplayTimer.Stop()
    if (-not $script:jmaSubtitleEnded -and $Elapsed -ge $jmaSubtitleEnd) {
        $script:jmaSubtitleEnded = $true
        Hide-PreviewSubtitle
    }

    $report = $jmaReports[$script:nextJmaReport]
    if ($Elapsed -lt (Get-JmaReplayOffset $report)) {
        Schedule-JmaReplay
        return
    }
    $script:nextJmaReport++
    $progress = "$($script:nextJmaReport)/$($jmaReports.Count)"
    if ($report.body.isCanceled -eq $true) {
        End-Preview
        $update.Content = "撤销报 · $progress"
        return
    }
    if (-not $script:jmaSubtitleEnded) {
        Update-Preview (New-JmaTelegramSample $report $jmaReplayLabel)
    }
    $update.Content = "第 $($report.serialNo) 报 · $progress"
    Schedule-JmaReplay
}

$timer.Add_Tick({ Advance-Preview })
$jmaReplayTimer.Add_Tick({ Advance-JmaReplay })
$select.Add_SelectionChanged({ Start-Preview })
$replay.Add_Click({ Start-Preview })
$pause.Add_Click({
    if ($script:paused) {
        $script:paused = $false
        if ($script:resumeAreaTimer) { $timer.Start() }
        if ($select.SelectedIndex -eq $jmaReplayIndex) {
            $jmaReplayClock.Start()
            Schedule-JmaReplay
        }
        $pause.Content = '暂停'
    } else {
        $script:resumeAreaTimer = $timer.IsEnabled
        $timer.Stop()
        $jmaReplayTimer.Stop()
        $jmaReplayClock.Stop()
        $script:paused = $true
        $pause.Content = '继续'
    }
})
$update.Add_Click({
    $updates = $sampleUpdates[$select.SelectedIndex]
    if ($script:nextUpdate -ge $updates.Count) { return }
    Update-Preview $updates[$script:nextUpdate]
    $script:nextUpdate++
    $update.IsEnabled = $script:nextUpdate -lt $updates.Count
})
$end.Add_Click({ End-Preview })
$control.Add_Closed({
    $timer.Stop()
    $jmaReplayTimer.Stop()
    $informationTimer.Stop()
    $informationOverlay.Close()
    $overlay.Close()
    $app.Shutdown()
})

if ($CheckDirectory) {
    $script:checkedUpdateClocks = @{}
    $overlay.Left = [Windows.SystemParameters]::VirtualScreenLeft + [Windows.SystemParameters]::VirtualScreenWidth + 32
    $informationOverlay.Left = $overlay.Left
    $wolfxWarning = Read-Fixture 'jma_cancellation_20261016/wolfx_original.json'
    $wolfxSample = New-WolfxJmaSample $wolfxWarning 'Wolfx regions test'
    Test-PreviewFrames

    function New-PreviewTestClock {
        if (-not $surface.HasAnimatedProperties) { throw 'First report did not start blinking.' }
        $clock = [Windows.Media.Animation.AnimationClock]$firstReportBlink.CreateClock($true)
        $surface.ApplyAnimationClock([Windows.UIElement]::OpacityProperty, $clock)
        $clock.Controller.Pause()
        $clock
    }

    function Wait-PreviewTick([int]$TimeoutMs, $WatchedTimer = $timer) {
        $frame = [Windows.Threading.DispatcherFrame]::new()
        $stopFrame = [EventHandler]({ $frame.Continue = $false }.GetNewClosure())
        $timeout = [Windows.Threading.DispatcherTimer]::new()
        $timeout.Interval = [TimeSpan]::FromMilliseconds($TimeoutMs)
        $timeout.Add_Tick($stopFrame)
        $WatchedTimer.Add_Tick($stopFrame)
        $timeout.Start()
        try {
            [Windows.Threading.Dispatcher]::PushFrame($frame)
        } finally {
            $timeout.Stop()
            $WatchedTimer.Remove_Tick($stopFrame)
        }
    }

    function Test-UpdateBlink([Windows.UIElement[]]$ChangedRows) {
        if ($script:checkedUpdateClocks.Count -ne $ChangedRows.Count) {
            throw 'A subtitle update must animate exactly the changed rows.'
        }
        foreach ($row in $ChangedRows) {
            if (-not $script:checkedUpdateClocks.ContainsKey($row)) {
                throw 'A changed subtitle row did not blink.'
            }
        }
        $samplePoints = @(
            @(80, 0),
            @(($blinkHiddenMs + 80), 1),
            @(($blinkCycleMs + 80), 0),
            @(($blinkCycleMs + $blinkHiddenMs + 1), 1)
        )
        foreach ($point in $samplePoints) {
            foreach ($row in $ChangedRows) {
                $script:checkedUpdateClocks[$row].Controller.SeekAlignedToLastTick(
                    [TimeSpan]::FromMilliseconds($point[0]), 'BeginTime'
                )
            }
            foreach ($row in @($surface, $titleSurface, $bodySurface, $detailSurface)) {
                $expectedOpacity = if ($row -in $ChangedRows) { $point[1] } else { 1 }
                if ($row.Opacity -ne $expectedOpacity -or -not $row.RenderTransform.Value.IsIdentity) {
                    throw "Unexpected frame at $($point[0]) ms in $($script:activeSample.Label): opacity $($row.Opacity), expected $expectedOpacity."
                }
            }
        }
        foreach ($row in $ChangedRows) {
            if ($script:checkedUpdateClocks[$row].CurrentState -ne 'Stopped') {
                throw 'The update animation must stop after two blinks.'
            }
        }
        $script:checkedUpdateClocks.Clear()
    }

    $select.SelectedIndex = 3
    Start-Preview
    if ($bodySurface.Visibility -ne 'Collapsed' -or $detailSurface.Visibility -ne 'Collapsed') {
        throw 'The opening red title should appear by itself.'
    }
    Advance-Preview
    if ($surface.Opacity -ne 1 -or $body.Text -cne $samples[3].Body -or
        $details.Text -cne $samples[3].Details -or $timer.IsEnabled) {
        throw 'The body and details must appear in the same frame before the blink.'
    }
    $blinkClock = New-PreviewTestClock
    $samplePoints = @(
        @(850, 0), @(1400, 1), @(2000, 0), @(2550, 1), @(3150, 0), @(3700, 1)
    )
    foreach ($point in $samplePoints) {
        $blinkClock.Controller.SeekAlignedToLastTick([TimeSpan]::FromMilliseconds($point[0]), 'BeginTime')
        if ($surface.Opacity -ne $point[1] -or $details.Text -cne $samples[3].Details) {
            throw "Unexpected first-report frame at $($point[0]) ms: opacity $($surface.Opacity), expected $($point[1])."
        }
    }
    $heldDetails = $details.Text
    Advance-Preview
    if ($surface.Opacity -ne 1 -or $timer.IsEnabled -or -not $overlay.IsVisible -or
        $heldDetails -cne $samples[3].Details -or $details.Text -cne $heldDetails) {
        throw 'KMA subtitle did not hold after three blinks.'
    }
    End-Preview
    if ($timer.IsEnabled -or $overlay.IsVisible) { throw 'EEW end did not hide the subtitle.' }

    $select.SelectedIndex = 2
    Advance-Preview
    if ($details.Text -cne 'M4.5　深度 40 km') { throw 'Initial CWA details do not match the report.' }
    $initialTitle = $title.Text
    $blinkClock = New-PreviewTestClock
    $blinkClock.Controller.SeekAlignedToLastTick([TimeSpan]::FromMilliseconds(850), 'BeginTime')
    if ($surface.Opacity -ne 0) { throw 'The first CWA report was not hidden before its update.' }
    $updateClick = [Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)
    $update.RaiseEvent($updateClick)
    if ($surface.Opacity -ne 1 -or $surface.HasAnimatedProperties -or $timer.IsEnabled -or $title.Text -cne $initialTitle -or
        $body.Text -cne $cwaUpdates[0].Body -or $details.Text -cne 'M4.5　深度 30 km') {
        throw 'CWA update did not replace only the changed content.'
    }
    Test-UpdateBlink @($bodySurface, $detailSurface)
    Update-Preview (New-CwaSample $cwaReports[1])
    if (-not [object]::ReferenceEquals($script:activeSample, $cwaUpdates[0]) -or $timer.IsEnabled) {
        throw 'A CWA update with the same visible fields restarted the subtitle.'
    }
    Test-UpdateBlink @()
    $update.RaiseEvent($updateClick)
    if ($details.Text -cne 'M4.6　深度 30 km' -or $surface.HasAnimatedProperties -or $timer.IsEnabled) {
        throw 'A magnitude-only CWA update did not refresh without restarting the subtitle.'
    }
    Test-UpdateBlink @($detailSurface)

    $select.SelectedIndex = 1
    Start-Preview -Sample $wolfxSample
    Advance-Preview
    $longPages = $script:areaPages
    if ($longPages.Count -le 1 -or -not $surface.HasAnimatedProperties -or
        -not $timer.IsEnabled -or $timer.Interval.TotalMilliseconds -ne $firstAreaPageMs) {
        throw 'An overflowing JMA report must start paging after the first-report blinks.'
    }
    $firstTitle = $title.Text
    $firstBody = $body.Text
    $playedPages = @(foreach ($pageIndex in 0..($longPages.Count - 1)) {
        if ($pageIndex -eq 1) {
            Wait-PreviewTick ($firstAreaPageMs + 2000)
        } elseif ($pageIndex -gt 1) {
            Advance-Preview
        }
        if ($details.Text -cne $longPages[$pageIndex] -or
            $title.Text -cne $firstTitle -or $body.Text -cne $firstBody -or
            -not $timer.IsEnabled) {
            throw "JMA area page $pageIndex did not play in order with a fixed title and body."
        }
        $details.Text
    })
    if (($playedPages -join "`n").Replace("`n", '　') -cne ($wolfxWarning.WarnArea.Chiiki -join '　')) {
        throw 'JMA area playback omitted or reordered original report regions.'
    }
    Advance-Preview
    if (-not $timer.IsEnabled -or $details.Text -cne $longPages[0] -or $surface.Opacity -ne 1 -or
        $title.Text -cne $firstTitle -or $body.Text -cne $firstBody) {
        throw 'JMA area playback must loop without replaying the first-report opening.'
    }

    $firstReportTime = [DateTimeOffset]$jmaReports[0].reportDateTime
    $lastReportTime = [DateTimeOffset]$jmaReports[-1].reportDateTime
    $ordinaryNumbers = @($jmaReports | Where-Object { -not $_.body.isCanceled } | ForEach-Object { [int]$_.serialNo })
    if ($jmaReports.Count -ne 43 -or @($jmaReports | Where-Object eventId -CNE '20261016123810').Count -or
        ($ordinaryNumbers -join ',') -cne ((1..42) -join ',') -or
        $jmaReports[-1].serialNo -ne 37 -or -not $jmaReports[-1].body.isCanceled -or
        ($lastReportTime - $firstReportTime).TotalSeconds -ne 623) {
        throw 'The JMA archive must contain reports 1–42 followed by the original cancellation.'
    }
    $select.SelectedIndex = $jmaReplayIndex
    if ($update.IsEnabled -or $update.Content -cne '第 1 报 · 1/43' -or -not $jmaReplayTimer.IsEnabled -or
        $jmaReplayTimer.Interval.TotalMilliseconds -notin 900..1000) {
        throw 'The full replay must start at the first report and schedule the second at +1 second.'
    }
    Wait-PreviewTick 2500 $jmaReplayTimer
    if ($update.Content -cne '第 2 报 · 2/43' -or $script:areaPages.Count -ne 1 -or
        $details.Text -cne $jmaReports[1].body.intensity.regions.name -or $timer.IsEnabled -or
        -not $pause.IsEnabled -or $update.IsEnabled) {
        throw 'The automatic JMA tick must show the second report without starting area pagination.'
    }
    Test-UpdateBlink @($detailSurface)
    $pauseClick = [Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)
    $pause.RaiseEvent($pauseClick)
    if ($jmaReplayTimer.IsEnabled -or $jmaReplayClock.IsRunning) { throw 'Pause must stop the replay clock.' }
    $pause.RaiseEvent($pauseClick)
    if (-not $jmaReplayTimer.IsEnabled -or -not $jmaReplayClock.IsRunning) { throw 'Resume must restart the replay clock.' }

    if ($jmaSubtitleEnd.TotalSeconds -ne 183) {
        throw 'The horizontal subtitle must end 88 seconds after the first warning.'
    }
    for ($index = 2; $index -lt ($jmaReports.Count - 1); $index++) {
        $report = $jmaReports[$index]
        $reportOffset = Get-JmaReplayOffset $report
        if (-not $script:jmaSubtitleEnded -and $reportOffset -ge $jmaSubtitleEnd) {
            $priorProgress = $update.Content
            Advance-JmaReplay ($jmaSubtitleEnd.Subtract([TimeSpan]::FromMilliseconds(1)))
            if (-not $overlay.IsVisible -or $update.Content -cne $priorProgress) {
                throw 'The horizontal subtitle must remain visible until its hide deadline.'
            }
            if ($reportOffset -gt $jmaSubtitleEnd) {
                Advance-JmaReplay $jmaSubtitleEnd
                if ($overlay.IsVisible -or $timer.IsEnabled -or $update.Content -cne $priorProgress -or
                    -not $jmaReplayTimer.IsEnabled) {
                    throw 'The horizontal subtitle must hide at its deadline without advancing the report.'
                }
            }
        }
        $sample = New-JmaTelegramSample $report $jmaReplayLabel
        $priorSample = $script:activeSample
        $priorAreaNames = $details.Text -split '\s+'
        Advance-JmaReplay $reportOffset
        if ($update.Content -cne "第 $($report.serialNo) 报 · $($index + 1)/43" -or
            $update.IsEnabled -or -not $jmaReplayTimer.IsEnabled) {
            throw "JMA replay failed to advance to original report $($report.serialNo)."
        }
        if ($reportOffset -ge $jmaSubtitleEnd) {
            if ($overlay.IsVisible -or $timer.IsEnabled -or $script:activeSample) {
                throw "JMA report $($report.serialNo) reopened the horizontal subtitle."
            }
            continue
        }
        $expectedPages = @(Get-AreaPages $sample)
        if (-not $overlay.IsVisible -or
            $title.Text -cne $sample.Title -or $body.Text -cne $sample.Body -or
            $details.Text -cne ($expectedPages[0] ?? $sample.Details)) {
            throw "JMA replay failed to render original report $($report.serialNo)."
        }
        if ($report.serialNo -eq 17) {
            if ($title.Text -cne '緊急地震速報（警報）' -or $script:areaPages.Count -ne 1 -or
                $surface.HasAnimatedProperties -or $timer.IsEnabled) {
                throw 'The JMA forecast upgrade must display the full warning without restarting the opening.'
            }
            Test-UpdateBlink @($titleSurface, $bodySurface, $detailSurface)
            Save-PreviewFrame 'jma-upgraded-to-warning.png'
        } elseif ($report.serialNo -eq 19) {
            $updatedAreaNames = $details.Text -split '\s+'
            if ($expectedPages.Count -ne 1 -or $details.Text.Contains('追加') -or
                @($priorAreaNames | Where-Object { $_ -cnotin $updatedAreaNames }).Count -or
                '福井' -cin $priorSample.Prefectures -or '福井' -cnotin $sample.Prefectures -or
                '北陸' -cnotin $updatedAreaNames -or $title.Text -cne $priorSample.Title -or
                $body.Text -cne $priorSample.Body -or $surface.HasAnimatedProperties -or $timer.IsEnabled) {
                throw 'The JMA update must keep the full warning area, including the existing areas and Fukui under Hokuriku.'
            }
            Test-UpdateBlink @($detailSurface)
            Save-PreviewFrame 'jma-expanded-warning-areas.png'
            Advance-Preview
            if ($details.Text -cne $expectedPages[0] -or $timer.IsEnabled) {
                throw 'The full JMA warning area must stay visible after the update blink.'
            }
        } else {
            Test-UpdateBlink @($script:checkedUpdateClocks.Keys)
        }
    }
    $cancelOffset = Get-JmaReplayOffset $jmaReports[-1]
    if ($cancelOffset.TotalSeconds -ne 603 -or
        ($cancelOffset - (Get-JmaReplayOffset $jmaReports[-2])).TotalSeconds -ne 20) {
        throw 'The replay cancellation must be 20 seconds early and 20 seconds after report 42.'
    }
    Advance-JmaReplay ($cancelOffset.Subtract([TimeSpan]::FromMilliseconds(1)))
    if ($update.Content -cne '第 42 报 · 42/43' -or -not $jmaReplayTimer.IsEnabled) {
        throw 'The replay must stay on report 42 until the cancellation deadline.'
    }
    Advance-JmaReplay $cancelOffset
    if ($update.Content -cne '撤销报 · 43/43' -or $jmaReplayTimer.IsEnabled -or
        $jmaReplayClock.IsRunning -or $timer.IsEnabled -or $overlay.IsVisible) {
        throw 'The original JMA cancellation must end the full replay and hide the overlay.'
    }

    # Run the dispatcher across a hide deadline between reports without waiting three minutes.
    $actualSubtitleEnd = $jmaSubtitleEnd
    $jmaSubtitleEnd = [TimeSpan]::FromMilliseconds(300)
    try {
        Start-Preview
        if (-not $overlay.IsVisible -or $script:jmaSubtitleEnded) {
            throw 'Restarting JMA playback must show the first report again.'
        }
        Wait-PreviewTick 2000 $jmaReplayTimer
        if ($overlay.IsVisible -or $update.Content -cne '第 1 报 · 1/43' -or
            -not $jmaReplayTimer.IsEnabled) {
            throw 'The dispatcher must hide the subtitle between reports.'
        }
        Wait-PreviewTick 2000 $jmaReplayTimer
        if ($overlay.IsVisible -or $update.Content -cne '第 2 报 · 2/43') {
            throw 'The dispatcher must advance reports after the subtitle has hidden.'
        }
    } finally {
        $jmaSubtitleEnd = $actualSubtitleEnd
    }

    $select.SelectedIndex = $gqUpdateIndex
    Advance-Preview
    if ($details.Text -cne 'M5.2　深度 10 km') { throw 'The initial GQ replay report did not display.' }
    $update.RaiseEvent($updateClick)
    if ($gqReports[2].eventId -cne $gqReports[3].eventId -or
        $details.Text -cne 'M5.1　深度 10 km' -or $surface.HasAnimatedProperties) {
        throw 'A GQ magnitude change must update only the detail row.'
    }
    Test-UpdateBlink @($detailSurface)
    End-Preview
    if ($timer.IsEnabled -or $overlay.IsVisible) { throw 'EEW end did not hide the subtitle.' }

    if (($informationSamples.Source -join ',') -cne 'CWA,JMA,CENC,USGS' -or
        $jmaObserved.Key -cne $jmaDetailed.Key -or
        $jmaDetailed.Revision -le $jmaObserved.Revision -or
        $cencDetail.placeName -cne '内蒙古阿拉善盟阿拉善左旗' -or
        $cencPages[0].Text -cnotmatch '^(上午|下午)\d+时\d+分左右' -or
        $jmaObserved.Pages[0].Text -cnotmatch '^(午前|午後)\d+時\d+分ごろ.*震度5弱' -or
        @($jmaDetailed.Pages | Where-Object SecondLine -like '*マグニチュード5.7*').Count -ne 1) {
        throw 'Information samples must use the four agency reports and the occurrence-time format.'
    }
    $select.SelectedIndex = [array]::IndexOf($samples.Label, '中国地震台网 · CEA')
    Advance-Preview
    $eewBodyBefore = $body.Text
    $playInformation.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    if (-not $overlay.IsVisible -or -not $informationOverlay.IsVisible -or
        $informationOverlay.Top -le ($overlay.Top + $overlay.ActualHeight) -or
        $body.Text -cne $eewBodyBefore -or $body.Text -cnotlike "*$($cencDetail.placeName)*" -or
        -not [SubtitlePreviewWindow]::IsPassive([Windows.Interop.WindowInteropHelper]::new($informationOverlay).Handle)) {
        throw 'The CENC report must display below the matching original EEW in a passive window.'
    }
    $positionBefore = $informationOverlay.Top
    Save-PreviewFrame 'information-cenc-summary.png' $informationOverlay $informationSurface
    Receive-Information $jmaObserved
    Receive-Information $jmaObserved
    Receive-Information $jmaDetailed
    if ($script:pendingInformation.Count -ne 1) { throw 'One pending JMA event must retain its latest version.' }
    End-Preview
    if ($overlay.IsVisible -or -not $informationOverlay.IsVisible -or
        $informationOverlay.Top -ne $positionBefore -or -not $informationTimer.IsEnabled) {
        throw 'Ending EEW must leave the current information in place.'
    }
    Wait-PreviewTick 5000 $informationTimer
    if ($script:informationPage -ne 1 -or
        [Windows.Automation.AutomationProperties]::GetName($informationSurface.Children[1]) -cne 'M4.4　深度 10 km') {
        throw 'The information timer must independently show the original CENC details.'
    }
    Advance-Information
    if ($script:currentInformation.Revision -ne $jmaDetailed.Revision -or $informationOverlay.Top -ne $overlay.Top) {
        throw 'The next event may occupy the top after EEW ends and must show its latest report.'
    }
    Advance-Information
    Save-PreviewFrame 'information-jma-areas.png' $informationOverlay $informationSurface
    foreach ($sample in @($informationSamples[0], $informationSamples[3])) {
        Receive-Information $sample
    }
    while ($script:currentInformation) { Advance-Information }
    if ($informationOverlay.IsVisible -or $informationTimer.IsEnabled) {
        throw 'The information window must hide after all queued pages finish.'
    }
    Receive-Information $jmaObserved -Replay
    $updateInformation.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    if ($script:currentInformation.Revision -ne $jmaDetailed.Revision -or $updateInformation.IsEnabled) {
        throw 'A JMA detail report must replace its summary in place.'
    }
    $informationTimer.Stop()
    $informationOverlay.Close()
    $overlay.Close()
    $app.Shutdown()
    "Verified the 43-telegram JMA replay, timed subtitle hide, continued report progress, early cancellation, three first-report blinks, $($longPages.Count) looping pages, and two in-place blinks of changed rows."
    'Verified four-source information, original CENC EEW coexistence, independent timer, in-place JMA update and deduplicated queue.'
    return
}

Start-Preview
if ($ShowInformation) { Receive-Information $informationSamples[$informationSelect.SelectedIndex] }
$control.Show()
[void]$control.Activate()
[void]$app.Run()
