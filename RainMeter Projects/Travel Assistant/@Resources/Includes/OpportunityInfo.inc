; Opportunity presentation support measures.
; CardPresenter owns the home-state Leave/window tooltip; TravelStateWindowTweaks
; owns that same Leave tooltip while traveling/returning/abroad. No invisible
; tooltip anchors or graph-hover tooltip surfaces remain.

[MeasureFreshnessGuard]
Measure=Script
ScriptFile=#@#Scripts\FreshnessGuard.lua
StateFile=#@#Generated\ui-state.kv
HeartbeatFile=#@#Generated\last-update.txt
StaleAfter=300
HardStaleAfter=21600
UpdateDivider=1

; Travel-state-specific status pass. While outbound or abroad, physical upcoming
; cycle timing is informational and must not skip a nearer cycle merely because the
; player cannot catch it. Returning/home planning remains handled by CardPresenter.
[MeasureTravelStateWindowTweaks]
Measure=Script
ScriptFile=#@#Scripts\TravelStateWindowTweaks.lua
StateFile=#@#Generated\ui-state.kv
UpdateDivider=1

; Final visible-card polish. Keeps the forecast untouched while simplifying Safe
; labels and placing item cost/MV beside the item name with profit at far right.
[MeasureFinalCardPolish]
Measure=Script
ScriptFile=#@#Scripts\FinalCardPolish.lua
UpdateDivider=1

