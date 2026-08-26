; Stable image hover anchors for Safe/Best departure calculations.
; The PNG is generated locally by EnsureUiAssets.ps1 so there is no Unicode/font dependency.

[MeterOpportunity1Info]
Meter=Image
Group=OpportunityRow1
X=303
Y=148
W=12
H=12
PreserveAspectRatio=1
ImageName=#@#Generated\info-icon.png
ImageAlpha=0
Hidden=1
ToolTipTitle=Window calculation
ToolTipText=
ToolTipWidth=420
DynamicVariables=1

[MeterOpportunity2Info]
Meter=Image
Group=OpportunityRow2
X=303
Y=202
W=12
H=12
PreserveAspectRatio=1
ImageName=#@#Generated\info-icon.png
ImageAlpha=0
Hidden=1
ToolTipTitle=Window calculation
ToolTipText=
ToolTipWidth=420
DynamicVariables=1

[MeterOpportunity3Info]
Meter=Image
Group=OpportunityRow3
X=303
Y=256
W=12
H=12
PreserveAspectRatio=1
ImageName=#@#Generated\info-icon.png
ImageAlpha=0
Hidden=1
ToolTipTitle=Window calculation
ToolTipText=
ToolTipWidth=420
DynamicVariables=1

[MeterOpportunity4Info]
Meter=Image
Group=OpportunityRow4
X=303
Y=310
W=12
H=12
PreserveAspectRatio=1
ImageName=#@#Generated\info-icon.png
ImageAlpha=0
Hidden=1
ToolTipTitle=Window calculation
ToolTipText=
ToolTipWidth=420
DynamicVariables=1

[MeterOpportunity5Info]
Meter=Image
Group=OpportunityRow5
X=303
Y=364
W=12
H=12
PreserveAspectRatio=1
ImageName=#@#Generated\info-icon.png
ImageAlpha=0
Hidden=1
ToolTipTitle=Window calculation
ToolTipText=
ToolTipWidth=420
DynamicVariables=1

[MeterOpportunity6Info]
Meter=Image
Group=OpportunityRow6
X=303
Y=418
W=12
H=12
PreserveAspectRatio=1
ImageName=#@#Generated\info-icon.png
ImageAlpha=0
Hidden=1
ToolTipTitle=Window calculation
ToolTipText=
ToolTipWidth=420
DynamicVariables=1

[MeterOpportunity7Info]
Meter=Image
Group=OpportunityRow7
X=303
Y=472
W=12
H=12
PreserveAspectRatio=1
ImageName=#@#Generated\info-icon.png
ImageAlpha=0
Hidden=1
ToolTipTitle=Window calculation
ToolTipText=
ToolTipWidth=420
DynamicVariables=1

[MeterOpportunity8Info]
Meter=Image
Group=OpportunityRow8
X=303
Y=526
W=12
H=12
PreserveAspectRatio=1
ImageName=#@#Generated\info-icon.png
ImageAlpha=0
Hidden=1
ToolTipTitle=Window calculation
ToolTipText=
ToolTipWidth=420
DynamicVariables=1

; Final render-time freshness fence. Provider selection still requires a snapshot
; newer than StaleAfter, but the UI keeps the last computed opportunity set in a
; clearly labeled forecast-only mode until HardStaleAfter. This avoids long blank
; periods during provider outages without presenting cached stock as live evidence.
[MeasureFreshnessGuard]
Measure=Script
ScriptFile=#@#Scripts\FreshnessGuard.lua
StateFile=#@#Generated\ui-state.kv
HeartbeatFile=#@#Generated\last-update.txt
StaleAfter=300
HardStaleAfter=21600
RetryInterval=15
UpdateDivider=1

; Travel-state-specific status pass. While outbound or abroad, physical upcoming
; cycle timing is informational and must not skip a nearer cycle merely because the
; player cannot catch it. Returning/home planning remains handled by CardPresenter.
[MeasureTravelStateWindowTweaks]
Measure=Script
ScriptFile=#@#Scripts\TravelStateWindowTweaks.lua
StateFile=#@#Generated\ui-state.kv
UpdateDivider=1

; Final tooltip pass. Runs after the card presenter/tweaks and travel-state status
; pass, keeps confidence out of the card, and adds live relative Safe-window timing.
[MeasureWindowTooltipTweaks]
Measure=Script
ScriptFile=#@#Scripts\WindowTooltipTweaks.lua
StateFile=#@#Generated\ui-state.kv
UpdateDivider=1

; Final visible-card polish. Keeps the forecast untouched while simplifying Safe
; labels and placing item cost/MV beside the item name with profit at far right.
[MeasureFinalCardPolish]
Measure=Script
ScriptFile=#@#Scripts\FinalCardPolish.lua
UpdateDivider=1

; Hover lookup is generated only when an inline graph is open. It is local-only and
; samples the same retained stock observations used by the graph renderer.
[MeasureGraphHoverData]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
Parameter=-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "#@#Scripts\BuildGraphHoverData.ps1" -MarketKey "#GraphHoverMarketKey#"
State=Hide
Timeout=10000
DynamicVariables=1
FinishAction=[!UpdateMeasure MeasureGraphHover][!UpdateMeterGroup InlineGraphHover][!Redraw]

[MeasureGraphHover]
Measure=Script
ScriptFile=#@#Scripts\GraphHover.lua
UpdateDivider=1

@IncludeGraphHover=#@#Includes\GraphHover.inc
