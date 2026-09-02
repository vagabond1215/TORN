; Opportunity card meters. StateReader.lua owns all dynamic Y/height geometry.
; Gross/DetailEach* and DetailTotal* form the optional two-line per-item / total economics bar.
; Inline graphs remain in a separate group so showing a card never resurrects a collapsed graph.

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
ToolTipText=

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

[MeterOpportunity1Gross]
Meter=String
Group=OpportunityRow1
X=14
Y=124
W=250
H=14
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

[MeterOpportunity1DetailTotal]
Meter=String
Group=OpportunityRow1
X=282
Y=124
W=250
H=14
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

[MeterOpportunity1DetailEachNet]
Meter=String
Group=OpportunityRow1
X=14
Y=140
W=120
H=14
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

[MeterOpportunity1DetailEachTax]
Meter=String
Group=OpportunityRow1
X=264
Y=140
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity1DetailTotalNet]
Meter=String
Group=OpportunityRow1
X=282
Y=140
W=120
H=14
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

[MeterOpportunity1DetailTotalTax]
Meter=String
Group=OpportunityRow1
X=532
Y=140
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity1Name]
Meter=String
Group=OpportunityRow1
X=123
Y=126
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=265
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity1Take]
Meter=String
Group=OpportunityRow1
X=123
Y=126
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=108
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=15
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
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
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=

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
ToolTipText=

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

[MeterOpportunity2Gross]
Meter=String
Group=OpportunityRow2
X=14
Y=178
W=250
H=14
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

[MeterOpportunity2DetailTotal]
Meter=String
Group=OpportunityRow2
X=282
Y=178
W=250
H=14
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

[MeterOpportunity2DetailEachNet]
Meter=String
Group=OpportunityRow2
X=14
Y=194
W=120
H=14
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

[MeterOpportunity2DetailEachTax]
Meter=String
Group=OpportunityRow2
X=264
Y=194
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity2DetailTotalNet]
Meter=String
Group=OpportunityRow2
X=282
Y=194
W=120
H=14
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

[MeterOpportunity2DetailTotalTax]
Meter=String
Group=OpportunityRow2
X=532
Y=194
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity2Name]
Meter=String
Group=OpportunityRow2
X=123
Y=180
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=265
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity2Take]
Meter=String
Group=OpportunityRow2
X=123
Y=180
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=108
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=15
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
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
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=

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
ToolTipText=

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

[MeterOpportunity3Gross]
Meter=String
Group=OpportunityRow3
X=14
Y=232
W=250
H=14
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

[MeterOpportunity3DetailTotal]
Meter=String
Group=OpportunityRow3
X=282
Y=232
W=250
H=14
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

[MeterOpportunity3DetailEachNet]
Meter=String
Group=OpportunityRow3
X=14
Y=248
W=120
H=14
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

[MeterOpportunity3DetailEachTax]
Meter=String
Group=OpportunityRow3
X=264
Y=248
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity3DetailTotalNet]
Meter=String
Group=OpportunityRow3
X=282
Y=248
W=120
H=14
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

[MeterOpportunity3DetailTotalTax]
Meter=String
Group=OpportunityRow3
X=532
Y=248
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity3Name]
Meter=String
Group=OpportunityRow3
X=123
Y=234
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=265
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity3Take]
Meter=String
Group=OpportunityRow3
X=123
Y=234
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=108
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=15
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
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
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=

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
ToolTipText=

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

[MeterOpportunity4Gross]
Meter=String
Group=OpportunityRow4
X=14
Y=286
W=250
H=14
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

[MeterOpportunity4DetailTotal]
Meter=String
Group=OpportunityRow4
X=282
Y=286
W=250
H=14
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

[MeterOpportunity4DetailEachNet]
Meter=String
Group=OpportunityRow4
X=14
Y=302
W=120
H=14
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

[MeterOpportunity4DetailEachTax]
Meter=String
Group=OpportunityRow4
X=264
Y=302
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity4DetailTotalNet]
Meter=String
Group=OpportunityRow4
X=282
Y=302
W=120
H=14
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

[MeterOpportunity4DetailTotalTax]
Meter=String
Group=OpportunityRow4
X=532
Y=302
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity4Name]
Meter=String
Group=OpportunityRow4
X=123
Y=288
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=265
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity4Take]
Meter=String
Group=OpportunityRow4
X=123
Y=288
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=108
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=15
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
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
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=

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
ToolTipText=

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

[MeterOpportunity5Gross]
Meter=String
Group=OpportunityRow5
X=14
Y=340
W=250
H=14
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

[MeterOpportunity5DetailTotal]
Meter=String
Group=OpportunityRow5
X=282
Y=340
W=250
H=14
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

[MeterOpportunity5DetailEachNet]
Meter=String
Group=OpportunityRow5
X=14
Y=356
W=120
H=14
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

[MeterOpportunity5DetailEachTax]
Meter=String
Group=OpportunityRow5
X=264
Y=356
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity5DetailTotalNet]
Meter=String
Group=OpportunityRow5
X=282
Y=356
W=120
H=14
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

[MeterOpportunity5DetailTotalTax]
Meter=String
Group=OpportunityRow5
X=532
Y=356
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity5Name]
Meter=String
Group=OpportunityRow5
X=123
Y=342
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=265
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity5Take]
Meter=String
Group=OpportunityRow5
X=123
Y=342
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=108
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=15
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
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
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=

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
ToolTipText=

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

[MeterOpportunity6Gross]
Meter=String
Group=OpportunityRow6
X=14
Y=394
W=250
H=14
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

[MeterOpportunity6DetailTotal]
Meter=String
Group=OpportunityRow6
X=282
Y=394
W=250
H=14
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

[MeterOpportunity6DetailEachNet]
Meter=String
Group=OpportunityRow6
X=14
Y=410
W=120
H=14
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

[MeterOpportunity6DetailEachTax]
Meter=String
Group=OpportunityRow6
X=264
Y=410
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity6DetailTotalNet]
Meter=String
Group=OpportunityRow6
X=282
Y=410
W=120
H=14
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

[MeterOpportunity6DetailTotalTax]
Meter=String
Group=OpportunityRow6
X=532
Y=410
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity6Name]
Meter=String
Group=OpportunityRow6
X=123
Y=396
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=265
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity6Take]
Meter=String
Group=OpportunityRow6
X=123
Y=396
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=108
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=15
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
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
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=

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
ToolTipText=

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

[MeterOpportunity7Gross]
Meter=String
Group=OpportunityRow7
X=14
Y=448
W=250
H=14
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

[MeterOpportunity7DetailTotal]
Meter=String
Group=OpportunityRow7
X=282
Y=448
W=250
H=14
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

[MeterOpportunity7DetailEachNet]
Meter=String
Group=OpportunityRow7
X=14
Y=464
W=120
H=14
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

[MeterOpportunity7DetailEachTax]
Meter=String
Group=OpportunityRow7
X=264
Y=464
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity7DetailTotalNet]
Meter=String
Group=OpportunityRow7
X=282
Y=464
W=120
H=14
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

[MeterOpportunity7DetailTotalTax]
Meter=String
Group=OpportunityRow7
X=532
Y=464
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity7Name]
Meter=String
Group=OpportunityRow7
X=123
Y=450
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=265
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity7Take]
Meter=String
Group=OpportunityRow7
X=123
Y=450
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=108
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=15
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
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
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=

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
ToolTipText=

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

[MeterOpportunity8Gross]
Meter=String
Group=OpportunityRow8
X=14
Y=502
W=250
H=14
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

[MeterOpportunity8DetailTotal]
Meter=String
Group=OpportunityRow8
X=282
Y=502
W=250
H=14
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

[MeterOpportunity8DetailEachNet]
Meter=String
Group=OpportunityRow8
X=14
Y=518
W=120
H=14
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

[MeterOpportunity8DetailEachTax]
Meter=String
Group=OpportunityRow8
X=264
Y=518
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity8DetailTotalNet]
Meter=String
Group=OpportunityRow8
X=282
Y=518
W=120
H=14
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

[MeterOpportunity8DetailTotalTax]
Meter=String
Group=OpportunityRow8
X=532
Y=518
W=120
H=14
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=9
FontColor=#Muted#
StringAlign=RightCenter
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity8Name]
Meter=String
Group=OpportunityRow8
X=123
Y=504
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=265
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity8Take]
Meter=String
Group=OpportunityRow8
X=123
Y=504
W=1
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=11
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
W=108
Hidden=1
DynamicVariables=1
FontFace=Nirmala UI Semilight
FontSize=15
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=
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
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
SolidColor=0,0,0,1
Text=
ToolTipText=

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
