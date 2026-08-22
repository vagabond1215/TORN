; Opportunity row meters. Positions are updated dynamically by StateReader.lua.
; Each row uses a FlagKit PNG plus a generated local inline-history PNG.
; Inline graph meters intentionally use a separate group so showing a row never
; resurrects a previously collapsed graph image.

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
ToolTipText=

[MeterOpportunity1Flag]
Meter=Image
Group=OpportunityRow1
X=10
Y=123
W=62
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=

[MeterOpportunity1Name]
Meter=String
Group=OpportunityRow1
X=78
Y=126
W=230
Hidden=1
FontFace=Segoe UI Semibold
FontSize=10
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity1Gross]
Meter=String
Group=OpportunityRow1
X=504
Y=126
W=184
StringAlign=Right
Hidden=1
FontFace=Segoe UI Semibold
FontSize=9
FontColor=#Good#
AntiAlias=1
Text=
ToolTipText=

[MeterOpportunity1Window]
Meter=String
Group=OpportunityRow1
X=78
Y=147
W=86
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity1Leave]
Meter=String
Group=OpportunityRow1
X=166
Y=147
W=92
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity1Chance]
Meter=String
Group=OpportunityRow1
X=260
Y=147
W=62
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
Text=

[MeterOpportunity1Price]
Meter=String
Group=OpportunityRow1
X=326
Y=146
W=174
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=
InlinePattern=(\([^\)]+\))$
InlineSetting=Size | 7
InlineSetting2=Color | #Muted#

[MeterOpportunity1Graph]
Meter=String
Group=OpportunityRow1
X=522
Y=145
W=18
StringAlign=Center
Hidden=1
FontFace=Segoe UI Semibold
FontSize=11
FontColor=#Accent#
AntiAlias=1
SolidColor=0,0,0,1
Text=v
ToolTipText=Expand 8-hour stock history in this card
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(1)"]

[MeterOpportunity1InlineGraph]
Meter=Image
Group=OpportunityInlineGraph1
X=58
Y=173
W=470
H=100
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
ToolTipText=

[MeterOpportunity2Flag]
Meter=Image
Group=OpportunityRow2
X=10
Y=177
W=62
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=

[MeterOpportunity2Name]
Meter=String
Group=OpportunityRow2
X=78
Y=180
W=230
Hidden=1
FontFace=Segoe UI Semibold
FontSize=10
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity2Gross]
Meter=String
Group=OpportunityRow2
X=504
Y=180
W=184
StringAlign=Right
Hidden=1
FontFace=Segoe UI Semibold
FontSize=9
FontColor=#Good#
AntiAlias=1
Text=
ToolTipText=

[MeterOpportunity2Window]
Meter=String
Group=OpportunityRow2
X=78
Y=201
W=86
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity2Leave]
Meter=String
Group=OpportunityRow2
X=166
Y=201
W=92
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity2Chance]
Meter=String
Group=OpportunityRow2
X=260
Y=201
W=62
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
Text=

[MeterOpportunity2Price]
Meter=String
Group=OpportunityRow2
X=326
Y=200
W=174
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=
InlinePattern=(\([^\)]+\))$
InlineSetting=Size | 7
InlineSetting2=Color | #Muted#

[MeterOpportunity2Graph]
Meter=String
Group=OpportunityRow2
X=522
Y=199
W=18
StringAlign=Center
Hidden=1
FontFace=Segoe UI Semibold
FontSize=11
FontColor=#Accent#
AntiAlias=1
SolidColor=0,0,0,1
Text=v
ToolTipText=Expand 8-hour stock history in this card
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(2)"]

[MeterOpportunity2InlineGraph]
Meter=Image
Group=OpportunityInlineGraph2
X=58
Y=227
W=470
H=100
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
ToolTipText=

[MeterOpportunity3Flag]
Meter=Image
Group=OpportunityRow3
X=10
Y=231
W=62
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=

[MeterOpportunity3Name]
Meter=String
Group=OpportunityRow3
X=78
Y=234
W=230
Hidden=1
FontFace=Segoe UI Semibold
FontSize=10
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity3Gross]
Meter=String
Group=OpportunityRow3
X=504
Y=234
W=184
StringAlign=Right
Hidden=1
FontFace=Segoe UI Semibold
FontSize=9
FontColor=#Good#
AntiAlias=1
Text=
ToolTipText=

[MeterOpportunity3Window]
Meter=String
Group=OpportunityRow3
X=78
Y=255
W=86
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity3Leave]
Meter=String
Group=OpportunityRow3
X=166
Y=255
W=92
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity3Chance]
Meter=String
Group=OpportunityRow3
X=260
Y=255
W=62
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
Text=

[MeterOpportunity3Price]
Meter=String
Group=OpportunityRow3
X=326
Y=254
W=174
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=
InlinePattern=(\([^\)]+\))$
InlineSetting=Size | 7
InlineSetting2=Color | #Muted#

[MeterOpportunity3Graph]
Meter=String
Group=OpportunityRow3
X=522
Y=253
W=18
StringAlign=Center
Hidden=1
FontFace=Segoe UI Semibold
FontSize=11
FontColor=#Accent#
AntiAlias=1
SolidColor=0,0,0,1
Text=v
ToolTipText=Expand 8-hour stock history in this card
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(3)"]

[MeterOpportunity3InlineGraph]
Meter=Image
Group=OpportunityInlineGraph3
X=58
Y=281
W=470
H=100
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
ToolTipText=

[MeterOpportunity4Flag]
Meter=Image
Group=OpportunityRow4
X=10
Y=285
W=62
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=

[MeterOpportunity4Name]
Meter=String
Group=OpportunityRow4
X=78
Y=288
W=230
Hidden=1
FontFace=Segoe UI Semibold
FontSize=10
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity4Gross]
Meter=String
Group=OpportunityRow4
X=504
Y=288
W=184
StringAlign=Right
Hidden=1
FontFace=Segoe UI Semibold
FontSize=9
FontColor=#Good#
AntiAlias=1
Text=
ToolTipText=

[MeterOpportunity4Window]
Meter=String
Group=OpportunityRow4
X=78
Y=309
W=86
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity4Leave]
Meter=String
Group=OpportunityRow4
X=166
Y=309
W=92
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity4Chance]
Meter=String
Group=OpportunityRow4
X=260
Y=309
W=62
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
Text=

[MeterOpportunity4Price]
Meter=String
Group=OpportunityRow4
X=326
Y=308
W=174
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=
InlinePattern=(\([^\)]+\))$
InlineSetting=Size | 7
InlineSetting2=Color | #Muted#

[MeterOpportunity4Graph]
Meter=String
Group=OpportunityRow4
X=522
Y=307
W=18
StringAlign=Center
Hidden=1
FontFace=Segoe UI Semibold
FontSize=11
FontColor=#Accent#
AntiAlias=1
SolidColor=0,0,0,1
Text=v
ToolTipText=Expand 8-hour stock history in this card
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(4)"]

[MeterOpportunity4InlineGraph]
Meter=Image
Group=OpportunityInlineGraph4
X=58
Y=335
W=470
H=100
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
ToolTipText=

[MeterOpportunity5Flag]
Meter=Image
Group=OpportunityRow5
X=10
Y=339
W=62
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=

[MeterOpportunity5Name]
Meter=String
Group=OpportunityRow5
X=78
Y=342
W=230
Hidden=1
FontFace=Segoe UI Semibold
FontSize=10
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity5Gross]
Meter=String
Group=OpportunityRow5
X=504
Y=342
W=184
StringAlign=Right
Hidden=1
FontFace=Segoe UI Semibold
FontSize=9
FontColor=#Good#
AntiAlias=1
Text=
ToolTipText=

[MeterOpportunity5Window]
Meter=String
Group=OpportunityRow5
X=78
Y=363
W=86
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity5Leave]
Meter=String
Group=OpportunityRow5
X=166
Y=363
W=92
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity5Chance]
Meter=String
Group=OpportunityRow5
X=260
Y=363
W=62
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
Text=

[MeterOpportunity5Price]
Meter=String
Group=OpportunityRow5
X=326
Y=362
W=174
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=
InlinePattern=(\([^\)]+\))$
InlineSetting=Size | 7
InlineSetting2=Color | #Muted#

[MeterOpportunity5Graph]
Meter=String
Group=OpportunityRow5
X=522
Y=361
W=18
StringAlign=Center
Hidden=1
FontFace=Segoe UI Semibold
FontSize=11
FontColor=#Accent#
AntiAlias=1
SolidColor=0,0,0,1
Text=v
ToolTipText=Expand 8-hour stock history in this card
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(5)"]

[MeterOpportunity5InlineGraph]
Meter=Image
Group=OpportunityInlineGraph5
X=58
Y=389
W=470
H=100
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
ToolTipText=

[MeterOpportunity6Flag]
Meter=Image
Group=OpportunityRow6
X=10
Y=393
W=62
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=

[MeterOpportunity6Name]
Meter=String
Group=OpportunityRow6
X=78
Y=396
W=230
Hidden=1
FontFace=Segoe UI Semibold
FontSize=10
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity6Gross]
Meter=String
Group=OpportunityRow6
X=504
Y=396
W=184
StringAlign=Right
Hidden=1
FontFace=Segoe UI Semibold
FontSize=9
FontColor=#Good#
AntiAlias=1
Text=
ToolTipText=

[MeterOpportunity6Window]
Meter=String
Group=OpportunityRow6
X=78
Y=417
W=86
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity6Leave]
Meter=String
Group=OpportunityRow6
X=166
Y=417
W=92
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity6Chance]
Meter=String
Group=OpportunityRow6
X=260
Y=417
W=62
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
Text=

[MeterOpportunity6Price]
Meter=String
Group=OpportunityRow6
X=326
Y=416
W=174
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=
InlinePattern=(\([^\)]+\))$
InlineSetting=Size | 7
InlineSetting2=Color | #Muted#

[MeterOpportunity6Graph]
Meter=String
Group=OpportunityRow6
X=522
Y=415
W=18
StringAlign=Center
Hidden=1
FontFace=Segoe UI Semibold
FontSize=11
FontColor=#Accent#
AntiAlias=1
SolidColor=0,0,0,1
Text=v
ToolTipText=Expand 8-hour stock history in this card
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(6)"]

[MeterOpportunity6InlineGraph]
Meter=Image
Group=OpportunityInlineGraph6
X=58
Y=443
W=470
H=100
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
ToolTipText=

[MeterOpportunity7Flag]
Meter=Image
Group=OpportunityRow7
X=10
Y=447
W=62
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=

[MeterOpportunity7Name]
Meter=String
Group=OpportunityRow7
X=78
Y=450
W=230
Hidden=1
FontFace=Segoe UI Semibold
FontSize=10
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity7Gross]
Meter=String
Group=OpportunityRow7
X=504
Y=450
W=184
StringAlign=Right
Hidden=1
FontFace=Segoe UI Semibold
FontSize=9
FontColor=#Good#
AntiAlias=1
Text=
ToolTipText=

[MeterOpportunity7Window]
Meter=String
Group=OpportunityRow7
X=78
Y=471
W=86
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity7Leave]
Meter=String
Group=OpportunityRow7
X=166
Y=471
W=92
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity7Chance]
Meter=String
Group=OpportunityRow7
X=260
Y=471
W=62
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
Text=

[MeterOpportunity7Price]
Meter=String
Group=OpportunityRow7
X=326
Y=470
W=174
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=
InlinePattern=(\([^\)]+\))$
InlineSetting=Size | 7
InlineSetting2=Color | #Muted#

[MeterOpportunity7Graph]
Meter=String
Group=OpportunityRow7
X=522
Y=469
W=18
StringAlign=Center
Hidden=1
FontFace=Segoe UI Semibold
FontSize=11
FontColor=#Accent#
AntiAlias=1
SolidColor=0,0,0,1
Text=v
ToolTipText=Expand 8-hour stock history in this card
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(7)"]

[MeterOpportunity7InlineGraph]
Meter=Image
Group=OpportunityInlineGraph7
X=58
Y=497
W=470
H=100
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
ToolTipText=

[MeterOpportunity8Flag]
Meter=Image
Group=OpportunityRow8
X=10
Y=501
W=62
H=44
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
ToolTipText=

[MeterOpportunity8Name]
Meter=String
Group=OpportunityRow8
X=78
Y=504
W=230
Hidden=1
FontFace=Segoe UI Semibold
FontSize=10
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=
ToolTipText=

[MeterOpportunity8Gross]
Meter=String
Group=OpportunityRow8
X=504
Y=504
W=184
StringAlign=Right
Hidden=1
FontFace=Segoe UI Semibold
FontSize=9
FontColor=#Good#
AntiAlias=1
Text=
ToolTipText=

[MeterOpportunity8Window]
Meter=String
Group=OpportunityRow8
X=78
Y=525
W=86
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity8Leave]
Meter=String
Group=OpportunityRow8
X=166
Y=525
W=92
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Text#
AntiAlias=1
ClipString=1
Text=

[MeterOpportunity8Chance]
Meter=String
Group=OpportunityRow8
X=260
Y=525
W=62
Hidden=1
FontFace=Segoe UI
FontSize=8
FontColor=#Muted#
AntiAlias=1
Text=

[MeterOpportunity8Price]
Meter=String
Group=OpportunityRow8
X=326
Y=524
W=174
Hidden=1
FontFace=Segoe UI Semibold
FontSize=8
FontColor=#Muted#
AntiAlias=1
ClipString=1
Text=
InlinePattern=(\([^\)]+\))$
InlineSetting=Size | 7
InlineSetting2=Color | #Muted#

[MeterOpportunity8Graph]
Meter=String
Group=OpportunityRow8
X=522
Y=523
W=18
StringAlign=Center
Hidden=1
FontFace=Segoe UI Semibold
FontSize=11
FontColor=#Accent#
AntiAlias=1
SolidColor=0,0,0,1
Text=v
ToolTipText=Expand 8-hour stock history in this card
LeftMouseUpAction=[!CommandMeasure MeasureState "ToggleInlineGraph(8)"]

[MeterOpportunity8InlineGraph]
Meter=Image
Group=OpportunityInlineGraph8
X=58
Y=551
W=470
H=100
PreserveAspectRatio=1
Hidden=1
DynamicVariables=1
ImageName=
