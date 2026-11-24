"use strict";
/* Current 39 company types and their star-unlocked job specials.
 * Factual table fields transcribed from the official Torn company catalog,
 * checked 2026-11-23. Playstyle tags are editorial recommendations, not Torn metadata.
 */
const tornCompanyCatalog=[
  {
    "name": "Adult Novelties",
    "styles": [
      "Training",
      "Money",
      "War",
      "Beginner"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Blackmail",
        "cost": "1",
        "effect": "Money"
      },
      {
        "stars": 3,
        "name": "Voyeur",
        "cost": "20",
        "effect": "Erotic DVD"
      },
      {
        "stars": 5,
        "name": "Party Supplies",
        "cost": "500",
        "effect": "Pack of Trojans"
      },
      {
        "stars": 7,
        "name": "Bondage",
        "cost": "Passive",
        "effect": "25% enemy speed reduction"
      },
      {
        "stars": 10,
        "name": "Indecent",
        "cost": "Passive",
        "effect": "100% bonus to Erotic DVDs"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Amusement Park",
    "styles": [
      "Crime",
      "War",
      "Training"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Dauntless",
        "cost": "1",
        "effect": "+2 nerve"
      },
      {
        "stars": 3,
        "name": "Free Ride",
        "cost": "10",
        "effect": "250 happiness for target"
      },
      {
        "stars": 5,
        "name": "Unflinching",
        "cost": "Passive",
        "effect": "10 maximum nerve"
      },
      {
        "stars": 7,
        "name": "Adrenaline Rush",
        "cost": "Passive",
        "effect": "25% epinephrine effect & duration"
      },
      {
        "stars": 10,
        "name": "Thrill Seeker",
        "cost": "Passive",
        "effect": "10% crime exp & skill gain"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Candle Shop",
    "styles": [
      "Training",
      "Crime",
      "Revive",
      "Beginner",
      "War"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Warming Therapy",
        "cost": "1",
        "effect": "50 happiness"
      },
      {
        "stars": 3,
        "name": "Illumination",
        "cost": "Passive",
        "effect": "50% awareness"
      },
      {
        "stars": 5,
        "name": "Calming Therapy",
        "cost": "1",
        "effect": "2 nerve"
      },
      {
        "stars": 7,
        "name": "Reinvigorating Therapy",
        "cost": "1",
        "effect": "5 energy"
      },
      {
        "stars": 10,
        "name": "Meditation",
        "cost": "250",
        "effect": "View someone's true level if they are level holding"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Car Dealership",
    "styles": [
      "Racing",
      "Trade",
      "Crime",
      "War"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Test Drive",
        "cost": "5",
        "effect": "Racing point"
      },
      {
        "stars": 3,
        "name": "Discount parts",
        "cost": "Passive",
        "effect": "75% cost discount on car parts"
      },
      {
        "stars": 5,
        "name": "Salesman",
        "cost": "Passive",
        "effect": "Waive anonymous item market listing fee"
      },
      {
        "stars": 7,
        "name": "Two-Faced",
        "cost": "Passive",
        "effect": "15% fraud crime exp & skill gain"
      },
      {
        "stars": 10,
        "name": "Getaway car",
        "cost": "Passive",
        "effect": "Escape button always enabled"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Clothing Store",
    "styles": [
      "Trade",
      "War",
      "Mug",
      "Beginner"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Fashion Show",
        "cost": "1",
        "effect": "Experience"
      },
      {
        "stars": 3,
        "name": "Nine to five",
        "cost": "10",
        "effect": "100 Endurance"
      },
      {
        "stars": 5,
        "name": "Activewear",
        "cost": "Passive",
        "effect": "+25% Passive Dexterity"
      },
      {
        "stars": 7,
        "name": "Secret pockets",
        "cost": "Passive",
        "effect": "+75% Mug Protection"
      },
      {
        "stars": 10,
        "name": "Tailoring",
        "cost": "Passive",
        "effect": "+20% Armor Bonus"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Cruise Line",
    "styles": [
      "Travel",
      "Trade",
      "Training"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Bursar",
        "cost": "1",
        "effect": "25 casino tokens"
      },
      {
        "stars": 3,
        "name": "Portage",
        "cost": "Passive",
        "effect": "2 extra travel items"
      },
      {
        "stars": 5,
        "name": "R&R",
        "cost": "1",
        "effect": "Drug addiction reduction"
      },
      {
        "stars": 7,
        "name": "Destination Report",
        "cost": "1",
        "effect": "View stock analysis of all items at a selected country"
      },
      {
        "stars": 10,
        "name": "Freight",
        "cost": "Passive",
        "effect": "3 extra travel items"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Cyber Cafe",
    "styles": [
      "Crime",
      "Business",
      "Money",
      "Mug"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Ub3rg33k",
        "cost": "Passive",
        "effect": "50% virus coding time reduction"
      },
      {
        "stars": 3,
        "name": "Clone Data",
        "cost": "25",
        "effect": "Virus"
      },
      {
        "stars": 5,
        "name": "Proxy Hacking",
        "cost": "25",
        "effect": "Cancel a target's virus programming"
      },
      {
        "stars": 7,
        "name": "IP Tracing",
        "cost": "25",
        "effect": "View lister of anonymous bounties"
      },
      {
        "stars": 10,
        "name": "Financial Phishing",
        "cost": "25",
        "effect": "View details of someone's investment account"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Detective Agency",
    "styles": [
      "Crime",
      "Mug",
      "Travel",
      "War"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "References",
        "cost": "2",
        "effect": "View someone's employment and faction history"
      },
      {
        "stars": 3,
        "name": "Deputized",
        "cost": "Passive",
        "effect": "Able to Arrest those who meet the required threshold after defeat"
      },
      {
        "stars": 5,
        "name": "Friend or Foe",
        "cost": "100",
        "effect": "See who's friended / blacklisted you"
      },
      {
        "stars": 7,
        "name": "Watchlist",
        "cost": "50",
        "effect": "Anonymously extend a target's flight time by 1:30 - 2:00 hours"
      },
      {
        "stars": 10,
        "name": "Most Wanted",
        "cost": "25",
        "effect": "View a list of people with the highest wanted rewards"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Farm",
    "styles": [
      "Revive",
      "Training",
      "Money",
      "Travel",
      "War"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Fullfillment",
        "cost": "1",
        "effect": "50 happiness"
      },
      {
        "stars": 3,
        "name": "Animal Instinct",
        "cost": "Passive",
        "effect": "25% hunting reward"
      },
      {
        "stars": 5,
        "name": "Special K",
        "cost": "5",
        "effect": "Ketamine drug"
      },
      {
        "stars": 7,
        "name": "Fertilizer",
        "cost": "100",
        "effect": "Small Explosive Device"
      },
      {
        "stars": 10,
        "name": "Early Riser",
        "cost": "1",
        "effect": "7 energy"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Firework Stand",
    "styles": [
      "Crime",
      "War",
      "Beginner"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Audaciousness",
        "cost": "1",
        "effect": "+2 Nerve"
      },
      {
        "stars": 3,
        "name": "Illumination",
        "cost": "Passive",
        "effect": "+50% Awareness"
      },
      {
        "stars": 5,
        "name": "Pyromania",
        "cost": "Passive",
        "effect": "+25% Flamethrower Damage, +10 Flamethrower Accuracy"
      },
      {
        "stars": 7,
        "name": "Explosives Expert",
        "cost": "5",
        "effect": "Random bomb parts (Temporarily Unavailable)"
      },
      {
        "stars": 10,
        "name": "Inferno",
        "cost": "25",
        "effect": "Random incendiary ammunition, supplying currently equipped weapons if applicable"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Fitness Center",
    "styles": [
      "Training",
      "War",
      "Education"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Healthy Mind",
        "cost": "1",
        "effect": "30 minute education time reduction"
      },
      {
        "stars": 3,
        "name": "Goal Oriented",
        "cost": "Passive",
        "effect": "50% reduction of happiness loss in gym"
      },
      {
        "stars": 5,
        "name": "Roid Rage",
        "cost": "1",
        "effect": "Strength"
      },
      {
        "stars": 7,
        "name": "Athlete",
        "cost": "Passive",
        "effect": "3% life regeneration per tick"
      },
      {
        "stars": 10,
        "name": "Training Regime",
        "cost": "Passive",
        "effect": "3% gym gains"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Flower Shop",
    "styles": [
      "Trade",
      "Travel",
      "Beginner",
      "Training"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Rare Import",
        "cost": "3",
        "effect": "Special flower"
      },
      {
        "stars": 3,
        "name": "Cultivation",
        "cost": "Passive",
        "effect": "25% illegal production success & gain (Temporarily Unavailable)"
      },
      {
        "stars": 5,
        "name": "Herbal Cleansing",
        "cost": "1",
        "effect": "Drug addiction reduction"
      },
      {
        "stars": 7,
        "name": "Over Capacity",
        "cost": "Passive",
        "effect": "Buy 5 additional special flowers abroad"
      },
      {
        "stars": 10,
        "name": "Floral Contacts",
        "cost": "1",
        "effect": "View stock analysis of flowers in all countries"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Furniture Store",
    "styles": [
      "Training",
      "Revive",
      "Crime",
      "War"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Coffee Break",
        "cost": "1",
        "effect": "3 energy"
      },
      {
        "stars": 3,
        "name": "Heavy Lifting",
        "cost": "1",
        "effect": "Strength"
      },
      {
        "stars": 5,
        "name": "Removal",
        "cost": "Passive",
        "effect": "15% theft crime exp & skill gain"
      },
      {
        "stars": 7,
        "name": "Beefcake",
        "cost": "Passive",
        "effect": "25% passive strength"
      },
      {
        "stars": 10,
        "name": "Brute Force",
        "cost": "Passive",
        "effect": "100% fist & kick damage"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Game Shop",
    "styles": [
      "Training",
      "Beginner",
      "Crime",
      "Revive",
      "Money"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Ub3rg33k",
        "cost": "Passive",
        "effect": "50% virus coding time reduction"
      },
      {
        "stars": 3,
        "name": "Early Release",
        "cost": "100",
        "effect": "Money"
      },
      {
        "stars": 5,
        "name": "Gamer",
        "cost": "Passive",
        "effect": "100% console happiness"
      },
      {
        "stars": 7,
        "name": "Power Levelling",
        "cost": "10",
        "effect": "View progress to your next level"
      },
      {
        "stars": 10,
        "name": "Overpowered",
        "cost": "1",
        "effect": "1 nerve, 5 energy, 50 happiness"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Gas Station",
    "styles": [
      "War"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Molotov Cocktail",
        "cost": "3",
        "effect": "+1 Molotov Cocktail"
      },
      {
        "stars": 3,
        "name": "Fueled",
        "cost": "Passive",
        "effect": "+25% bonus to Speed"
      },
      {
        "stars": 5,
        "name": "Cauterize",
        "cost": "Passive",
        "effect": "Occasional 20% health regeneration (10% chance per turn)"
      },
      {
        "stars": 7,
        "name": "Fireproof",
        "cost": "Passive",
        "effect": "50% reduction to Burning damage received"
      },
      {
        "stars": 10,
        "name": "Blaze of Glory",
        "cost": "Passive",
        "effect": "50% bonus to Burning damage dealt"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Gents Strip Club",
    "styles": [
      "War",
      "Training"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Happy Ending",
        "cost": "1",
        "effect": "+50 Happy"
      },
      {
        "stars": 3,
        "name": "Dancer's Flair",
        "cost": "Passive",
        "effect": "+25% Passive Dexterity"
      },
      {
        "stars": 5,
        "name": "Supple",
        "cost": "Passive",
        "effect": "+50% Tyrosine effect & duration"
      },
      {
        "stars": 7,
        "name": "Pilates",
        "cost": "Passive",
        "effect": "+10% Dexterity gym gains"
      },
      {
        "stars": 10,
        "name": "No Touching",
        "cost": "Passive",
        "effect": "1/4 chance to dodge melee attacks"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Grocery Store",
    "styles": [
      "Training",
      "Trade",
      "Crime",
      "Revive",
      "Beginner"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Bagged Down",
        "cost": "2",
        "effect": "Bag of candy"
      },
      {
        "stars": 3,
        "name": "Fast Metabolism",
        "cost": "Passive",
        "effect": "10% consumable cooldown"
      },
      {
        "stars": 5,
        "name": "Bottled Up",
        "cost": "5",
        "effect": "Bottle of alcohol"
      },
      {
        "stars": 7,
        "name": "Absorption",
        "cost": "Passive",
        "effect": "10% consumable boost"
      },
      {
        "stars": 10,
        "name": "Canned in",
        "cost": "12",
        "effect": "Can of (premium) Energy Drink"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Gun Shop",
    "styles": [
      "War"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Sales Discount",
        "cost": "Passive",
        "effect": "20% discount on standard ammo"
      },
      {
        "stars": 3,
        "name": "Surplus",
        "cost": "15",
        "effect": "Random special ammunition, supplying currently equipped weapons if applicable"
      },
      {
        "stars": 5,
        "name": "Skilled Analysis",
        "cost": "Passive",
        "effect": "Target equipment and ammo is always visible"
      },
      {
        "stars": 7,
        "name": "Bandoleer",
        "cost": "Passive",
        "effect": "1 extra clip for guns during attacks"
      },
      {
        "stars": 10,
        "name": "Firearms Expert",
        "cost": "Passive",
        "effect": "10% primary & secondary weapon damage"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Hair Salon",
    "styles": [
      "Education",
      "Mug",
      "War",
      "Beginner"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Debate",
        "cost": "1",
        "effect": "Experience"
      },
      {
        "stars": 3,
        "name": "Gossip",
        "cost": "10",
        "effect": "View someone's money on hand"
      },
      {
        "stars": 5,
        "name": "Rumors",
        "cost": "Passive",
        "effect": "Reduced enemy stealth"
      },
      {
        "stars": 7,
        "name": "Cutting corners",
        "cost": "1",
        "effect": "30 minute education time reduction"
      },
      {
        "stars": 10,
        "name": "Sweeney's Revenge",
        "cost": "Passive",
        "effect": "20% slashing weapon damage"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Ladies Strip Club",
    "styles": [
      "War",
      "Training"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Hot Flush",
        "cost": "1",
        "effect": "+50 Happy"
      },
      {
        "stars": 3,
        "name": "Hench",
        "cost": "Passive",
        "effect": "+25% Passive Defense"
      },
      {
        "stars": 5,
        "name": "Hormonal",
        "cost": "Passive",
        "effect": "+50% Serotonin effect & duration"
      },
      {
        "stars": 7,
        "name": "Boxercise",
        "cost": "Passive",
        "effect": "+10% Defense gym gains"
      },
      {
        "stars": 10,
        "name": "Hardbody",
        "cost": "Passive",
        "effect": "30% melee damage mitigation"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Law Firm",
    "styles": [
      "Crime",
      "War",
      "Mug"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Bail Bondsman",
        "cost": "Passive",
        "effect": "50% decreased bail costs"
      },
      {
        "stars": 3,
        "name": "Background Check",
        "cost": "10",
        "effect": "View someone's stats"
      },
      {
        "stars": 5,
        "name": "Closing Argument",
        "cost": "Passive",
        "effect": "Easier to bust more people at once"
      },
      {
        "stars": 7,
        "name": "Loophole",
        "cost": "Passive",
        "effect": "20% organised crime skill"
      },
      {
        "stars": 10,
        "name": "Educated Decisions",
        "cost": "Passive",
        "effect": "View success chance of potential busts"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Lingerie Store",
    "styles": [
      "Trade",
      "Travel",
      "War",
      "Money"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Nine to Five",
        "cost": "10",
        "effect": "100 endurance"
      },
      {
        "stars": 3,
        "name": "Concealment",
        "cost": "Passive",
        "effect": "2 extra travel items"
      },
      {
        "stars": 5,
        "name": "Born Free",
        "cost": "Passive",
        "effect": "+50% speed and dexterity when not wearing armor"
      },
      {
        "stars": 7,
        "name": "Simp",
        "cost": "Passive",
        "effect": "Waive all property upkeep and staff costs"
      },
      {
        "stars": 10,
        "name": "Sex Appeal",
        "cost": "Passive",
        "effect": "Provides Free Business Class Travel"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Logistics Management",
    "styles": [
      "Trade",
      "Business",
      "Travel",
      "War"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Efficiency",
        "cost": "1",
        "effect": "Speed"
      },
      {
        "stars": 3,
        "name": "Organized",
        "cost": "Passive",
        "effect": "Increases available open mission contracts from 3 to 5"
      },
      {
        "stars": 5,
        "name": "Repatriated",
        "cost": "Passive",
        "effect": "Allows traveling back to Torn from abroad while in hosp"
      },
      {
        "stars": 7,
        "name": "Contraband",
        "cost": "50",
        "effect": "Large quantity of a foreign item"
      },
      {
        "stars": 10,
        "name": "Logistics Report",
        "cost": "250",
        "effect": "Targeted company productivity boost"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Meat Warehouse",
    "styles": [
      "Crime",
      "War",
      "Travel",
      "Money"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Blood Thirst",
        "cost": "1",
        "effect": "+2 nerve"
      },
      {
        "stars": 3,
        "name": "Blood Splatter",
        "cost": "Passive",
        "effect": "50% reduction in crime penalty"
      },
      {
        "stars": 5,
        "name": "Carnage",
        "cost": "Passive",
        "effect": "10 maximum nerve"
      },
      {
        "stars": 7,
        "name": "Huntsman",
        "cost": "Passive",
        "effect": "25% hunting skill gain"
      },
      {
        "stars": 10,
        "name": "Vampiric",
        "cost": "Passive",
        "effect": "3% life regeneration per tick"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Mechanic Shop",
    "styles": [
      "Racing",
      "Trade"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Machinist",
        "cost": "5",
        "effect": "Racing point"
      },
      {
        "stars": 3,
        "name": "Discount Parts",
        "cost": "Passive",
        "effect": "75% cost discount on car parts"
      },
      {
        "stars": 5,
        "name": "Junkyard Dog",
        "cost": "10",
        "effect": "Random car"
      },
      {
        "stars": 7,
        "name": "Refurbish",
        "cost": "Passive",
        "effect": "Lose no car parts after crashing"
      },
      {
        "stars": 10,
        "name": "Driver",
        "cost": "Passive",
        "effect": "50% driving skill gain"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Mining Corporation",
    "styles": [
      "Crime",
      "War",
      "Training",
      "Money",
      "Business"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Mining Boom",
        "cost": "20",
        "effect": "Random excavation equipment"
      },
      {
        "stars": 3,
        "name": "Thirsty Work",
        "cost": "Passive",
        "effect": "30% alcohol cooldown reduction"
      },
      {
        "stars": 5,
        "name": "Rock Salt",
        "cost": "1",
        "effect": "Defense"
      },
      {
        "stars": 7,
        "name": "Essential Salts",
        "cost": "Passive",
        "effect": "10% maximum life"
      },
      {
        "stars": 10,
        "name": "Preserved Meat",
        "cost": "25",
        "effect": "Boost current life to 150% of maximum"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Music Store",
    "styles": [
      "Training",
      "War",
      "Mug"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Ambience",
        "cost": "1",
        "effect": "50 happiness"
      },
      {
        "stars": 3,
        "name": "Well Tuned",
        "cost": "Passive",
        "effect": "30% increased gym experience"
      },
      {
        "stars": 5,
        "name": "High-fidelity",
        "cost": "Passive",
        "effect": "Reduced enemy stealth"
      },
      {
        "stars": 7,
        "name": "Deafened",
        "cost": "10",
        "effect": "Maximum stealth"
      },
      {
        "stars": 10,
        "name": "The Score",
        "cost": "Passive",
        "effect": "+15% passive on all stats"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Nightclub",
    "styles": [
      "Crime",
      "Training",
      "Education"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Criminal Connections",
        "cost": "1",
        "effect": "Experience"
      },
      {
        "stars": 3,
        "name": "Target Market",
        "cost": "Passive",
        "effect": "+15% illicit service exp and skill gain"
      },
      {
        "stars": 5,
        "name": "Suppression",
        "cost": "1",
        "effect": "Drug addiction reduction"
      },
      {
        "stars": 7,
        "name": "Tolerance",
        "cost": "Passive",
        "effect": "50% drug overdose chance reduction"
      },
      {
        "stars": 10,
        "name": "Restraint",
        "cost": "Passive",
        "effect": "Education is unaffected by drug addiction"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Oil Rig",
    "styles": [
      "Money",
      "Business",
      "War"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Danger Money",
        "cost": "1",
        "effect": "Money"
      },
      {
        "stars": 3,
        "name": "Embargo",
        "cost": "50",
        "effect": "Halve a target's happiness"
      },
      {
        "stars": 5,
        "name": "Oil Mogul",
        "cost": "3",
        "effect": "Reduce bank investment time by 1 hour"
      },
      {
        "stars": 7,
        "name": "Tax Haven",
        "cost": "Passive",
        "effect": "10% increase of Cayman Islands interest rate"
      },
      {
        "stars": 10,
        "name": "Fat Cat",
        "cost": "Passive",
        "effect": "50% investment banking limit"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Private Security Firm",
    "styles": [
      "War",
      "Mug"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Off the Grid",
        "cost": "20",
        "effect": "72 hour bounty protection"
      },
      {
        "stars": 3,
        "name": "Tactical Breach",
        "cost": "Passive",
        "effect": "+50% flash grenade intensity"
      },
      {
        "stars": 5,
        "name": "Open Arsenal",
        "cost": "75",
        "effect": "Primary or Secondary weapon"
      },
      {
        "stars": 7,
        "name": "Regulation",
        "cost": "Passive",
        "effect": "25% full set armor mitigation bonus"
      },
      {
        "stars": 10,
        "name": "Mercenary",
        "cost": "1",
        "effect": "3 mission credits"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Property Broker",
    "styles": [
      "Money",
      "Business",
      "Trade",
      "Training"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Commission",
        "cost": "1",
        "effect": "Money"
      },
      {
        "stars": 3,
        "name": "Job Satisfaction",
        "cost": "1",
        "effect": "50 happiness"
      },
      {
        "stars": 5,
        "name": "Vendor",
        "cost": "Passive",
        "effect": "Waive anonymous item market listing fee"
      },
      {
        "stars": 7,
        "name": "Insider Trading",
        "cost": "150",
        "effect": "Random property (Up to Castle)"
      },
      {
        "stars": 10,
        "name": "Interior Connections",
        "cost": "Passive",
        "effect": "10% property upgrade cost reduction"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Pub",
    "styles": [
      "Crime",
      "Training",
      "War",
      "Revive"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Pub Lunch",
        "cost": "1",
        "effect": "3 energy"
      },
      {
        "stars": 3,
        "name": "Drunken Master",
        "cost": "Passive",
        "effect": "10% melee weapon damage"
      },
      {
        "stars": 5,
        "name": "Liquid Courage",
        "cost": "25",
        "effect": "Refill nerve bar"
      },
      {
        "stars": 7,
        "name": "Lightweight",
        "cost": "Passive",
        "effect": "50% bottle of alcohol boost"
      },
      {
        "stars": 10,
        "name": "Buzzed",
        "cost": "Passive",
        "effect": "+15 maximum nerve"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Restaurant",
    "styles": [
      "Training",
      "War",
      "Crime",
      "Revive"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Free Meals",
        "cost": "1",
        "effect": "3 energy"
      },
      {
        "stars": 3,
        "name": "Butcher",
        "cost": "Passive",
        "effect": "10% melee weapon damage"
      },
      {
        "stars": 5,
        "name": "Flambayed",
        "cost": "50",
        "effect": "Flamethrower"
      },
      {
        "stars": 7,
        "name": "Healthy Diet",
        "cost": "Passive",
        "effect": "2% life regeneration per tick"
      },
      {
        "stars": 10,
        "name": "Professional Metabolism",
        "cost": "Passive",
        "effect": "25% consumable cooldown reduction"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Software Corporation",
    "styles": [
      "Crime",
      "Business",
      "Money"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Ub3rg33k",
        "cost": "Passive",
        "effect": "50% virus coding time reduction"
      },
      {
        "stars": 3,
        "name": "Proxy Hacking",
        "cost": "25",
        "effect": "Cancel a target's virus programming"
      },
      {
        "stars": 5,
        "name": "Intricate Hack",
        "cost": "250",
        "effect": "Steals 1-3% of a company's funds"
      },
      {
        "stars": 7,
        "name": "Hack the Planet",
        "cost": "Passive",
        "effect": "15% cybercrime success & skill gain"
      },
      {
        "stars": 10,
        "name": "Corporate Espionage",
        "cost": "50",
        "effect": "View financial details of a company"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Sweet Shop",
    "styles": [
      "Training",
      "Beginner",
      "Trade"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Sweet Tooth",
        "cost": "1",
        "effect": "50 happiness"
      },
      {
        "stars": 3,
        "name": "Sugar Rush",
        "cost": "2",
        "effect": "Bag of candy"
      },
      {
        "stars": 5,
        "name": "Gluttony",
        "cost": "10",
        "effect": "1,000 happiness"
      },
      {
        "stars": 7,
        "name": "Energy Rush",
        "cost": "15",
        "effect": "Can of (premium) Energy Drink"
      },
      {
        "stars": 10,
        "name": "Voracious",
        "cost": "30",
        "effect": "4,500 happiness"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Television Network",
    "styles": [
      "Business",
      "Money",
      "War",
      "Mug",
      "Trade"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Propaganda",
        "cost": "5",
        "effect": "1 faction respect"
      },
      {
        "stars": 3,
        "name": "Scoop",
        "cost": "Passive",
        "effect": "50% newspaper advertising cost"
      },
      {
        "stars": 5,
        "name": "Inside Story",
        "cost": "15",
        "effect": "View someone's stats & money"
      },
      {
        "stars": 7,
        "name": "Bad Publicity",
        "cost": "Passive",
        "effect": "25% extortion success rate and skill gain (Temporarily Unavailable)"
      },
      {
        "stars": 10,
        "name": "Press Pass",
        "cost": "25",
        "effect": "Receive special privileges"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Theater",
    "styles": [
      "Travel",
      "War",
      "Mug",
      "Crime"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Stagecraft",
        "cost": "1",
        "effect": "Experience"
      },
      {
        "stars": 3,
        "name": "Dramatics",
        "cost": "10",
        "effect": "Maximum stealth"
      },
      {
        "stars": 5,
        "name": "Masked",
        "cost": "Passive",
        "effect": "Cannot be targeted by spies"
      },
      {
        "stars": 7,
        "name": "Twinlike",
        "cost": "Passive",
        "effect": "15% counterfeiting crime exp & skill gain"
      },
      {
        "stars": 10,
        "name": "Disguised",
        "cost": "Passive",
        "effect": "Hidden traveling status & destination"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Toy Shop",
    "styles": [
      "Trade",
      "Travel",
      "Training",
      "Beginner"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Memory Lane",
        "cost": "1",
        "effect": "50 happiness"
      },
      {
        "stars": 3,
        "name": "Jumble Sale",
        "cost": "3",
        "effect": "Special plushie"
      },
      {
        "stars": 5,
        "name": "Gamer",
        "cost": "Passive",
        "effect": "100% console happiness"
      },
      {
        "stars": 7,
        "name": "Over Capacity",
        "cost": "Passive",
        "effect": "Able to bring back +5 plushies from abroad"
      },
      {
        "stars": 10,
        "name": "Toy Importer",
        "cost": "1",
        "effect": "View stock analysis of plushies in all countries"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  },
  {
    "name": "Zoo",
    "styles": [
      "Crime",
      "War",
      "Travel",
      "Money",
      "Training"
    ],
    "specials": [
      {
        "stars": 1,
        "name": "Fulfillment",
        "cost": "1",
        "effect": "50 happiness"
      },
      {
        "stars": 3,
        "name": "Animal Instinct",
        "cost": "Passive",
        "effect": "25% hunting reward"
      },
      {
        "stars": 5,
        "name": "Special K",
        "cost": "5",
        "effect": "Ketamine drug"
      },
      {
        "stars": 7,
        "name": "Eye of the Tiger",
        "cost": "Passive",
        "effect": "70% Awareness"
      },
      {
        "stars": 10,
        "name": "Seasoned Poacher",
        "cost": "Passive",
        "effect": "+3.00 Accuracy"
      }
    ],
    "source": "https://wiki.torn.com/wiki/Company/Company_List"
  }
];
