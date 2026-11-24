"use strict";
// Factual course data and condensed outcomes from official Torn Wiki degree tables, checked 2026-11-24.
// DEF2760 cost omitted because the wiki has an ambiguous amount. Pistol code matched by name in renderer.
const tornEducationReference={
  "BIO1340": {
    "cost": 200,
    "working_stats": {
      "manual_labor": 5,
      "intelligence": 50,
      "endurance": 5
    },
    "duration": 604800,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Biology"
  },
  "BIO2350": {
    "cost": 2000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 50,
      "endurance": 10
    },
    "duration": 1209600,
    "effects": [
      "+1% weapon damage"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Biology"
  },
  "BIO2360": {
    "cost": 2500,
    "working_stats": {
      "manual_labor": 5,
      "intelligence": 55,
      "endurance": 15
    },
    "duration": 2419200,
    "effects": [
      "+10% medical item effectiveness"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Biology"
  },
  "BIO2370": {
    "cost": 2750,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 65,
      "endurance": 10
    },
    "duration": 2419200,
    "effects": [
      "Additional 10% medical item effectiveness"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Biology"
  },
  "BIO2380": {
    "cost": 2800,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 65,
      "endurance": 15
    },
    "duration": 1814400,
    "effects": [
      "+10% throat-hit damage"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Biology"
  },
  "BIO2390": {
    "cost": 900,
    "working_stats": {
      "manual_labor": 5,
      "intelligence": 170,
      "endurance": 120
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Biology"
  },
  "BIO2400": {
    "cost": 3000,
    "working_stats": {
      "manual_labor": 10,
      "intelligence": 80,
      "endurance": 20
    },
    "duration": 2419200,
    "effects": [
      "Opponent stealth reduced by 0.5"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Biology"
  },
  "BIO2410": {
    "cost": 3500,
    "working_stats": {
      "manual_labor": 15,
      "intelligence": 75,
      "endurance": 20
    },
    "duration": 1814400,
    "effects": [
      "+3% critical hit chance"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Biology"
  },
  "BIO2127": {
    "cost": 3500,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 40,
      "endurance": 35
    },
    "duration": 1814400,
    "effects": [
      "Unlock blood withdrawal and transfusion"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Biology"
  },
  "BIO3420": {
    "cost": 5000,
    "working_stats": {
      "manual_labor": 25,
      "intelligence": 75,
      "endurance": 30
    },
    "duration": 3024000,
    "effects": [
      "Unlock temporary-slot needles"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Biology"
  },
  "BUS1100": {
    "cost": 200,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 50,
      "endurance": 10
    },
    "duration": 604800,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "BUS2200": {
    "cost": 500,
    "working_stats": {
      "manual_labor": 5,
      "intelligence": 60,
      "endurance": 25
    },
    "duration": 1209600,
    "effects": [
      "+2% company productivity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "BUS2300": {
    "cost": 600,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 65,
      "endurance": 20
    },
    "duration": 1209600,
    "effects": [
      "+5% employee effectiveness"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "BUS2400": {
    "cost": 800,
    "working_stats": {
      "manual_labor": 15,
      "intelligence": 75,
      "endurance": 15
    },
    "duration": 1814400,
    "effects": [
      "Improved company advertising effectiveness"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "BUS2500": {
    "cost": 500,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 80,
      "endurance": 20
    },
    "duration": 1209600,
    "effects": [
      "+2% company productivity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "BUS2600": {
    "cost": 1000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 95,
      "endurance": 10
    },
    "duration": 2419200,
    "effects": [
      "+7% employee effectiveness"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "BUS2700": {
    "cost": 800,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 75,
      "endurance": 20
    },
    "duration": 2419200,
    "effects": [
      "+10% perceived product value"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "BUS2800": {
    "cost": 500,
    "working_stats": {
      "manual_labor": 25,
      "intelligence": 50,
      "endurance": 15
    },
    "duration": 1209600,
    "effects": [
      "+2% company productivity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "BUS2900": {
    "cost": 750,
    "working_stats": {
      "manual_labor": 10,
      "intelligence": 60,
      "endurance": 15
    },
    "duration": 1814400,
    "effects": [
      "+5% perceived product value"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "BUS2100": {
    "cost": 600,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 60,
      "endurance": 15
    },
    "duration": 1814400,
    "effects": [
      "+2% company productivity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "BUS2110": {
    "cost": 750,
    "working_stats": {
      "manual_labor": 20,
      "intelligence": 50,
      "endurance": 15
    },
    "duration": 1814400,
    "effects": [
      "Passive employee working-stat bonus"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "BUS2120": {
    "cost": 800,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 50,
      "endurance": 40
    },
    "duration": 1814400,
    "effects": [
      "+2% company productivity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "BUS3130": {
    "cost": 5000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 100,
      "endurance": 0
    },
    "duration": 3024000,
    "effects": [
      "Unlock company size, storage and staff room upgrades"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Business_Management"
  },
  "CBT1780": {
    "cost": 200,
    "working_stats": {
      "manual_labor": 50,
      "intelligence": 50,
      "endurance": 0
    },
    "duration": 604800,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Combat_Training"
  },
  "CBT2790": {
    "cost": 1200,
    "working_stats": {
      "manual_labor": 45,
      "intelligence": 55,
      "endurance": 0
    },
    "duration": 1209600,
    "effects": [
      "+1% passive speed"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Combat_Training"
  },
  "CBT2800": {
    "cost": 1250,
    "working_stats": {
      "manual_labor": 20,
      "intelligence": 95,
      "endurance": 0
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Combat_Training"
  },
  "CBT2810": {
    "cost": 1300,
    "working_stats": {
      "manual_labor": 20,
      "intelligence": 110,
      "endurance": 0
    },
    "duration": 2419200,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Combat_Training"
  },
  "CBT2820": {
    "cost": 3500,
    "working_stats": {
      "manual_labor": 30,
      "intelligence": 70,
      "endurance": 0
    },
    "duration": 1209600,
    "effects": [
      "+1 accuracy with machine guns"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Combat_Training"
  },
  "CBT2830": {
    "cost": 3500,
    "working_stats": {
      "manual_labor": 30,
      "intelligence": 70,
      "endurance": 0
    },
    "duration": 1209600,
    "effects": [
      "+1 accuracy with submachine guns"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Combat_Training"
  },
  "CBT2840": {
    "cost": 3500,
    "working_stats": {
      "manual_labor": 30,
      "intelligence": 70,
      "endurance": 0
    },
    "duration": 1209600,
    "effects": [
      "+1 pistol accuracy"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Combat_Training"
  },
  "CBT2850": {
    "cost": 3500,
    "working_stats": {
      "manual_labor": 30,
      "intelligence": 70,
      "endurance": 0
    },
    "duration": 1209600,
    "effects": [
      "+1 rifle accuracy"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Combat_Training"
  },
  "CBT2860": {
    "cost": 3500,
    "working_stats": {
      "manual_labor": 30,
      "intelligence": 70,
      "endurance": 0
    },
    "duration": 1209600,
    "effects": [
      "+1 heavy artillery accuracy"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Combat_Training"
  },
  "CBT2125": {
    "cost": 3500,
    "working_stats": {
      "manual_labor": 30,
      "intelligence": 70,
      "endurance": 0
    },
    "duration": 1209600,
    "effects": [
      "+1 shotgun accuracy"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Combat_Training"
  },
  "CBT3870": {
    "cost": 5000,
    "working_stats": {
      "manual_labor": 75,
      "intelligence": 75,
      "endurance": 0
    },
    "duration": 4233600,
    "effects": [
      "Unlock weapon experience"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Combat_Training"
  },
  "CMT1520": {
    "cost": 200,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 45,
      "endurance": 50
    },
    "duration": 604800,
    "effects": [
      "Unlock Cracking and simple virus coding"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2230": {
    "cost": 300,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 35,
      "endurance": 20
    },
    "duration": 604800,
    "effects": [
      "Website creation for Bootlegging and Scamming"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2530": {
    "cost": 800,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 65,
      "endurance": 20
    },
    "duration": 1209600,
    "effects": [
      "Polymorphic and tunneling virus coding"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2560": {
    "cost": 1200,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 100,
      "endurance": 50
    },
    "duration": 1814400,
    "effects": [
      "Armored, stealth and Firewalk virus coding"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2130": {
    "cost": 1000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 40,
      "endurance": 15
    },
    "duration": 604800,
    "effects": [
      "In-game Scamming data-breach address collection"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2131": {
    "cost": 1000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 85,
      "endurance": 60
    },
    "duration": 1209600,
    "effects": [
      "In-game Scamming website address collection"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2540": {
    "cost": 900,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 75,
      "endurance": 35
    },
    "duration": 1209600,
    "effects": [
      "Unlock hacking crimes"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2610": {
    "cost": 3200,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 175,
      "endurance": 55
    },
    "duration": 2419200,
    "effects": [
      "+10% hacking crime success"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2550": {
    "cost": 850,
    "working_stats": {
      "manual_labor": 25,
      "intelligence": 90,
      "endurance": 55
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2570": {
    "cost": 1500,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 150,
      "endurance": 95
    },
    "duration": 1209600,
    "effects": [
      "−25% rig heat generation"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2128": {
    "cost": 500,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 25,
      "endurance": 15
    },
    "duration": 604800,
    "effects": [
      "Rig overclocking up to 30%"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2129": {
    "cost": 500,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 30,
      "endurance": 20
    },
    "duration": 604800,
    "effects": [
      "Rig overclocking up to 50%"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2580": {
    "cost": 2200,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 120,
      "endurance": 65
    },
    "duration": 1814400,
    "effects": [
      "−20% virus coding time"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2590": {
    "cost": 1950,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 250,
      "endurance": 30
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT2600": {
    "cost": 2350,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 275,
      "endurance": 55
    },
    "duration": 1814400,
    "effects": [
      "−10% virus coding time"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "CMT3620": {
    "cost": 5000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 115,
      "endurance": 25
    },
    "duration": 4233600,
    "effects": [
      "Anonymous mail and cash transfers"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Computer_Science"
  },
  "GEN1112": {
    "cost": 200,
    "working_stats": {
      "manual_labor": 25,
      "intelligence": 25,
      "endurance": 25
    },
    "duration": 604800,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:General_Studies"
  },
  "GEN2113": {
    "cost": 1500,
    "working_stats": {
      "manual_labor": 25,
      "intelligence": 35,
      "endurance": 10
    },
    "duration": 1209600,
    "effects": [
      "Driving-related legacy crimes; not a racing license"
    ],
    "source": "https://wiki.torn.com/wiki/Education:General_Studies"
  },
  "GEN2114": {
    "cost": 500,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 75,
      "endurance": 15
    },
    "duration": 604800,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:General_Studies"
  },
  "GEN2115": {
    "cost": 600,
    "working_stats": {
      "manual_labor": 45,
      "intelligence": 75,
      "endurance": 45
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:General_Studies"
  },
  "GEN2116": {
    "cost": 1500,
    "working_stats": {
      "manual_labor": 25,
      "intelligence": 35,
      "endurance": 10
    },
    "duration": 1209600,
    "effects": [
      "+1 temporary weapon accuracy"
    ],
    "source": "https://wiki.torn.com/wiki/Education:General_Studies"
  },
  "GEN2117": {
    "cost": 890,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 75,
      "endurance": 15
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:General_Studies"
  },
  "GEN2118": {
    "cost": 895,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 85,
      "endurance": 20
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:General_Studies"
  },
  "GEN2119": {
    "cost": 1200,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 100,
      "endurance": 20
    },
    "duration": 1814400,
    "effects": [
      "+5% temporary weapon damage"
    ],
    "source": "https://wiki.torn.com/wiki/Education:General_Studies"
  },
  "GEN2120": {
    "cost": 725,
    "working_stats": {
      "manual_labor": 75,
      "intelligence": 45,
      "endurance": 55
    },
    "duration": 1209600,
    "effects": [
      "+15% hunting bonus"
    ],
    "source": "https://wiki.torn.com/wiki/Education:General_Studies"
  },
  "GEN2122": {
    "cost": 2500,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 125,
      "endurance": 25
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:General_Studies"
  },
  "GEN2123": {
    "cost": 3500,
    "working_stats": {
      "manual_labor": 40,
      "intelligence": 60,
      "endurance": 20
    },
    "duration": 1814400,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:General_Studies"
  },
  "GEN3121": {
    "cost": 5000,
    "working_stats": {
      "manual_labor": 75,
      "intelligence": 25,
      "endurance": 35
    },
    "duration": 4233600,
    "effects": [
      "+10% working stats from future courses"
    ],
    "source": "https://wiki.torn.com/wiki/Education:General_Studies"
  },
  "HAF1103": {
    "cost": 200,
    "working_stats": {
      "manual_labor": 75,
      "intelligence": 0,
      "endurance": 15
    },
    "duration": 604800,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:_Health_&_Fitness"
  },
  "HAF2104": {
    "cost": 900,
    "working_stats": {
      "manual_labor": 65,
      "intelligence": 0,
      "endurance": 20
    },
    "duration": 1209600,
    "effects": [
      "+1% passive dexterity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:_Health_&_Fitness"
  },
  "HAF2105": {
    "cost": 1000,
    "working_stats": {
      "manual_labor": 65,
      "intelligence": 0,
      "endurance": 15
    },
    "duration": 1209600,
    "effects": [
      "+1% passive speed"
    ],
    "source": "https://wiki.torn.com/wiki/Education:_Health_&_Fitness"
  },
  "HAF2106": {
    "cost": 1150,
    "working_stats": {
      "manual_labor": 125,
      "intelligence": 0,
      "endurance": 25
    },
    "duration": 1209600,
    "effects": [
      "+1% passive strength"
    ],
    "source": "https://wiki.torn.com/wiki/Education:_Health_&_Fitness"
  },
  "HAF2107": {
    "cost": 1200,
    "working_stats": {
      "manual_labor": 75,
      "intelligence": 0,
      "endurance": 45
    },
    "duration": 1209600,
    "effects": [
      "+2% passive strength"
    ],
    "source": "https://wiki.torn.com/wiki/Education:_Health_&_Fitness"
  },
  "HAF2108": {
    "cost": 1500,
    "working_stats": {
      "manual_labor": 95,
      "intelligence": 0,
      "endurance": 25
    },
    "duration": 1209600,
    "effects": [
      "+1% passive dexterity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:_Health_&_Fitness"
  },
  "HAF2109": {
    "cost": 2000,
    "working_stats": {
      "manual_labor": 150,
      "intelligence": 0,
      "endurance": 75
    },
    "duration": 2419200,
    "effects": [
      "+3% passive speed"
    ],
    "source": "https://wiki.torn.com/wiki/Education:_Health_&_Fitness"
  },
  "HAF2110": {
    "cost": 3500,
    "working_stats": {
      "manual_labor": 65,
      "intelligence": 0,
      "endurance": 45
    },
    "duration": 1814400,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:_Health_&_Fitness"
  },
  "HAF3111": {
    "cost": 5000,
    "working_stats": {
      "manual_labor": 75,
      "intelligence": 20,
      "endurance": 65
    },
    "duration": 3024000,
    "effects": [
      "+25% speed during opponent escape attempts"
    ],
    "source": "https://wiki.torn.com/wiki/Education:_Health_&_Fitness"
  },
  "HIS1140": {
    "cost": 200,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 30,
      "endurance": 25
    },
    "duration": 604800,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:History"
  },
  "HIS2150": {
    "cost": 500,
    "working_stats": {
      "manual_labor": 15,
      "intelligence": 135,
      "endurance": 75
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:History"
  },
  "HIS2160": {
    "cost": 950,
    "working_stats": {
      "manual_labor": 20,
      "intelligence": 15,
      "endurance": 20
    },
    "duration": 1814400,
    "effects": [
      "+10% Japanese blade damage"
    ],
    "source": "https://wiki.torn.com/wiki/Education:History"
  },
  "HIS2170": {
    "cost": 950,
    "working_stats": {
      "manual_labor": 25,
      "intelligence": 15,
      "endurance": 25
    },
    "duration": 2419200,
    "effects": [
      "+2% melee damage"
    ],
    "source": "https://wiki.torn.com/wiki/Education:History"
  },
  "HIS2180": {
    "cost": 850,
    "working_stats": {
      "manual_labor": 35,
      "intelligence": 10,
      "endurance": 40
    },
    "duration": 1814400,
    "effects": [
      "Unlock medieval coin finds"
    ],
    "source": "https://wiki.torn.com/wiki/Education:History"
  },
  "HIS2190": {
    "cost": 850,
    "working_stats": {
      "manual_labor": 15,
      "intelligence": 35,
      "endurance": 35
    },
    "duration": 1814400,
    "effects": [
      "Unlock Asian sculptures and Quran page finds"
    ],
    "source": "https://wiki.torn.com/wiki/Education:History"
  },
  "HIS2200": {
    "cost": 850,
    "working_stats": {
      "manual_labor": 10,
      "intelligence": 35,
      "endurance": 45
    },
    "duration": 1814400,
    "effects": [
      "Unlock Senet pieces and amulet finds"
    ],
    "source": "https://wiki.torn.com/wiki/Education:History"
  },
  "HIS3210": {
    "cost": 5000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 50,
      "endurance": 55
    },
    "duration": 3628800,
    "effects": [
      "Unlock museum exchanges for points"
    ],
    "source": "https://wiki.torn.com/wiki/Education:History"
  },
  "LAW1880": {
    "cost": 200,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 50,
      "endurance": 25
    },
    "duration": 604800,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2890": {
    "cost": 1500,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 45,
      "endurance": 25
    },
    "duration": 1209600,
    "effects": [
      "Lower jail escape detection chance"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2900": {
    "cost": 2000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 65,
      "endurance": 15
    },
    "duration": 1814400,
    "effects": [
      "Allow bail payments while jailed"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2910": {
    "cost": 2000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 75,
      "endurance": 25
    },
    "duration": 1209600,
    "effects": [
      "5% estate agent property discount"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2920": {
    "cost": 1000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 75,
      "endurance": 15
    },
    "duration": 1209600,
    "effects": [
      "+5% busting skill"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2930": {
    "cost": 1500,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 85,
      "endurance": 10
    },
    "duration": 1209600,
    "effects": [
      "5% bail discount"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2940": {
    "cost": 900,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 120,
      "endurance": 35
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2950": {
    "cost": 850,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 125,
      "endurance": 25
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2960": {
    "cost": 1050,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 135,
      "endurance": 20
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2970": {
    "cost": 1780,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 80,
      "endurance": 20
    },
    "duration": 1814400,
    "effects": [
      "+10% busting skill"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2980": {
    "cost": 2490,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 75,
      "endurance": 20
    },
    "duration": 1814400,
    "effects": [
      "10% bail discount"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2990": {
    "cost": 2925,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 70,
      "endurance": 25
    },
    "duration": 1814400,
    "effects": [
      "Reduced nerve cost for jail escapes"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2100": {
    "cost": 2350,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 85,
      "endurance": 20
    },
    "duration": 1814400,
    "effects": [
      "Improved company advertising effectiveness"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW2101": {
    "cost": 3200,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 175,
      "endurance": 40
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "LAW3102": {
    "cost": 5000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 125,
      "endurance": 20
    },
    "duration": 3628800,
    "effects": [
      "50% easier busting; 50% cheaper bail"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Law"
  },
  "MTH1220": {
    "cost": 200,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 35,
      "endurance": 10
    },
    "duration": 604800,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Mathematics"
  },
  "MTH2240": {
    "cost": 1000,
    "working_stats": {
      "manual_labor": 10,
      "intelligence": 40,
      "endurance": 15
    },
    "duration": 1814400,
    "effects": [
      "+1% passive speed"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Mathematics"
  },
  "MTH2250": {
    "cost": 1100,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 50,
      "endurance": 15
    },
    "duration": 1814400,
    "effects": [
      "+1% passive speed"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Mathematics"
  },
  "MTH2260": {
    "cost": 1150,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 55,
      "endurance": 20
    },
    "duration": 1814400,
    "effects": [
      "+1% passive defense"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Mathematics"
  },
  "MTH2320": {
    "cost": 1100,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 120,
      "endurance": 35
    },
    "duration": 1814400,
    "effects": [
      "+2% passive defense"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Mathematics"
  },
  "MTH2270": {
    "cost": 500,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 165,
      "endurance": 15
    },
    "duration": 1209600,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Mathematics"
  },
  "MTH2280": {
    "cost": 980,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 75,
      "endurance": 20
    },
    "duration": 1814400,
    "effects": [
      "+1% company productivity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Mathematics"
  },
  "MTH2290": {
    "cost": 1000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 100,
      "endurance": 145
    },
    "duration": 1814400,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Mathematics"
  },
  "MTH2300": {
    "cost": 800,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 120,
      "endurance": 95
    },
    "duration": 2419200,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Mathematics"
  },
  "MTH2310": {
    "cost": 1250,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 80,
      "endurance": 25
    },
    "duration": 2419200,
    "effects": [
      "+5% ammo conservation"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Mathematics"
  },
  "MTH3330": {
    "cost": 5000,
    "working_stats": {
      "manual_labor": 10,
      "intelligence": 50,
      "endurance": 40
    },
    "duration": 3628800,
    "effects": [
      "+20% ammo conservation"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Mathematics"
  },
  "PSY1630": {
    "cost": 200,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 50,
      "endurance": 0
    },
    "duration": 604800,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Psychology"
  },
  "PSY2640": {
    "cost": 900,
    "working_stats": {
      "manual_labor": 65,
      "intelligence": 100,
      "endurance": 0
    },
    "duration": 1209600,
    "effects": [
      "+1% passive dexterity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Psychology"
  },
  "PSY2650": {
    "cost": 1100,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 80,
      "endurance": 15
    },
    "duration": 1814400,
    "effects": [
      "+2% passive dexterity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Psychology"
  },
  "PSY2660": {
    "cost": 1150,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 100,
      "endurance": 10
    },
    "duration": 1814400,
    "effects": [
      "+4% passive dexterity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Psychology"
  },
  "PSY2670": {
    "cost": 1500,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 125,
      "endurance": 0
    },
    "duration": 2419200,
    "effects": [
      "+8% passive dexterity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Psychology"
  },
  "PSY2680": {
    "cost": 2330,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 115,
      "endurance": 0
    },
    "duration": 2419200,
    "effects": [
      "+10% awareness"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Psychology"
  },
  "PSY2132": {
    "cost": 1000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 70,
      "endurance": 0
    },
    "duration": 604800,
    "effects": [
      "Scamming response range indicators"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Psychology"
  },
  "PSY3690": {
    "cost": 5000,
    "working_stats": {
      "manual_labor": 0,
      "intelligence": 120,
      "endurance": 0
    },
    "duration": 4233600,
    "effects": [
      "+10% crime experience and skill progression"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Psychology"
  },
  "DEF1700": {
    "cost": 200,
    "working_stats": {
      "manual_labor": 50,
      "intelligence": 50,
      "endurance": 50
    },
    "duration": 604800,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Self_Defence"
  },
  "DEF2710": {
    "cost": 1000,
    "working_stats": {
      "manual_labor": 65,
      "intelligence": 0,
      "endurance": 50
    },
    "duration": 1814400,
    "effects": [
      "+1% passive defense"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Self_Defence"
  },
  "DEF2720": {
    "cost": 1500,
    "working_stats": {
      "manual_labor": 75,
      "intelligence": 0,
      "endurance": 45
    },
    "duration": 1209600,
    "effects": [
      "Unlock kick attacks"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Self_Defence"
  },
  "DEF2730": {
    "cost": 2500,
    "working_stats": {
      "manual_labor": 90,
      "intelligence": 0,
      "endurance": 75
    },
    "duration": 2419200,
    "effects": [
      "+2% passive defense"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Self_Defence"
  },
  "DEF2740": {
    "cost": 1800,
    "working_stats": {
      "manual_labor": 75,
      "intelligence": 0,
      "endurance": 70
    },
    "duration": 1209600,
    "effects": [
      "+3% passive defense"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Self_Defence"
  },
  "DEF2750": {
    "cost": 2000,
    "working_stats": {
      "manual_labor": 80,
      "intelligence": 0,
      "endurance": 45
    },
    "duration": 1209600,
    "effects": [
      "+2% passive speed"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Self_Defence"
  },
  "DEF2760": {
    "cost": null,
    "working_stats": {
      "manual_labor": 100,
      "intelligence": 0,
      "endurance": 75
    },
    "duration": 1814400,
    "effects": [
      "+3% passive speed"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Self_Defence"
  },
  "DEF3770": {
    "cost": 5000,
    "working_stats": {
      "manual_labor": 150,
      "intelligence": 10,
      "endurance": 75
    },
    "duration": 3024000,
    "effects": [
      "Double fist-only damage"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Self_Defence"
  },
  "SPT1430": {
    "cost": 200,
    "working_stats": {
      "manual_labor": 50,
      "intelligence": 0,
      "endurance": 10
    },
    "duration": 604800,
    "effects": [],
    "source": "https://wiki.torn.com/wiki/Education:Sports_Science"
  },
  "SPT2440": {
    "cost": 1150,
    "working_stats": {
      "manual_labor": 55,
      "intelligence": 5,
      "endurance": 15
    },
    "duration": 1814400,
    "effects": [
      "+1% strength gym gains"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Sports_Science"
  },
  "SPT2450": {
    "cost": 1200,
    "working_stats": {
      "manual_labor": 45,
      "intelligence": 0,
      "endurance": 55
    },
    "duration": 1814400,
    "effects": [
      "+1% speed gym gains"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Sports_Science"
  },
  "SPT2460": {
    "cost": 1500,
    "working_stats": {
      "manual_labor": 60,
      "intelligence": 5,
      "endurance": 45
    },
    "duration": 1209600,
    "effects": [
      "+1% defense gym gains"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Sports_Science"
  },
  "SPT2470": {
    "cost": 1750,
    "working_stats": {
      "manual_labor": 55,
      "intelligence": 10,
      "endurance": 35
    },
    "duration": 1814400,
    "effects": [
      "+1% dexterity gym gains"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Sports_Science"
  },
  "SPT2480": {
    "cost": 2250,
    "working_stats": {
      "manual_labor": 15,
      "intelligence": 75,
      "endurance": 15
    },
    "duration": 2419200,
    "effects": [
      "+10% needle effectiveness"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Sports_Science"
  },
  "SPT2490": {
    "cost": 2500,
    "working_stats": {
      "manual_labor": 10,
      "intelligence": 65,
      "endurance": 15
    },
    "duration": 1814400,
    "effects": [
      "+2% passive speed and strength"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Sports_Science"
  },
  "SPT2500": {
    "cost": 2880,
    "working_stats": {
      "manual_labor": 65,
      "intelligence": 5,
      "endurance": 15
    },
    "duration": 1814400,
    "effects": [
      "+2% passive defense and dexterity"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Sports_Science"
  },
  "SPT2126": {
    "cost": 400,
    "working_stats": {
      "manual_labor": 20,
      "intelligence": 5,
      "endurance": 30
    },
    "duration": 604800,
    "effects": [
      "Unlock sports shop"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Sports_Science"
  },
  "SPT3510": {
    "cost": 5000,
    "working_stats": {
      "manual_labor": 95,
      "intelligence": 15,
      "endurance": 65
    },
    "duration": 3628800,
    "effects": [
      "Additional 1% all gym gains"
    ],
    "source": "https://wiki.torn.com/wiki/Education:Sports_Science"
  }
};
