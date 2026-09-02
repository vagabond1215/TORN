; Opportunity card meters. StateReader.lua owns all dynamic Y/height geometry.
; Each/Total label blocks plus MV/alternate metric/price/tax meters form the fixed two-line economics bar.
; Inline graphs remain in a separate group so showing a card never resurrects a collapsed graph.
; Card-body surfaces toggle both expansions; the $ and chart end-cap meters retain independent actions.

[MeterOpportunity1Card]
Meter=Shape
Group=OpportunityRow1
X=8
Y=120
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#
Shape2=Line 510,0,510,50 | StrokeWidth 1 | Stroke Color #Border#
Shape3=Line 510,25,536,25 | StrokeWidth 1 | Stroke Color #Border#
Shape4=Line 0,0,0,0 | StrokeWidth 0
Shape5=Line 0,0,0,0 | StrokeWidth 0
Shape6=Line 0,0,0,0 | StrokeWidth 0
Shape7=Line 0,0,0,0 | StrokeWidth 0
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1Flag]
Meter=Image
Group=OpportunityRow1
X=8
Y=120
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1FlagMask]
Meter=Image
Group=OpportunityRow1
X=8
Y=120
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ImageTint=#Panel#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1ItemImage]
Meter=Image
Group=OpportunityRow1
X=77
Y=123
W=44
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1CardBorder]
Meter=Shape
Group=OpportunityRow1
X=8
Y=120
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color #Border#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]


[MeterOpportunity1DetailEachLabel]
Meter=String
Group=OpportunityRow1
X=29
Y=137
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Each
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1DetailTotalLabel]
Meter=String
Group=OpportunityRow1
X=297
Y=137
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Total
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]
[MeterOpportunity1Gross]
Meter=String
Group=OpportunityRow1
X=54
Y=128
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]


[MeterOpportunity1DetailEachGrossValue]
Meter=String
Group=OpportunityRow1
X=154
Y=128
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1DetailTotal]
Meter=String
Group=OpportunityRow1
X=322
Y=128
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]


[MeterOpportunity1DetailTotalGrossValue]
Meter=String
Group=OpportunityRow1
X=422
Y=128
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1DetailEachNet]
Meter=String
Group=OpportunityRow1
X=162
Y=128
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]


[MeterOpportunity1DetailEachNetValue]
Meter=String
Group=OpportunityRow1
X=270
Y=128
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1DetailEachTax]
Meter=String
Group=OpportunityRow1
X=162
Y=145
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]


[MeterOpportunity1DetailEachTaxValue]
Meter=String
Group=OpportunityRow1
X=270
Y=145
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1DetailEachProfitHour]
Meter=String
Group=OpportunityRow1
X=54
Y=145
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]


[MeterOpportunity1DetailEachPriceValue]
Meter=String
Group=OpportunityRow1
X=154
Y=145
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1DetailTotalNet]
Meter=String
Group=OpportunityRow1
X=430
Y=128
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]


[MeterOpportunity1DetailTotalNetValue]
Meter=String
Group=OpportunityRow1
X=538
Y=128
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1DetailTotalTax]
Meter=String
Group=OpportunityRow1
X=430
Y=145
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]


[MeterOpportunity1DetailTotalTaxValue]
Meter=String
Group=OpportunityRow1
X=538
Y=145
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1DetailTotalProfitHour]
Meter=String
Group=OpportunityRow1
X=322
Y=145
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]


[MeterOpportunity1DetailTotalPriceValue]
Meter=String
Group=OpportunityRow1
X=422
Y=145
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1Name]
Meter=String
Group=OpportunityRow1
X=123
Y=126
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity1Price]
Meter=String
Group=OpportunityRow1
X=123
Y=126
W=230
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1Take]
Meter=String
Group=OpportunityRow1
X=123
Y=126
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity1Make]
Meter=String
Group=OpportunityRow1
X=504
Y=145
W=142
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=14
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]
H=50
StringAlign=RightCenter

[MeterOpportunity1DetailToggle]
Meter=String
Group=OpportunityRow1
X=531
Y=133
W=24
H=23
StringAlign=CenterCenter
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=10
FontColor=#ToggleIdle#
AntiAlias=1
SolidColor=0,0,0,1
Text=$
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardDetails(1)"]

[MeterOpportunity1Window]
Meter=String
Group=OpportunityRow1
X=123
Y=154
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity1Leave]
Meter=String
Group=OpportunityRow1
X=123
Y=154
W=263
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity1Chance]
Meter=String
Group=OpportunityRow1
X=123
Y=154
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity1Graph]
Meter=Shape
Group=OpportunityRow1
X=519
Y=146
W=24
H=23
Hidden=1
DynamicVariables=1
GraphExpanded=0
Shape=Rectangle 0,0,24,23 | Fill Color 0,0,0,1 | StrokeWidth 0
Shape2=Line 7,16,7,7 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape3=Line 7,16,17,16 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape4=Line 8,14,11,11 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape5=Line 11,11,13,13 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape6=Line 13,13,17,8 | StrokeWidth 1 | Stroke Color #ToggleIdle#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(1)"]

[MeterOpportunity1InlineGraph]
Meter=Image
Group=OpportunityInlineGraph1
X=12
Y=173
W=528
H=125
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(1)"]

[MeterOpportunity2Card]
Meter=Shape
Group=OpportunityRow2
X=8
Y=174
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#
Shape2=Line 510,0,510,50 | StrokeWidth 1 | Stroke Color #Border#
Shape3=Line 510,25,536,25 | StrokeWidth 1 | Stroke Color #Border#
Shape4=Line 0,0,0,0 | StrokeWidth 0
Shape5=Line 0,0,0,0 | StrokeWidth 0
Shape6=Line 0,0,0,0 | StrokeWidth 0
Shape7=Line 0,0,0,0 | StrokeWidth 0
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2Flag]
Meter=Image
Group=OpportunityRow2
X=8
Y=174
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2FlagMask]
Meter=Image
Group=OpportunityRow2
X=8
Y=174
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ImageTint=#Panel#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2ItemImage]
Meter=Image
Group=OpportunityRow2
X=77
Y=177
W=44
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2CardBorder]
Meter=Shape
Group=OpportunityRow2
X=8
Y=174
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color #Border#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]


[MeterOpportunity2DetailEachLabel]
Meter=String
Group=OpportunityRow2
X=29
Y=191
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Each
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2DetailTotalLabel]
Meter=String
Group=OpportunityRow2
X=297
Y=191
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Total
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]
[MeterOpportunity2Gross]
Meter=String
Group=OpportunityRow2
X=54
Y=182
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]


[MeterOpportunity2DetailEachGrossValue]
Meter=String
Group=OpportunityRow2
X=154
Y=182
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2DetailTotal]
Meter=String
Group=OpportunityRow2
X=322
Y=182
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]


[MeterOpportunity2DetailTotalGrossValue]
Meter=String
Group=OpportunityRow2
X=422
Y=182
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2DetailEachNet]
Meter=String
Group=OpportunityRow2
X=162
Y=182
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]


[MeterOpportunity2DetailEachNetValue]
Meter=String
Group=OpportunityRow2
X=270
Y=182
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2DetailEachTax]
Meter=String
Group=OpportunityRow2
X=162
Y=199
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]


[MeterOpportunity2DetailEachTaxValue]
Meter=String
Group=OpportunityRow2
X=270
Y=199
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2DetailEachProfitHour]
Meter=String
Group=OpportunityRow2
X=54
Y=199
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]


[MeterOpportunity2DetailEachPriceValue]
Meter=String
Group=OpportunityRow2
X=154
Y=199
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2DetailTotalNet]
Meter=String
Group=OpportunityRow2
X=430
Y=182
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]


[MeterOpportunity2DetailTotalNetValue]
Meter=String
Group=OpportunityRow2
X=538
Y=182
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2DetailTotalTax]
Meter=String
Group=OpportunityRow2
X=430
Y=199
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]


[MeterOpportunity2DetailTotalTaxValue]
Meter=String
Group=OpportunityRow2
X=538
Y=199
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2DetailTotalProfitHour]
Meter=String
Group=OpportunityRow2
X=322
Y=199
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]


[MeterOpportunity2DetailTotalPriceValue]
Meter=String
Group=OpportunityRow2
X=422
Y=199
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2Name]
Meter=String
Group=OpportunityRow2
X=123
Y=180
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity2Price]
Meter=String
Group=OpportunityRow2
X=123
Y=180
W=230
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2Take]
Meter=String
Group=OpportunityRow2
X=123
Y=180
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity2Make]
Meter=String
Group=OpportunityRow2
X=504
Y=199
W=142
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=14
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]
H=50
StringAlign=RightCenter

[MeterOpportunity2DetailToggle]
Meter=String
Group=OpportunityRow2
X=531
Y=187
W=24
H=23
StringAlign=CenterCenter
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=10
FontColor=#ToggleIdle#
AntiAlias=1
SolidColor=0,0,0,1
Text=$
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardDetails(2)"]

[MeterOpportunity2Window]
Meter=String
Group=OpportunityRow2
X=123
Y=208
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity2Leave]
Meter=String
Group=OpportunityRow2
X=123
Y=208
W=263
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity2Chance]
Meter=String
Group=OpportunityRow2
X=123
Y=208
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity2Graph]
Meter=Shape
Group=OpportunityRow2
X=519
Y=200
W=24
H=23
Hidden=1
DynamicVariables=1
GraphExpanded=0
Shape=Rectangle 0,0,24,23 | Fill Color 0,0,0,1 | StrokeWidth 0
Shape2=Line 7,16,7,7 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape3=Line 7,16,17,16 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape4=Line 8,14,11,11 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape5=Line 11,11,13,13 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape6=Line 13,13,17,8 | StrokeWidth 1 | Stroke Color #ToggleIdle#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(2)"]

[MeterOpportunity2InlineGraph]
Meter=Image
Group=OpportunityInlineGraph2
X=12
Y=227
W=528
H=125
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(2)"]

[MeterOpportunity3Card]
Meter=Shape
Group=OpportunityRow3
X=8
Y=228
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#
Shape2=Line 510,0,510,50 | StrokeWidth 1 | Stroke Color #Border#
Shape3=Line 510,25,536,25 | StrokeWidth 1 | Stroke Color #Border#
Shape4=Line 0,0,0,0 | StrokeWidth 0
Shape5=Line 0,0,0,0 | StrokeWidth 0
Shape6=Line 0,0,0,0 | StrokeWidth 0
Shape7=Line 0,0,0,0 | StrokeWidth 0
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3Flag]
Meter=Image
Group=OpportunityRow3
X=8
Y=228
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3FlagMask]
Meter=Image
Group=OpportunityRow3
X=8
Y=228
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ImageTint=#Panel#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3ItemImage]
Meter=Image
Group=OpportunityRow3
X=77
Y=231
W=44
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3CardBorder]
Meter=Shape
Group=OpportunityRow3
X=8
Y=228
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color #Border#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]


[MeterOpportunity3DetailEachLabel]
Meter=String
Group=OpportunityRow3
X=29
Y=245
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Each
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3DetailTotalLabel]
Meter=String
Group=OpportunityRow3
X=297
Y=245
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Total
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]
[MeterOpportunity3Gross]
Meter=String
Group=OpportunityRow3
X=54
Y=236
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]


[MeterOpportunity3DetailEachGrossValue]
Meter=String
Group=OpportunityRow3
X=154
Y=236
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3DetailTotal]
Meter=String
Group=OpportunityRow3
X=322
Y=236
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]


[MeterOpportunity3DetailTotalGrossValue]
Meter=String
Group=OpportunityRow3
X=422
Y=236
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3DetailEachNet]
Meter=String
Group=OpportunityRow3
X=162
Y=236
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]


[MeterOpportunity3DetailEachNetValue]
Meter=String
Group=OpportunityRow3
X=270
Y=236
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3DetailEachTax]
Meter=String
Group=OpportunityRow3
X=162
Y=253
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]


[MeterOpportunity3DetailEachTaxValue]
Meter=String
Group=OpportunityRow3
X=270
Y=253
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3DetailEachProfitHour]
Meter=String
Group=OpportunityRow3
X=54
Y=253
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]


[MeterOpportunity3DetailEachPriceValue]
Meter=String
Group=OpportunityRow3
X=154
Y=253
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3DetailTotalNet]
Meter=String
Group=OpportunityRow3
X=430
Y=236
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]


[MeterOpportunity3DetailTotalNetValue]
Meter=String
Group=OpportunityRow3
X=538
Y=236
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3DetailTotalTax]
Meter=String
Group=OpportunityRow3
X=430
Y=253
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]


[MeterOpportunity3DetailTotalTaxValue]
Meter=String
Group=OpportunityRow3
X=538
Y=253
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3DetailTotalProfitHour]
Meter=String
Group=OpportunityRow3
X=322
Y=253
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]


[MeterOpportunity3DetailTotalPriceValue]
Meter=String
Group=OpportunityRow3
X=422
Y=253
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3Name]
Meter=String
Group=OpportunityRow3
X=123
Y=234
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity3Price]
Meter=String
Group=OpportunityRow3
X=123
Y=234
W=230
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3Take]
Meter=String
Group=OpportunityRow3
X=123
Y=234
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity3Make]
Meter=String
Group=OpportunityRow3
X=504
Y=253
W=142
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=14
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]
H=50
StringAlign=RightCenter

[MeterOpportunity3DetailToggle]
Meter=String
Group=OpportunityRow3
X=531
Y=241
W=24
H=23
StringAlign=CenterCenter
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=10
FontColor=#ToggleIdle#
AntiAlias=1
SolidColor=0,0,0,1
Text=$
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardDetails(3)"]

[MeterOpportunity3Window]
Meter=String
Group=OpportunityRow3
X=123
Y=262
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity3Leave]
Meter=String
Group=OpportunityRow3
X=123
Y=262
W=263
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity3Chance]
Meter=String
Group=OpportunityRow3
X=123
Y=262
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity3Graph]
Meter=Shape
Group=OpportunityRow3
X=519
Y=254
W=24
H=23
Hidden=1
DynamicVariables=1
GraphExpanded=0
Shape=Rectangle 0,0,24,23 | Fill Color 0,0,0,1 | StrokeWidth 0
Shape2=Line 7,16,7,7 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape3=Line 7,16,17,16 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape4=Line 8,14,11,11 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape5=Line 11,11,13,13 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape6=Line 13,13,17,8 | StrokeWidth 1 | Stroke Color #ToggleIdle#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(3)"]

[MeterOpportunity3InlineGraph]
Meter=Image
Group=OpportunityInlineGraph3
X=12
Y=281
W=528
H=125
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(3)"]

[MeterOpportunity4Card]
Meter=Shape
Group=OpportunityRow4
X=8
Y=282
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#
Shape2=Line 510,0,510,50 | StrokeWidth 1 | Stroke Color #Border#
Shape3=Line 510,25,536,25 | StrokeWidth 1 | Stroke Color #Border#
Shape4=Line 0,0,0,0 | StrokeWidth 0
Shape5=Line 0,0,0,0 | StrokeWidth 0
Shape6=Line 0,0,0,0 | StrokeWidth 0
Shape7=Line 0,0,0,0 | StrokeWidth 0
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4Flag]
Meter=Image
Group=OpportunityRow4
X=8
Y=282
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4FlagMask]
Meter=Image
Group=OpportunityRow4
X=8
Y=282
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ImageTint=#Panel#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4ItemImage]
Meter=Image
Group=OpportunityRow4
X=77
Y=285
W=44
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4CardBorder]
Meter=Shape
Group=OpportunityRow4
X=8
Y=282
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color #Border#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]


[MeterOpportunity4DetailEachLabel]
Meter=String
Group=OpportunityRow4
X=29
Y=299
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Each
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4DetailTotalLabel]
Meter=String
Group=OpportunityRow4
X=297
Y=299
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Total
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]
[MeterOpportunity4Gross]
Meter=String
Group=OpportunityRow4
X=54
Y=290
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]


[MeterOpportunity4DetailEachGrossValue]
Meter=String
Group=OpportunityRow4
X=154
Y=290
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4DetailTotal]
Meter=String
Group=OpportunityRow4
X=322
Y=290
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]


[MeterOpportunity4DetailTotalGrossValue]
Meter=String
Group=OpportunityRow4
X=422
Y=290
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4DetailEachNet]
Meter=String
Group=OpportunityRow4
X=162
Y=290
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]


[MeterOpportunity4DetailEachNetValue]
Meter=String
Group=OpportunityRow4
X=270
Y=290
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4DetailEachTax]
Meter=String
Group=OpportunityRow4
X=162
Y=307
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]


[MeterOpportunity4DetailEachTaxValue]
Meter=String
Group=OpportunityRow4
X=270
Y=307
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4DetailEachProfitHour]
Meter=String
Group=OpportunityRow4
X=54
Y=307
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]


[MeterOpportunity4DetailEachPriceValue]
Meter=String
Group=OpportunityRow4
X=154
Y=307
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4DetailTotalNet]
Meter=String
Group=OpportunityRow4
X=430
Y=290
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]


[MeterOpportunity4DetailTotalNetValue]
Meter=String
Group=OpportunityRow4
X=538
Y=290
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4DetailTotalTax]
Meter=String
Group=OpportunityRow4
X=430
Y=307
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]


[MeterOpportunity4DetailTotalTaxValue]
Meter=String
Group=OpportunityRow4
X=538
Y=307
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4DetailTotalProfitHour]
Meter=String
Group=OpportunityRow4
X=322
Y=307
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]


[MeterOpportunity4DetailTotalPriceValue]
Meter=String
Group=OpportunityRow4
X=422
Y=307
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4Name]
Meter=String
Group=OpportunityRow4
X=123
Y=288
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity4Price]
Meter=String
Group=OpportunityRow4
X=123
Y=288
W=230
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4Take]
Meter=String
Group=OpportunityRow4
X=123
Y=288
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity4Make]
Meter=String
Group=OpportunityRow4
X=504
Y=307
W=142
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=14
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]
H=50
StringAlign=RightCenter

[MeterOpportunity4DetailToggle]
Meter=String
Group=OpportunityRow4
X=531
Y=295
W=24
H=23
StringAlign=CenterCenter
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=10
FontColor=#ToggleIdle#
AntiAlias=1
SolidColor=0,0,0,1
Text=$
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardDetails(4)"]

[MeterOpportunity4Window]
Meter=String
Group=OpportunityRow4
X=123
Y=316
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity4Leave]
Meter=String
Group=OpportunityRow4
X=123
Y=316
W=263
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity4Chance]
Meter=String
Group=OpportunityRow4
X=123
Y=316
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity4Graph]
Meter=Shape
Group=OpportunityRow4
X=519
Y=308
W=24
H=23
Hidden=1
DynamicVariables=1
GraphExpanded=0
Shape=Rectangle 0,0,24,23 | Fill Color 0,0,0,1 | StrokeWidth 0
Shape2=Line 7,16,7,7 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape3=Line 7,16,17,16 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape4=Line 8,14,11,11 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape5=Line 11,11,13,13 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape6=Line 13,13,17,8 | StrokeWidth 1 | Stroke Color #ToggleIdle#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(4)"]

[MeterOpportunity4InlineGraph]
Meter=Image
Group=OpportunityInlineGraph4
X=12
Y=335
W=528
H=125
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(4)"]

[MeterOpportunity5Card]
Meter=Shape
Group=OpportunityRow5
X=8
Y=336
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#
Shape2=Line 510,0,510,50 | StrokeWidth 1 | Stroke Color #Border#
Shape3=Line 510,25,536,25 | StrokeWidth 1 | Stroke Color #Border#
Shape4=Line 0,0,0,0 | StrokeWidth 0
Shape5=Line 0,0,0,0 | StrokeWidth 0
Shape6=Line 0,0,0,0 | StrokeWidth 0
Shape7=Line 0,0,0,0 | StrokeWidth 0
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5Flag]
Meter=Image
Group=OpportunityRow5
X=8
Y=336
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5FlagMask]
Meter=Image
Group=OpportunityRow5
X=8
Y=336
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ImageTint=#Panel#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5ItemImage]
Meter=Image
Group=OpportunityRow5
X=77
Y=339
W=44
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5CardBorder]
Meter=Shape
Group=OpportunityRow5
X=8
Y=336
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color #Border#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]


[MeterOpportunity5DetailEachLabel]
Meter=String
Group=OpportunityRow5
X=29
Y=353
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Each
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5DetailTotalLabel]
Meter=String
Group=OpportunityRow5
X=297
Y=353
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Total
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]
[MeterOpportunity5Gross]
Meter=String
Group=OpportunityRow5
X=54
Y=344
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]


[MeterOpportunity5DetailEachGrossValue]
Meter=String
Group=OpportunityRow5
X=154
Y=344
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5DetailTotal]
Meter=String
Group=OpportunityRow5
X=322
Y=344
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]


[MeterOpportunity5DetailTotalGrossValue]
Meter=String
Group=OpportunityRow5
X=422
Y=344
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5DetailEachNet]
Meter=String
Group=OpportunityRow5
X=162
Y=344
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]


[MeterOpportunity5DetailEachNetValue]
Meter=String
Group=OpportunityRow5
X=270
Y=344
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5DetailEachTax]
Meter=String
Group=OpportunityRow5
X=162
Y=361
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]


[MeterOpportunity5DetailEachTaxValue]
Meter=String
Group=OpportunityRow5
X=270
Y=361
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5DetailEachProfitHour]
Meter=String
Group=OpportunityRow5
X=54
Y=361
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]


[MeterOpportunity5DetailEachPriceValue]
Meter=String
Group=OpportunityRow5
X=154
Y=361
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5DetailTotalNet]
Meter=String
Group=OpportunityRow5
X=430
Y=344
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]


[MeterOpportunity5DetailTotalNetValue]
Meter=String
Group=OpportunityRow5
X=538
Y=344
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5DetailTotalTax]
Meter=String
Group=OpportunityRow5
X=430
Y=361
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]


[MeterOpportunity5DetailTotalTaxValue]
Meter=String
Group=OpportunityRow5
X=538
Y=361
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5DetailTotalProfitHour]
Meter=String
Group=OpportunityRow5
X=322
Y=361
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]


[MeterOpportunity5DetailTotalPriceValue]
Meter=String
Group=OpportunityRow5
X=422
Y=361
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5Name]
Meter=String
Group=OpportunityRow5
X=123
Y=342
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity5Price]
Meter=String
Group=OpportunityRow5
X=123
Y=342
W=230
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5Take]
Meter=String
Group=OpportunityRow5
X=123
Y=342
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity5Make]
Meter=String
Group=OpportunityRow5
X=504
Y=361
W=142
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=14
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]
H=50
StringAlign=RightCenter

[MeterOpportunity5DetailToggle]
Meter=String
Group=OpportunityRow5
X=531
Y=349
W=24
H=23
StringAlign=CenterCenter
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=10
FontColor=#ToggleIdle#
AntiAlias=1
SolidColor=0,0,0,1
Text=$
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardDetails(5)"]

[MeterOpportunity5Window]
Meter=String
Group=OpportunityRow5
X=123
Y=370
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity5Leave]
Meter=String
Group=OpportunityRow5
X=123
Y=370
W=263
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity5Chance]
Meter=String
Group=OpportunityRow5
X=123
Y=370
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity5Graph]
Meter=Shape
Group=OpportunityRow5
X=519
Y=362
W=24
H=23
Hidden=1
DynamicVariables=1
GraphExpanded=0
Shape=Rectangle 0,0,24,23 | Fill Color 0,0,0,1 | StrokeWidth 0
Shape2=Line 7,16,7,7 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape3=Line 7,16,17,16 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape4=Line 8,14,11,11 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape5=Line 11,11,13,13 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape6=Line 13,13,17,8 | StrokeWidth 1 | Stroke Color #ToggleIdle#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(5)"]

[MeterOpportunity5InlineGraph]
Meter=Image
Group=OpportunityInlineGraph5
X=12
Y=389
W=528
H=125
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(5)"]

[MeterOpportunity6Card]
Meter=Shape
Group=OpportunityRow6
X=8
Y=390
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#
Shape2=Line 510,0,510,50 | StrokeWidth 1 | Stroke Color #Border#
Shape3=Line 510,25,536,25 | StrokeWidth 1 | Stroke Color #Border#
Shape4=Line 0,0,0,0 | StrokeWidth 0
Shape5=Line 0,0,0,0 | StrokeWidth 0
Shape6=Line 0,0,0,0 | StrokeWidth 0
Shape7=Line 0,0,0,0 | StrokeWidth 0
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6Flag]
Meter=Image
Group=OpportunityRow6
X=8
Y=390
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6FlagMask]
Meter=Image
Group=OpportunityRow6
X=8
Y=390
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ImageTint=#Panel#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6ItemImage]
Meter=Image
Group=OpportunityRow6
X=77
Y=393
W=44
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6CardBorder]
Meter=Shape
Group=OpportunityRow6
X=8
Y=390
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color #Border#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]


[MeterOpportunity6DetailEachLabel]
Meter=String
Group=OpportunityRow6
X=29
Y=407
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Each
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6DetailTotalLabel]
Meter=String
Group=OpportunityRow6
X=297
Y=407
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Total
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]
[MeterOpportunity6Gross]
Meter=String
Group=OpportunityRow6
X=54
Y=398
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]


[MeterOpportunity6DetailEachGrossValue]
Meter=String
Group=OpportunityRow6
X=154
Y=398
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6DetailTotal]
Meter=String
Group=OpportunityRow6
X=322
Y=398
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]


[MeterOpportunity6DetailTotalGrossValue]
Meter=String
Group=OpportunityRow6
X=422
Y=398
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6DetailEachNet]
Meter=String
Group=OpportunityRow6
X=162
Y=398
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]


[MeterOpportunity6DetailEachNetValue]
Meter=String
Group=OpportunityRow6
X=270
Y=398
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6DetailEachTax]
Meter=String
Group=OpportunityRow6
X=162
Y=415
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]


[MeterOpportunity6DetailEachTaxValue]
Meter=String
Group=OpportunityRow6
X=270
Y=415
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6DetailEachProfitHour]
Meter=String
Group=OpportunityRow6
X=54
Y=415
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]


[MeterOpportunity6DetailEachPriceValue]
Meter=String
Group=OpportunityRow6
X=154
Y=415
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6DetailTotalNet]
Meter=String
Group=OpportunityRow6
X=430
Y=398
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]


[MeterOpportunity6DetailTotalNetValue]
Meter=String
Group=OpportunityRow6
X=538
Y=398
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6DetailTotalTax]
Meter=String
Group=OpportunityRow6
X=430
Y=415
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]


[MeterOpportunity6DetailTotalTaxValue]
Meter=String
Group=OpportunityRow6
X=538
Y=415
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6DetailTotalProfitHour]
Meter=String
Group=OpportunityRow6
X=322
Y=415
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]


[MeterOpportunity6DetailTotalPriceValue]
Meter=String
Group=OpportunityRow6
X=422
Y=415
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6Name]
Meter=String
Group=OpportunityRow6
X=123
Y=396
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity6Price]
Meter=String
Group=OpportunityRow6
X=123
Y=396
W=230
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6Take]
Meter=String
Group=OpportunityRow6
X=123
Y=396
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity6Make]
Meter=String
Group=OpportunityRow6
X=504
Y=415
W=142
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=14
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]
H=50
StringAlign=RightCenter

[MeterOpportunity6DetailToggle]
Meter=String
Group=OpportunityRow6
X=531
Y=403
W=24
H=23
StringAlign=CenterCenter
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=10
FontColor=#ToggleIdle#
AntiAlias=1
SolidColor=0,0,0,1
Text=$
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardDetails(6)"]

[MeterOpportunity6Window]
Meter=String
Group=OpportunityRow6
X=123
Y=424
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity6Leave]
Meter=String
Group=OpportunityRow6
X=123
Y=424
W=263
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity6Chance]
Meter=String
Group=OpportunityRow6
X=123
Y=424
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity6Graph]
Meter=Shape
Group=OpportunityRow6
X=519
Y=416
W=24
H=23
Hidden=1
DynamicVariables=1
GraphExpanded=0
Shape=Rectangle 0,0,24,23 | Fill Color 0,0,0,1 | StrokeWidth 0
Shape2=Line 7,16,7,7 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape3=Line 7,16,17,16 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape4=Line 8,14,11,11 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape5=Line 11,11,13,13 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape6=Line 13,13,17,8 | StrokeWidth 1 | Stroke Color #ToggleIdle#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(6)"]

[MeterOpportunity6InlineGraph]
Meter=Image
Group=OpportunityInlineGraph6
X=12
Y=443
W=528
H=125
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(6)"]

[MeterOpportunity7Card]
Meter=Shape
Group=OpportunityRow7
X=8
Y=444
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#
Shape2=Line 510,0,510,50 | StrokeWidth 1 | Stroke Color #Border#
Shape3=Line 510,25,536,25 | StrokeWidth 1 | Stroke Color #Border#
Shape4=Line 0,0,0,0 | StrokeWidth 0
Shape5=Line 0,0,0,0 | StrokeWidth 0
Shape6=Line 0,0,0,0 | StrokeWidth 0
Shape7=Line 0,0,0,0 | StrokeWidth 0
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7Flag]
Meter=Image
Group=OpportunityRow7
X=8
Y=444
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7FlagMask]
Meter=Image
Group=OpportunityRow7
X=8
Y=444
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ImageTint=#Panel#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7ItemImage]
Meter=Image
Group=OpportunityRow7
X=77
Y=447
W=44
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7CardBorder]
Meter=Shape
Group=OpportunityRow7
X=8
Y=444
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color #Border#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]


[MeterOpportunity7DetailEachLabel]
Meter=String
Group=OpportunityRow7
X=29
Y=461
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Each
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7DetailTotalLabel]
Meter=String
Group=OpportunityRow7
X=297
Y=461
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Total
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]
[MeterOpportunity7Gross]
Meter=String
Group=OpportunityRow7
X=54
Y=452
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]


[MeterOpportunity7DetailEachGrossValue]
Meter=String
Group=OpportunityRow7
X=154
Y=452
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7DetailTotal]
Meter=String
Group=OpportunityRow7
X=322
Y=452
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]


[MeterOpportunity7DetailTotalGrossValue]
Meter=String
Group=OpportunityRow7
X=422
Y=452
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7DetailEachNet]
Meter=String
Group=OpportunityRow7
X=162
Y=452
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]


[MeterOpportunity7DetailEachNetValue]
Meter=String
Group=OpportunityRow7
X=270
Y=452
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7DetailEachTax]
Meter=String
Group=OpportunityRow7
X=162
Y=469
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]


[MeterOpportunity7DetailEachTaxValue]
Meter=String
Group=OpportunityRow7
X=270
Y=469
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7DetailEachProfitHour]
Meter=String
Group=OpportunityRow7
X=54
Y=469
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]


[MeterOpportunity7DetailEachPriceValue]
Meter=String
Group=OpportunityRow7
X=154
Y=469
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7DetailTotalNet]
Meter=String
Group=OpportunityRow7
X=430
Y=452
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]


[MeterOpportunity7DetailTotalNetValue]
Meter=String
Group=OpportunityRow7
X=538
Y=452
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7DetailTotalTax]
Meter=String
Group=OpportunityRow7
X=430
Y=469
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]


[MeterOpportunity7DetailTotalTaxValue]
Meter=String
Group=OpportunityRow7
X=538
Y=469
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7DetailTotalProfitHour]
Meter=String
Group=OpportunityRow7
X=322
Y=469
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]


[MeterOpportunity7DetailTotalPriceValue]
Meter=String
Group=OpportunityRow7
X=422
Y=469
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7Name]
Meter=String
Group=OpportunityRow7
X=123
Y=450
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity7Price]
Meter=String
Group=OpportunityRow7
X=123
Y=450
W=230
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7Take]
Meter=String
Group=OpportunityRow7
X=123
Y=450
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity7Make]
Meter=String
Group=OpportunityRow7
X=504
Y=469
W=142
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=14
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]
H=50
StringAlign=RightCenter

[MeterOpportunity7DetailToggle]
Meter=String
Group=OpportunityRow7
X=531
Y=457
W=24
H=23
StringAlign=CenterCenter
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=10
FontColor=#ToggleIdle#
AntiAlias=1
SolidColor=0,0,0,1
Text=$
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardDetails(7)"]

[MeterOpportunity7Window]
Meter=String
Group=OpportunityRow7
X=123
Y=478
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity7Leave]
Meter=String
Group=OpportunityRow7
X=123
Y=478
W=263
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity7Chance]
Meter=String
Group=OpportunityRow7
X=123
Y=478
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity7Graph]
Meter=Shape
Group=OpportunityRow7
X=519
Y=470
W=24
H=23
Hidden=1
DynamicVariables=1
GraphExpanded=0
Shape=Rectangle 0,0,24,23 | Fill Color 0,0,0,1 | StrokeWidth 0
Shape2=Line 7,16,7,7 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape3=Line 7,16,17,16 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape4=Line 8,14,11,11 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape5=Line 11,11,13,13 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape6=Line 13,13,17,8 | StrokeWidth 1 | Stroke Color #ToggleIdle#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(7)"]

[MeterOpportunity7InlineGraph]
Meter=Image
Group=OpportunityInlineGraph7
X=12
Y=497
W=528
H=125
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(7)"]

[MeterOpportunity8Card]
Meter=Shape
Group=OpportunityRow8
X=8
Y=498
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#
Shape2=Line 510,0,510,50 | StrokeWidth 1 | Stroke Color #Border#
Shape3=Line 510,25,536,25 | StrokeWidth 1 | Stroke Color #Border#
Shape4=Line 0,0,0,0 | StrokeWidth 0
Shape5=Line 0,0,0,0 | StrokeWidth 0
Shape6=Line 0,0,0,0 | StrokeWidth 0
Shape7=Line 0,0,0,0 | StrokeWidth 0
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8Flag]
Meter=Image
Group=OpportunityRow8
X=8
Y=498
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8FlagMask]
Meter=Image
Group=OpportunityRow8
X=8
Y=498
W=67
H=50
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ImageTint=#Panel#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8ItemImage]
Meter=Image
Group=OpportunityRow8
X=77
Y=501
W=44
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8CardBorder]
Meter=Shape
Group=OpportunityRow8
X=8
Y=498
W=536
H=50
Hidden=1
DynamicVariables=1
Shape=Rectangle 0,0,536,50,5 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color #Border#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]


[MeterOpportunity8DetailEachLabel]
Meter=String
Group=OpportunityRow8
X=29
Y=515
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Each
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8DetailTotalLabel]
Meter=String
Group=OpportunityRow8
X=297
Y=515
W=40
H=32
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=CenterCenter
AntiAlias=1
ClipString=1
SolidColor=#Border#
Text=Total
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]
[MeterOpportunity8Gross]
Meter=String
Group=OpportunityRow8
X=54
Y=506
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]


[MeterOpportunity8DetailEachGrossValue]
Meter=String
Group=OpportunityRow8
X=154
Y=506
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8DetailTotal]
Meter=String
Group=OpportunityRow8
X=322
Y=506
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]


[MeterOpportunity8DetailTotalGrossValue]
Meter=String
Group=OpportunityRow8
X=422
Y=506
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8DetailEachNet]
Meter=String
Group=OpportunityRow8
X=162
Y=506
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]


[MeterOpportunity8DetailEachNetValue]
Meter=String
Group=OpportunityRow8
X=270
Y=506
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8DetailEachTax]
Meter=String
Group=OpportunityRow8
X=162
Y=523
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]


[MeterOpportunity8DetailEachTaxValue]
Meter=String
Group=OpportunityRow8
X=270
Y=523
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8DetailEachProfitHour]
Meter=String
Group=OpportunityRow8
X=54
Y=523
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]


[MeterOpportunity8DetailEachPriceValue]
Meter=String
Group=OpportunityRow8
X=154
Y=523
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8DetailTotalNet]
Meter=String
Group=OpportunityRow8
X=430
Y=506
W=48
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]


[MeterOpportunity8DetailTotalNetValue]
Meter=String
Group=OpportunityRow8
X=538
Y=506
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8DetailTotalTax]
Meter=String
Group=OpportunityRow8
X=430
Y=523
W=54
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]


[MeterOpportunity8DetailTotalTaxValue]
Meter=String
Group=OpportunityRow8
X=538
Y=523
W=96
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8DetailTotalProfitHour]
Meter=String
Group=OpportunityRow8
X=322
Y=523
W=42
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=LeftCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]


[MeterOpportunity8DetailTotalPriceValue]
Meter=String
Group=OpportunityRow8
X=422
Y=523
W=92
H=16
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8Name]
Meter=String
Group=OpportunityRow8
X=123
Y=504
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity8Price]
Meter=String
Group=OpportunityRow8
X=123
Y=504
W=230
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8Take]
Meter=String
Group=OpportunityRow8
X=123
Y=504
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=12
FontColor=0,0,0,0
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity8Make]
Meter=String
Group=OpportunityRow8
X=504
Y=523
W=142
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=14
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]
H=50
StringAlign=RightCenter

[MeterOpportunity8DetailToggle]
Meter=String
Group=OpportunityRow8
X=531
Y=511
W=24
H=23
StringAlign=CenterCenter
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=10
FontColor=#ToggleIdle#
AntiAlias=1
SolidColor=0,0,0,1
Text=$
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardDetails(8)"]

[MeterOpportunity8Window]
Meter=String
Group=OpportunityRow8
X=123
Y=532
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity8Leave]
Meter=String
Group=OpportunityRow8
X=123
Y=532
W=263
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]

[MeterOpportunity8Chance]
Meter=String
Group=OpportunityRow8
X=123
Y=532
W=1
Hidden=1
DynamicVariables=1
Text=

[MeterOpportunity8Graph]
Meter=Shape
Group=OpportunityRow8
X=519
Y=524
W=24
H=23
Hidden=1
DynamicVariables=1
GraphExpanded=0
Shape=Rectangle 0,0,24,23 | Fill Color 0,0,0,1 | StrokeWidth 0
Shape2=Line 7,16,7,7 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape3=Line 7,16,17,16 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape4=Line 8,14,11,11 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape5=Line 11,11,13,13 | StrokeWidth 1 | Stroke Color #ToggleIdle#
Shape6=Line 13,13,17,8 | StrokeWidth 1 | Stroke Color #ToggleIdle#
ToolTipText=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(8)"]

[MeterOpportunity8InlineGraph]
Meter=Image
Group=OpportunityInlineGraph8
X=12
Y=551
W=528
H=125
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleCardExpanded(8)"]
