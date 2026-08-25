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

; Final render-time safety fence. This measure updates after StateReader/CardPresenter/
; CardTweaks because the include is parsed at the end of the skin. It prevents stale
; provider evidence from remaining visible as actionable cards even if an upstream
; projection stage fails and leaves an older OpportunityCount in state.kv.
[MeasureFreshnessGuard]
Measure=Script
ScriptFile=#@#Scripts\FreshnessGuard.lua
StateFile=#@#Generated\state.kv
HeartbeatFile=#@#Generated\last-update.txt
StaleAfter=300
RetryInterval=15
UpdateDivider=1

; Final tooltip pass. Runs after the card presenter/tweaks and keeps confidence out
; of the card while adding live relative timing to the selected guaranteed window.
[MeasureWindowTooltipTweaks]
Measure=Script
ScriptFile=#@#Scripts\WindowTooltipTweaks.lua
StateFile=#@#Generated\state.kv
UpdateDivider=1

; Final visible-card polish. Keeps the forecast untouched while simplifying Safe
; labels and placing item cost/MV beside the item name with profit at far right.
[MeasureFinalCardPolish]
Measure=Script
ScriptFile=#@#Scripts\FinalCardPolish.lua
UpdateDivider=1
