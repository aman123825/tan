param([string]$Output = "stimuli\demo\speech_windows")
New-Item -ItemType Directory -Force -Path $Output | Out-Null
Add-Type -AssemblyName System.Speech
$items = @(
@('w001','Please close the blue window.'),@('w002','Meet me near the main entrance.'),@('w003','The class begins at nine thirty.'),@('w004','Turn left after the second signal.'),@('w005','Write down the name and phone number.'),@('w006','The meeting moved to Friday afternoon.'),@('w007','Bring the red folder and two pens.'),@('w008','Call me when you reach the station.'),@('w009','The teacher changed the final question.'),@('w010','Order tea without sugar, please.'),@('w011','The bus arrives at platform six.'),@('w012','Keep the medicine beside the water.'),@('w013','First open the file, then read page four.'),@('w014','The restaurant is crowded this evening.'),@('w015','Repeat the address after the tone.'),@('w016','Amit will join the call at five.'),@('w017','The television volume is already low.'),@('w018','Choose the third option on the screen.'),@('w019','Remember the date, place, and time.'),@('w020','Walk past the bank and cross the road.')
)
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.Rate = 0
foreach($x in $items){$path=Join-Path $Output ($x[0]+'.wav');$synth.SetOutputToWaveFile($path);$synth.Speak($x[1]);$synth.SetOutputToNull();Write-Host $path}
$synth.Dispose()
Write-Host "Generated $($items.Count) demo speech files. These are not validated clinical stimuli."
