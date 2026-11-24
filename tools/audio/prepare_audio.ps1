# Prepares a sound for Full Court: trims silence at both ends, measures its loudness, normalises it to a target loudness with a true-peak ceiling (two-pass
# EBU R128 loudnorm in ffmpeg: measure, then apply with the measured values, so the result is accurate, not just approximate), and writes Ogg Vorbis for
# Godot. Use it for ANY sound that did not come from the game's own synthesiser: a recording, a sound made with Audacity, an AI-generated effect or voice line.
# It does not decide whether the sound may be used: the licence and the provenance line in assets/ART_PROVENANCE.md come first (see
# docs/development/AI_DEVELOPMENT_TOOLKIT.md, audio).
#   ./tools/audio/prepare_audio.ps1 -In raw/crowd.wav -Out assets/audio/crowd_loop.ogg                       # effects: -16 LUFS, peak -1.5 dB
#   ./tools/audio/prepare_audio.ps1 -In raw/ambience.wav -Out assets/audio/ambience.ogg -Target -23           # a quiet bed under everything else
#   ./tools/audio/prepare_audio.ps1 -In raw/line.wav -Out assets/audio/line.ogg -Target -18 -Report            # prints the before and after loudness
# Needs ffmpeg on the PATH (winget install Gyan.FFmpeg; GitHub's Ubuntu runners have it).
param(
	[Parameter(Mandatory = $true)][string]$In,
	[Parameter(Mandatory = $true)][string]$Out,
	[double]$Target = -16.0,
	[double]$Peak = -1.5,
	[switch]$KeepSilence,
	[switch]$Report
)
$ErrorActionPreference = "Stop"
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { throw "ffmpeg was not found on the PATH" }
if (-not (Test-Path $In)) { throw "input file not found: $In" }
$trim = if ($KeepSilence) { "" } else { "silenceremove=start_periods=1:start_threshold=-60dB:start_silence=0.02,areverse,silenceremove=start_periods=1:start_threshold=-60dB:start_silence=0.02,areverse," }
# pass 1: measure (ffmpeg reports on stderr, which is normal; only its exit state and output files are checked)
$ErrorActionPreference = "Continue"
$first = & ffmpeg -hide_banner -nostats -i $In -af "${trim}loudnorm=I=${Target}:TP=${Peak}:LRA=11:print_format=json" -f null NUL 2>&1 | Out-String
$json = [regex]::Match($first, '\{[^{}]*"input_i"[^{}]*\}').Value
if (-not $json) { throw "could not measure the loudness of $In" }
$m = $json | ConvertFrom-Json
# pass 2: apply with the measured values, then write Ogg Vorbis
$dir = Split-Path -Parent $Out
if ($dir) { New-Item -ItemType Directory -Force $dir | Out-Null }
$filter = "${trim}loudnorm=I=${Target}:TP=${Peak}:LRA=11:measured_I=$($m.input_i):measured_TP=$($m.input_tp):measured_LRA=$($m.input_lra):measured_thresh=$($m.input_thresh):offset=$($m.target_offset):linear=true"
& ffmpeg -hide_banner -nostats -y -i $In -af $filter -ar 44100 -c:a libvorbis -q:a 5 $Out 2>&1 | Out-Null
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Out)) { throw "ffmpeg did not write $Out" }
if ($Report) {
	$ErrorActionPreference = "Continue"
	$after = & ffmpeg -hide_banner -nostats -i $Out -af "loudnorm=I=${Target}:TP=${Peak}:print_format=json" -f null NUL 2>&1 | Out-String
	$a = ([regex]::Match($after, '\{[^{}]*"input_i"[^{}]*\}').Value | ConvertFrom-Json)
	Write-Host ("before: {0} LUFS, true peak {1} dBTP" -f $m.input_i, $m.input_tp)
	Write-Host ("after:  {0} LUFS, true peak {1} dBTP (target {2} LUFS, ceiling {3} dBTP)" -f $a.input_i, $a.input_tp, $Target, $Peak)
}
Write-Host "wrote $Out"
