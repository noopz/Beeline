# Changelog

## 3.3.0 - 2026-11-27
- The route window's header loses its line of hours, steps and level ("about 59 h left", "876 of 2679 steps done", "To level 60"): the hours were the plan's own estimate of a pace that isn't yours, the counts didn't fall as you handed quests in, and a built-in plan always goes to 60. Which build of the plan you're on is in the tooltip on its name.
- Sunken Temple trip: after you hand in The Essence of Eranikus at the Essence Font, the trip has a step to start its second part with the Oathstone of Ysera's Dragonflight (its use button above the card; it needs the Chained Essence of Eranikus too, both go to Itharius). Without the Oathstone in your bags that quest and In Eranikus' Own Words wait under Later on this trip ("needs the Oathstone of Ysera's Dragonflight in your bags") and the card moves on; they come back once you have it. On any trip, a pick-up whose earlier quests aren't handed in waits for them: the card no longer offered In Eranikus' Own Words with the quest before it never started.
- The card has a side rail down its left edge: your route, Where to? (a signpost), the side trips and the quest log check, a click each. Side trips carries a count of the trips left for you and Log check the quests in your log no route of yours uses; their tooltips break it down ("Side trips: 8 dungeons, 3 attunements, 1 class quest, 1 special reward", "Log check: 4 quests in your log no route of yours uses"). Options sit at its foot. The tab on the card's left edge folds the rail away and brings it back (it stays as you leave it); a collapsed card has neither. On a side trip, Back to plan heads the rail too.
- The card's top line names the route you are on: "Leveling · Azshara", "Home base · Westfall" for a zone you picked, or the side trip's name in its kind's colour.
- The house is gone from the card. Where to? on the rail opens the zones you could go to; Back to plan takes you off a side trip; "Back to level 60" stops finishing your quests at 60; a zone you picked that is done lists your plan's next zone first among its rows. The level-up line's button is the Where to? signpost. The hover bar keeps the flag, back, done, skip and collapse: the route list and options moved to the rail.
- The zones-ahead panel beside the card and its tab are gone: the route list (Route, on the rail) shows the zones ahead.
- Route list: a long step wraps to a second line instead of being cut off ("Hand in Dark Iron Legacy at Monument of Franclorn Forgewright (in Blackrock Depths)"), "..." only past the second line; the list still scrolls to its last step and opens on your current one. The quest log check's quest titles wrap to two lines too.
- On a dungeon trip or side trip the card walks only the pick-ups you can take now: your level allows them, and they are not red to you (5 or more levels above you, the quest log's own colour). The rest are Later on this trip: not walked, their follow-ups wait with them, and each comes back by itself when you reach its level, on this run of the trip or a later one. Nothing is cut from the trip. At 54 on Blackrock Depths: Kharan Mighthammer and The Fate of the Kingdom (level 59) come back at 55, Attunement to the Core (needs 55, level 60) and the Onyxia chain (Stormwind Rendezvous and 3 more) at 56. The side trips window lists them under the trip you are on, each by the level it comes back at.
- On a trip, a pick-up you can take now has a Later button beside its other buttons on the card: not this run. It comes back on your next level or your next start of that trip, its follow-ups wait with it, and the card moves on. It is not a skip: Undo brings it back, and the side trips window lists it under Later on this trip.
- Plans: every dungeon trip's pick-ups carry the level the game asks for them. Trips are planned at level 60, so a quest needing 55 had no level on it and was walked at 54. Dungeon trips regenerated for every plan.
- Trips fly only to flight paths you have. A level 55 who never took Mount Hyjal's Tainted Foothills flight path was told to fly there from Rut'theran Village, Moonglade and Everlook: "Mount Hyjal" was read as known because a flight path you have is in Stonetalon Mountains. The trip now flies to Everlook and rides on, and offers the Tainted Foothills flight path when you pass by.

## 3.2.3 - 2026-11-27
- Beeline has its own icon in the game's addon list (a bee in flight), on every Beeline addon: the plans, the walk maps and the detailed map line, not a question mark.
- Detailed map line: the run back to your corpse may drop off a cliff. A ghost can't die of a fall, so its line now takes the drops off ledges too high for the living (a zone's falls, read only on a corpse run): in Azshara, from the plateau at 71.2, 29.9 to the shore below it, the line is 183 yd instead of 1,500 round by the slope. The living's lines and memory are unchanged; a zone's mesh is 1-4% bigger, and up to 1 MB more is unpacked while you're a ghost (the Barrens). The rebuilt meshes also pass the audit on the current plans' walks in Dun Morogh, Searing Gorge, Stranglethorn Vale, Swamp of Sorrows, Desolace and Felwood, so those 6 zones have the detailed line now (43 of 49).

## 3.2.2 - 2026-11-27
- Detailed map line: Feralas is back on it (37 zones). Its mesh had lost a steep hill path the plans walk (at 53, 52: the line went round for 2,000 yd where the walk is 940 yd); corners on steep hillsides that only a diagonal step crosses now join, in every zone outside the cities. Lines that swim to Feathermoon over the deep sea floor are no longer counted as going through walls: you swim at the surface. Every zone's mesh rebuilt; all 37 pass the audit on the 3.2.1 plans' walks (Feralas 60/60, Un'Goro 60/60).

## 3.2.1 - 2026-11-27
- Plans: the Timbermaw quests in Azshara that need Timbermaw Hold at Neutral (Report to Rageroar, Master Feardred, Toil and Trouble, Encroaching Corruption and 15 more) are off every built-in plan: the main route, the "go there instead" zone routes and the side trips. A character passing through Azshara at no standing could not take them (3.2.0 already keeps them off the card; now the plans no longer count on their XP).
- Horde plans rebuilt with 3.2.1's planner (no capital hops mid-zone, the walk to crossings priced like the addon's): about 0.9 hours less to 60 on average (91.6 h, from 92.5 h), every Horde plan 0.7 to 0.9 h less, simulated travel 34.8 h (35.0 h), no grinding. Alliance plans keep 3.1's route, reassembled the same way: the same hours to 60, simulated travel 30.6 h (30.8 h).
- Dungeon trips and side trips regenerated for every plan, so 3.2.0's trip wording reaches the built-in plans.
- Planner: its own trips (tools/travel.js) now price the walk to the crossings, flight masters and piers of your zone like the addon does since 3.1.2 (the walk maps' detours round mountains, not a straight line; a crossing reached only through another is no way round that one's enemy town), so the built-in plans' travel times match the trips the card gives you.
- Plans no longer fly you out of a zone in the middle of its quests to a capital and back for something that could wait for the end of the zone: the planner priced every flight inside a zone's route at 2 minutes, so a hand-in in Orgrimmar or the Undercity (Alliance Relations in Desolace, Notarized Claim in the Eastern Plaguelands) looked nearly free. A capital trip now happens mid-zone only when what comes after needs it (a follow-up that starts back in the zone, the level for the next quests). Class training waits for the end of the zone too, when you leave it within a level: no more flying from Stranglethorn to Stormwind and back at 44 for two ranks.
- Horde plans no longer send you to Ironforge to buy a Gyrochronatom for Gyro... What? (Badlands): the planner took any vendor of the item, of either faction.
- New planner check tools/capital-hops.js (run by tools/test-plan-lint.js): no main path of a built-in plan hops to a capital mid-zone when nothing after needs it, and none steps into the other faction's capitals; a visit of 10 or more of the city's own quests (Orgrimmar's at 18) and a class trip are not hops. 3.1.2's plans had 181 such hops and enemy-capital steps, 3.2.1's have 5, all in the race starts at levels 11-14 (a dwarf hunter's Stormwind errand from Dun Morogh, the orc and troll shamans' training and the tauren shaman's and warrior's Thunder Bluff hand-ins from the Barrens).
- Detailed map line: Feralas is off it again (the map keeps the plan's path there, as before 3.2.0). With the new plans' walks its mesh drew 8 lines through walls, most at Feathermoon Stronghold; 36 zones have it.

## 3.2.0 - 2026-11-27
- The Timbermaw quests in Azshara (Gatekeeper Rageroar, Korsa, Elder Bramblesnap, Furze, Gorn One Eye, Lorekeeper Nok, Unele and the Legashi Cauldron: Report to Rageroar, Master Feardred, Toil and Trouble and 16 more) need Timbermaw Hold at Neutral, which a player passing through Azshara doesn't have (Korsa is red). They stay off your route until you have it. Other quests that need a faction at Neutral are now checked too (that requirement was dropped from the quest data before).
- Quest givers with several quests no longer leave some off your route as "not offered": a quest you just took (its giver's window reopens before your log is read again - Commander Truesong's Preserving Eldarath in Azshara), and the quests that follow one you are handing in (the window you open to hand it in lists none of them yet - Truesong's four after Slay the Spitelash, Ekkal's The Legashi Threat). A quest in your log or done is never left off for something the data says it needs.
- Auto-fly takes flights of more than one hop: it asks the game for the route first, as the flight map does when you point at a town, instead of the game answering "no path" (Rut'theran Village to Talrendis Point). When the game knows no route, the map stays open for you.
- New option, Options > Map > "Detailed map line" (off by default): the map line runs from where you stand along the ground, round walls and cliffs - out of Nethergarde Keep by its west gate, north up the pass towards the Swamp of Sorrows, in at Brohann Caskbelly's door in Stormwind - in the 37 zones and cities whose navigation mesh passes the line check (Dun Morogh, Desolace, Felwood, Stranglethorn, the Swamp of Sorrows, Badlands, Searing Gorge, Thousand Needles, Moonglade, Deadwind Pass, Orgrimmar and Darnassus don't yet: there the map keeps the plan's path, or the city's line). It uses more memory: about 8-10 MB for your continent's maps while it is on, plus 1-8 MB for the zone you are in (and the one you walk to), let go when you leave it. With it off nothing of it is loaded and the map line is as before. The meshes come as two load-on-demand addons, Beeline_MeshEK and Beeline_MeshKalimdor, loaded only with the option on and never in a fight.
- Detailed map line: no more lines through town walls. From outside Gadgetzan's north-east wall to its flight master the line went in at the wall's corner and out through the south-west wall; it now goes round. The walk map it is baked from slipped through the seams between wall pieces and into the hollow inside Gadgetzan's walls; each step next to a wall is now checked against the walls themselves at a quarter of a yard, with room for a body (a gap under half a yard is shut; doors and gates stay open). The same leaks are gone at Theramore, Nethergarde Keep (its lines now use the real west gate), Menethil Harbor, Light's Hope Chapel, Tiragarde Keep and Northwatch Hold. Feralas passes the line check now (37 zones). New check tools/wall-sweep.js: the lines into and across every town against the collision geometry.
- Dungeon trip wording: a quest named after the one you hand it to reads "Find Marshal Windsor (in Blackrock Depths) and hand in the quest", not "Hand in Marshal Windsor to Marshal Windsor"; Bodley's hand-ins say "in Blackrock Mountain" (he stands in the cavern between the instances), not "in Blackrock Depths" or "in Dire Maul".
- Farming a quest objective, the card stays on it: it holds from your last kill or loot for it, not the first, and through a dry spell while you stay where it counts. Collecting Eldarath Relics off the naga in Azshara, the card went to the Making Contact hand-in 300 yd away mid-farm, without a word; when it does let go (no count for a while and you walked off), /bee why says so.
- "The giver has nothing for you" is one click per giver: all of that giver's quests you could take now leave your route until your next level, not one quest at a time with the card walking you back to them. Undo brings them back.
- A quest giver who won't talk to you (unfriendly or hostile, as the game shows when you target them, mouse over them or see their nameplate) has their quests and hand-ins off your route at once, and back when they are friendlier. It needs no reputation data: a gate the quest data doesn't know no longer walks you from one giver who turns you away to the next.
- No side quest and no stop taken "while you're here" or ahead of the plan's step sends you to a giver who has just turned you away.
- A pick-up you skipped stays skipped on a zone you pick (its route has its own steps), and the map's "!" no longer brings back a quest its giver turned down at two levels.

## 3.1.2 - 2026-11-26
- Dungeon quests in your log no longer count as "off-route" on the card or in the quest log check: they are marked for their dungeon, trip or not.
- Dungeon trips carry every quest for their dungeon, not only the ones both picked up and handed in out in the world. The Sunken Temple trip now has Into the Depths and Secret of the Circle (handed in at the Altar and the Idol of Hakkar inside), with their lead-in from Feathermoon, The Sunken Temple, and The Stone Circle; The Essence of Eranikus ("Loot Essence of Eranikus: it starts The Essence of Eranikus" on the run's list, its hand-in at the Essence Font, then its follow-ups to Itharius and Umbranse); and The God Hakkar, which says it needs Zul'Farrak's The Prophecy of Mosh'aru first. Every other dungeon's trip gains its quests got inside (from someone in there or loot: Blackfathom Villainy, The Shattered Necklace, Kharan's Tale, The Gordok Ogre Suit...) and those handed in inside (In Search of Thaelrid, Dark Iron Legacy, Legends of Maraudon...), with the chains that need them (Lore for a Price in Uldaman, Jail Break! in Blackrock Depths) - a second run where the game makes you go out and come back. Dire Maul's wings were read as outside the dungeon, which hid everyone in them.
- A quest started by an item lying out in the world is on its trip as "loot it there": Henrig Lonebrow's Journal in Thousand Needles, for The Crone of the Kraul.
- New release check tools/check-dungeon-quests.js: every quest for a dungeon that a plan's character can take is on one of its trips, or listed with the reason in tools/dungeon-quest-exclusions.json. 3.1.1's trips missed 179 such quests.
- Trips no longer send you over a mountain to a zone crossing that looks near on the map: in Blasted Lands just north of Nethergarde Keep, the way to the Swamp of Sorrows is up the pass (58.5, 3.3), not to the crossing on the ridge (70.7, 12.2), which you can only reach up that same pass and back round through the Swamp (850 yards on foot for 394 on the map). The walk from where you stand to the crossings, flight masters and piers of your zone now counts the walk maps' detours round mountains and cliffs, not a straight line; and a crossing you can only reach through another one no longer counts as the way round that one's enemy town (an Alliance player was kept off the pass because it runs by Stonard).
- Planner: tools/offnet.js bakes, from the walk maps, per zone and per 1/32 of the map, how much longer than a straight line the walk to each key point of the zone is, and which crossings are reached only by another (TravelData NET.walkEx). The planner's own trips (tools/travel.js) still join the network in straight lines.

## 3.1.1 - 2026-11-26
- Dungeon trips group their stops by place: every pick-up, objective and hand-in of a trip - the lead-in chains, the dungeon's quests and their follow-ups - is planned as one route, doing everything you can in a zone while you are there, instead of one chain after another. The Sunken Temple trip (gnome warlock) no longer goes to Stormwind six times and to Feralas, Felwood and Un'Goro three times each: 15 zone visits instead of 22 and nearly two hours less travel (7 hours down to about 4 in all). Across all the dungeon trips, a third less travel, with every quest still on them. Trips are timed with the same travel model as your route (flight paths, boats, trams, mage and druid teleports).
- A dungeon quest that another quest of the same dungeon opens (The Only Cure is More Green Glow after Gnogaine in Gnomeregan, the Blackrock Spire and Scholomance chains) is picked up once that one is handed in, for a second run ("Run ... again"). The trip used to have you pick it up before the first run, which the game doesn't allow.
- The live map line from where you stand is off outside the cities again: in 3.1.0 it could cut through walls (Nethergarde Keep) and over mountains (Blasted Lands), because the outdoor walk maps are too coarse to hold walls and cliffs. Outdoors the map shows the plan's own path and the arrow follows the card's trip, as in 3.0.0; the outdoor line comes back zone by zone once it passes the new check below.
- Stormwind: the line to Brohann Caskbelly (In Search of The Temple, the Sunken Temple trip) goes in at his door instead of round onto the roof above him - about 100 yards from the Dwarven District's street, not 290. A room the walk map had no way into now joins the street at its door step, in every capital.
- The card no longer flips back and forth between a hand-in added to your route here (A Little Slime Goes a Long Way, Ironforge) and the plan's next step on another continent (The Sunken Temple, Feralas): it stays on the hand-in.
- The route window's "why" log names the zone of a trip to a stop added to your route ("to Ironforge"), not "to another continent".
- Planner: a walk that starts where you land after a flight starts at your side's flight master - an Alliance trip's "Search for the Temple of Atal'Hakkar" walked from Stonard. (Reaches the built-in plans at their next rebuild.)
- New tools/nav-audit.js checks every walk map's line against the plans' own walks and players' reports (too long, through walls and cliffs); install.sh refuses a build where a zone with the line on fails it.

## 3.1.0 - 2026-11-26
- A collect step says who drops the item, under it beside the quest: "Collect 1 Ryedol's Lucky Pick" now reads "A Dwarf and His Tools · from Shadowforge mobs". A Buy step names the vendor ("from Innkeeper Helbrek" for The Third Fleet's mead), and Linken's compass, key and map say they come in A Small Pack. The card no longer lists the mobs in the step's title.
- The map line from where you stand now runs in every zone, not only in Elwynn, the Wetlands and the cities: along the ground and the roads and round walls and camps, to your step (in Desolace the world map showed only the plan's short dotted stub near the step). Each continent's walk maps come as their own addon (Beeline_NavEK, Beeline_NavKalimdor), loaded the first time the line needs them and never in a fight (until then the planned path is drawn).
- One Beeline window instead of two: the route list, Home base, the side trips and the quest log check are now items in its sidebar - Route, Zones, Class quests, Dungeons, Attunements, Special items, Log check - with no buttons across its top. Side trips are split by kind, and an item with nothing left for your character is hidden. "Show done" is a small checkbox in the Route view. Every way in still works and opens the right view (the card's buttons, the key binding, /bee list, /bee home, /bee dungeons, /bee logcheck), and /bee class, /bee attune and /bee items open the new ones. The Home base window's Plan tab is gone: the Route view shows the same zones and your steps under them, and a companion's other plans are under Zones.
- Skip the flight into a zone and the card no longer keeps saying "Fly to" there: that zone's steps head the card themselves, with the trip as a line under them, so each skip visibly moves on to the next step.
- A quest whose every way in is gone - its earlier quest skipped, and the other one that would open it already behind you - is passed over instead of sitting on the card as a step that can never be done (Suspicious Hoofprints in Duskwood after skipping They Call Him Smiling Jim).
- The side trips list follows your route: leave a trip from the card and the open list no longer still says FOLLOWING with its own Back to plan. The Sunken Temple is listed by that name (Temple of Atal'Hakkar).
- Dungeon quests stay on their dungeon's side trip and off your route: Reclaimed Treasures (the chests are in Uldaman's common halls) is no longer offered as a stop in the Badlands, Mother's Milk (Blackrock Spire) is off the Alliance routes, and the shaman's Elemental Aid (Charlga Razorflank in Razorfen Kraul), with the class quests after it, is off the shaman routes. Razorfen Kraul is now a side trip, and it carries them. A check now stops any dungeon quest from shipping on a route again.
- Fixed an error at login or when joining the plan ("join: attempt to yield across metamethod/C-call boundary"), new in 3.0.0: it could start you at the wrong place on the route. Logging in stays smooth.
- Razorfen Kraul is a side trip again (it was missing from every plan), and three loot steps no longer read "from undefined" (Essene's Necklace, Spellbook and Waterskin).
- The shaman class trips stop before a quest done in a dungeon: the Horde weapon chain (The Tempest's Weapons) and the dwarf's Call of Air chain after its first quest now go with the Razorfen Kraul trip, which carries the dwarf's whole chain to The Tempest's Weapons (it used to stop at Elemental Aid). A class trip merged onto your route on the way can no longer send you for Charlga Razorflank's note.
- Restoring the Necklace (Talvash del Kissel, Ironforge) is no longer offered as a side quest: it is the end of the Uldaman necklace chain.
- The Horde Onyxia attunement collects Scryer's, Somnus's and Chronalis's skulls before going back to Emberstrife and hands them in together: two fewer flights to Dustwallow Marsh. On every side trip, hand-ins to one NPC now wait for each other (the Horde Succubus chain saves a flight too).
- Opening the quest log check is quicker: it reads your bags only when they changed (and then only the quest items in them), and redraws only the rows whose text changed. A player's game took 7-9 ms to open it.
- Logging in, or a stop added to your route, no longer causes one long stutter of about 20 ms while the card works out its next step: that work now runs in small pieces across frames.
- Already in the zone a quick errand trip comes back to, the card no longer sends you across it for that visit's hand-ins first when the plan's way is shorter: a step of that visit you had already done was still counted and made it look worth it (an orc warrior sent to Sen'jin Village's hand-ins before the Far Watch Post errand, 3 min lost).
- The card's out-of-order steps weigh the rest of the route more truly. Before a quick errand trip it no longer does a zone's steps first when the plan comes back there anyway for quests still too high for you (a troll shaman behind the plan sent to Cenarius' Legacy before the trip to Ashenvale, 8.5 min lost), or when the ride back to the flight master costs more than it saves (Alther's Mill before the Stormwind trip, 3 min). Finished hand-ins from earlier in the plan wait for the plan's own visit to their town instead of a ride across the zone and back (Tarren Mill in Hillsbrad). And a flight path the route adds where the plan's next trip lands is taken on the way in, not ridden past (Sentinel Hill, on the way to Westfall from Stormwind).
- The arrow now follows the trip the card shows. Heading for a zone whose flight path you don't have yet (Un'Goro Crater from Gadgetzan), the card said "Ride to Un'Goro Crater" while the arrow turned to the flight master you stood next to; it now points along the ride (and, past its first crossing, on to where the ride ends), and the map pin of the trip marks the same spot. A trip that starts with your hearthstone says so when the arrow hides. When the trip changes on the way (a flight path learned mid-ride, a shorter way), the arrow and the pin switch to its new first leg at once, not only on the next step or zone.
- A quest handed in just after the card showed its hand-in is no longer saved as "the card shows a done step" moment: the card is given a moment to move on first (What Niby Commands at Impsy).
- Plans and data: every built-in plan is rebuilt on QuestieDB 1.1.6, on the same main routes as 3.0.0. The new data corrects 252 quests (who starts 156 of them, who takes 152 hand-ins, which races can take 29, objectives for 14, XP for 5), 1157 NPCs and 271 objects. 3.0.0's plans could send you to do things that aren't leveling, and they're gone. Near 60 every plan sent you to a Cloth Quartermaster to donate 60 pieces of cloth at a time ("A Donation of Mageweave"), and to the Ahn'Qiraj War Effort recruiters. Every plan also sent you after Under the Shadow, whose runes only drop during a Scourge Invasion. The card no longer offers the War Effort recruiters as side quests either, and a release check now stops any of these (event quests, reputation turn-ins, cloth donations, repeatable turn-ins) from shipping again. Hours to 60 hold, now without that XP you could never really get: the plans' own estimate is 87.7 hours for Alliance, the same as 3.0.0, and 92.5 for Horde (92.2 before). Class quests now go where your route already passes the quest giver: the undead warrior picks up Speak with Dillinger in Brill at 11, not on a trip into the Undercity at 13. The Horde rogue's The Horn of Xelthos (its horn is inside Shadowfang Keep) is now on the Shadowfang Keep side trip, not on your route.

## 3.0.0 - 2026-11-25
- New main routes for both factions, checked on every race and class (all 56 built-in plans). Alliance plans travel about 3.5 hours less on the way to 60 (34.1 to 30.5 hours in the test player), shorter on every Alliance plan; Horde plans about 3.8 hours less (37.8 to 34.0), shorter on every Horde plan. The Horde route no longer crosses to the Blasted Lands at 45 and back.
- Class quests for every class and race: every plan was checked for its class quests, its training and anything of another race, class or faction. 568 problems found and fixed. Class quests on your way in the plan went from 378 to 637 across the plans (the warlock's Felhunter and the rogue's start-zone chains among them).
- Three quest data corrections for WoW Forever, checked on Wowhead Forever.
- When the card does something you wouldn't expect - a quest out of the plan's order, a stop in another direction - it says why in one short line under the step: what it saves, or what it sets up later.
- The card's step changes its mind far less. In a test over 2,783 awkward situations on every built-in plan (joining mid-plan, behind or ahead of the plan, back from a capital or a dungeon, a full log, skipped steps), against the card before this release on the same plans: picks that cost you more than 2 minutes fell from 68 to 25 (none over 10 minutes), the step flipping without you doing anything by over a third, the card sending you somewhere and straight back from 10 to 3, walking you past a stop you then come back for from 62 to 40, and moves to another zone from 70 to 23. It no longer walks you out of town past a quest giver the plan needs, unless the plan picks that quest up later on its own way.
- Quests from earlier in the plan are weighed by the real way to their work from where you are, and an escort or long chain must clearly pay before the card takes it.
- After a pick-up that completes at once, its hand-in is on your route straight away (the card could flicker to something else for a moment).
- The "x" on every card line does what its tooltip says. The side trip line ("Felhunter: next stop here - worth a detour") came straight back when its next stop was in your zone; it now stays hidden there. "Bags full" and the food reminder came back within seconds; they now stay hidden until they change. "Next bases" now comes back at your next level, as it says. Every button on the card is now tested against its tooltip.
- The minimap marker is half size by default, so the game's own marker and its above/below arrow show. If you never changed it, it moves to the new size once; a size you set is kept.
- The card judges what to do next with the plan's own numbers. Every built-in plan now carries how long each step takes, how far out of the way it is, and what each quest costs in all (its work and hand-in included). When the card weighs doing something out of order, it counts the real rest of the route from where you rejoin the plan, not a guess. In a test over 2,767 awkward situations (joining mid-plan, behind or ahead of the plan, back from a capital or a dungeon, a full log, skipped steps), picks that cost you more than 2 minutes fell from 106 to 49, and the time they lose from 410 to 166 minutes. The worst, 17 minutes to Booty Bay while a Hillsbrad hand-in waited, is gone.
- "Do these here first, the trip waits" only when it really is quicker. Carry Your Weight before the flight to Orgrimmar (every orc and troll plan) and Dangerous! before the flight to the Undercity no longer cost a trip back.
- A hand-in no longer comes before the plan's own work for the same quest giver, and a later visit with a hearthstone bind in it isn't done early when the plan hearths first.
- The card does less work as you play: picking the next step takes about 15-20% less time.
- No more stutter at login: the catch-up after you log in or reload runs in small pieces (about 45-105 ms at a time, from up to 470 ms), and the arrow no longer hitches when the step changes. The card no longer walks the whole plan from its first step to find where you are.
- The card no longer tells you to go train. When to train is your call; the plans' training stops are left out of the card, the arrow and the route.
- New side trips: Alcaz Prison, Blackmaw Hold, The Shaper's Terrace and The Drowned City (WoW Forever's own dungeons), and the attunements and keys - Onyxia's Lair, Molten Core, Blackwing Lair, the Seal of Ascension (Upper Blackrock Spire), the Shadowforge Key (Blackrock Depths), the Skeleton Key (Scholomance) and the Scepter of Celebras (Maraudon). Like the dungeons, they come up only when you pick them; their quests never show on your normal route.
- Side trips are grouped by what they get you: class quests, attunements, dungeon keys and special rewards (the Cozy Sleeping Bag), each under its own heading.
- Beeline keeps a small log of what your play really takes, in your own saved variables: each flight's seconds between two flight masters, each quest's time from pick-up to done to hand-in, the zones you enter and your level-ups. It stays on your computer and is used to check the plans' timings against real play.

## 2.7.1 - 2026-11-24
- The card in a dungeon is much smaller: one bar for each quest (a quest with several parts shows how many are done, "Legends of Maraudon 1/4"), at most five, the rest on the "Also:" line.
- The world map no longer draws a dotted walking path that starts nowhere near you. A quest taken out of the plan's order drew the plan's own path to it, from where the plan expected you to be.
- The card no longer sends you to the zone after next for a few pick-ups first. From Searing Gorge it sent a warlock to Nethergarde for two Blasted Lands quests, then to the Hinterlands (the plan's next zone), and the plan came back to the Blasted Lands for their work: about 10 minutes of flying for nothing. It now weighs each quest's work and hand-in, not only its pick-up.
- A side quest from another zone no longer says "in this zone".

## 2.7.0 - 2026-11-24
- Every built-in plan is rebuilt on QuestieDB 1.1.5, which corrects quest givers, hand-ins, objectives and prerequisites. Hours to 60 are about the same as before.
- Your class quests where you start are now in the plan: the class letter at level 1 (Hallowed Rune, Simple Letter, Etched Sigil...) and a priest's two quests at level 5 (In Favor of the Light and Garments of the Light, and the other races' versions). They are picked up and handed in on your way.
- Training goes to the nearest trainer in the zone. A dwarf priest in Kharanos was sent back to Coldridge Valley at 6, 8 and 10.
- Quests given just outside the zone you are going to are picked up on the way when the detour pays, also ones with work to do there (The Atal'ai Exile, Dreadmaul Rock, Martek the Exiled, A Watchful Eye).
- Quests that need crafted goods are no longer in the plans: That's Asking A Lot (Thorium Bars, Hi-Explosive Bombs), The Ectoplasmic Distiller and Collection of Goods.
- When the card sends you to a quest the plan had earlier, it says so: "Side quest first: ~12 min, +2.8k XP. Then: To Searing Gorge". It no longer calls a quest across the zone "nearby", and you can put it off with "not now".

## 2.6.0 - 2026-11-24
- Quest givers who walk around: the card says when the NPC you need walks a route ("walks a route, see the map"), the arrow points at the nearest point of that route instead of the spot they started from, and the world map draws their route. 69 quest NPCs do this, among them the Centaur Pariah in Desolace, the Gizelton caravan, Crier Goodman and Curator Thorius.
- Dungeon trips carry every quest for the dungeon: the whole chain of quests that leads up to each one, also chains that start at an object (Maraudon now has Rot and Regret, from the Strange Pylons onward), and a new last part, "4. Follow-ups", with the quests that carry on after the hand-ins (Passing the Blame). Uldaman, Razorfen Downs, Blackrock Depths, Zul'Farrak, Blackrock Spire, Scholomance and Stratholme gain quests too.
- Ironforge and Undercity: the map line no longer runs through the rock. Their maps also cover the mountain top and the ruins above them, and the line could climb onto it.
- Fixed an error ("Style.lua:38: attempt to index local 'step'") when the route changed under an open window.
- Skins: Beeline can now look like the game's own windows. Pick **Skin: Blizzard** on the General tab of Options (beside Look), on Beeline's page in the game's Settings > AddOns, or with /bee skin blizzard; /bee skin beeline goes back. Changing it asks to reload.
- The Blizzard skin draws the card and every Beeline window in the game's metal frame with its title strip, like the bags, with the red close button, the game's buttons, check boxes and fonts, and the stock ! and ? quest marks on the card. The guide arrow and the map pins keep Beeline's look.

## 2.5.0 - 2026-11-23
- Home base is one place with one button: the house at the right of the card's bottom line, always there. It opens the Home base window to pick a zone; on a dungeon route or side trip it takes you back to your plan, and at 60 with "Finish my quests" on it goes back to the level 60 card. Its tooltip says which. The "Zones" text button on a level-up row is the house too.
- Undo shows next to the house for 10 seconds after a skip, done, jump or "not doing". /bee undo still works any time.
- The card's hover bar is shorter: back, next, done, skip, the route list, "looks wrong", collapse and options. Undo and side trips moved off it.
- Side trips (dungeons, class quests, bonus items) are a tab of the Home base window, beside Zones and Plan, instead of a window of their own. /bee dungeons opens it there; the house, /bee home, the key and the route list open Home base on Zones.
- Faster: opening the Home base window and switching its tabs take about a third to half the time they did, and so do drawing the card and standing still at higher levels on the test characters.
- Turning off "Keep notes for bug reports" in Options now stays off. It shared its saved setting with the notes themselves and came back on when they were kept or cleared.
- At a quest giver with several quests, the route's other pick-ups there are seen (they were read too late, after auto-accept had taken one).
- A learned boat pier moves the card's plan and the arrow together; the arrow could point at the new pier while the route was priced from the old one.
- The arrow's place no longer moves when you change its size or Beeline's scale.
- The x on the card's offer row dismisses the row it shows.
- A /click BeelineItemButton macro no longer uses the last step's item on a step with none.
- Keybinds pressed while the game is still loading do nothing instead of erroring.
- "Show example" in Options no longer writes made-up notes into /bee report.
- Auto hand-in only hands in quests that are in your log.

## 2.4.1 - 2026-11-22
- Gray quests are never offered for pick-up: not on the card, not as "right here" extras, not by auto-accept - not even to open a chain. Quests 6 or more levels below you aren't offered as "right here" extras either (a level 46 at Nijel's Point was told to pick up Carved Centaur Totems, 40). Gray quests already in your log can still be finished and handed in. The gray line is the game's own (the quest log's colours).
- No more trips back for quests far below you. Ahead of the plan, the card could send you across the map for something the plan does at a lower level: a level 46 who had finished Riverglades was sent by boat and flight to Dustwallow Marsh for Stinky's Escape, a level 37 escort. When the plan's next step leaves your zone for quests well below you, the addon now looks for the best place to carry on from your level, as it does when you first join the plan.
- The arrow no longer pulls you hard back onto the planned path out in the open. Off to the side of it, it leans toward the path and on toward where you're going; in cities, where walls matter, it still follows the walking line closely.
- In a dungeon with many quests the card is compact: a quest with one thing to get is one bar, without its name on a line above, and at most eight bars (the rest on one line). Zul'Farrak's eight quests filled the screen.
- A trip's later legs are listed under the card, one per line: when you land, the next one moves up.
- Flights name the town you land at: "Fly to Aerie Peak", not "Fly to The Hinterlands". The zone and the flight master are in small text under it.
- Take route flights works at flight masters who talk first (quests, an inn): it picks "Show me where I can fly" for you. Hold Shift to choose yourself. It also no longer skipped the flight when the card's trip came from memory.
- The boat in Riverglades: the arrow goes to the boat at Powderfuse Port, not the wharfmaster.
- Near the end of the plan, quests you skipped past in the zone you're in come back on the card, instead of "Route done for now".
- Reports say "Beeline report" (they said "FR report").

## 2.4.0 - 2026-11-22
- Trips only cross between zones where you really can. The ways from one zone into the next are now found from the game's own map of which ground belongs to which zone, and walked both ways: the old ones came from a scan that wandered over neighbouring zones' land and counted dropping off a cliff as a way in. Gone with it: paths from Feralas into The Barrens, Mulgore and Dustwallow Marsh, from Dun Morogh into the Wetlands, from Thousand Needles up into Dustwallow Marsh, from Mulgore into Stonetalon and Desolace, and from Westfall or Alterac along the coast (a swim). The locked gate from Loch Modan into Searing Gorge is not a way in; the Badlands pass is.
- The Great Lift between The Barrens and Thousand Needles is part of trips, and Orgrimmar's west gate onto The Barrens.
- North Blasted Lands (Nethergarde Keep, the road from the Swamp of Sorrows) had no walking map, so trips there went over the mountains from Deadwind Pass. They now take the road.
- Every built-in plan is rebuilt on these trips. Alliance plans are about half an hour shorter to 60, with fewer zone changes; Horde plans take about as long as before.
- Options, Map: "Minimap marker" turns our pin on the minimap off, and "Minimap marker size" makes it smaller. It sat on top of the game's own minimap marker and hid its above/below arrow.
- Plans no longer include the War Effort hand-ins ("The Horde Needs Rugged Leather!" and the rest): they want trade goods from a profession, and an orc at 58 was sent to Goldshire for leather.

## 2.3.2 - 2026-11-22
- Fewer wasted steps where your race's start joins the rest of the plan. Every Alliance plan had you set your hearth at the Auberdine inn and then hearth to Auberdine while standing there. Alliance and Horde plans asked for an objective you had already done a second time (Therylune's Escape, The Warsong Reports, Kill Grundig Darkcloud). Alliance plans also asked for a hearth while the stone was still cooling down from the one before.
- A travel step into a zone where your side has no flight path now reads "Travel to", not "Fly to". Alliance has no flight path in Thousand Needles: the trip flies to Gadgetzan and rides in, and "Fly to Thousand Needles" read as a flight path that isn't there.
- Trips no longer ride from Thousand Needles into Dustwallow Marsh. There is no way across, but the card could send you up the cliffs north of the Shimmering Flats. From the Flats it now rides to Gadgetzan and flies to Theramore.
- Ends Meet no longer shows up after you've handed in the other Praise quest, which shuts it out.
- On a zone you picked, a quest whose earlier quest you never did, and can't do on that zone's route, is passed over instead of left waiting for the rest of the zone (Lieutenant Paval Reethe on the level 36 Dustwallow Marsh route).

## 2.3.1 - 2026-11-22
- Every built-in plan is rebuilt on the latest quest data (QuestieDB 1.1.4): 98 new quests and 638 corrected, many of them quest givers and turn-ins in new places.
- Shaman-only quests stay with shamans. Challenge of the Desert Wolf (the Odd Totem in Tanaris) was in every class's plan.
- Trips through Deadwind Pass. The road from Duskwood through Deadwind Pass into the Swamp of Sorrows was treated as too dangerous below level 51, because of the ogres off the road. Heading for Blasted Lands from Duskwood, the card sent you back to fly to Riverglades and ride back up through the Swamp. It now takes the straight ride, about half the time.
- Feralas: trips no longer count on paths into The Barrens, Mulgore or Dustwallow Marsh that don't exist. When you know both Feralas flight paths, the card names the one to fly to ("Fly to Feathermoon, Feralas"), not just "Fly to Feralas".
- Trips name the flight path, not the flight master. "Ride to Thyssiana" is now "Ride to Thalanaar, Feralas", the name the flight map uses, with "Thyssiana, flight master" in small text under it. Flights from a flight master read the same way: "Fly from Farholde Keep, Riverglades to Stormwind City".
- Zone routes no longer send you on two trips in a row with nothing to do in between. Picking Feralas said "Fly to Feralas" twice, and Hillsbrad Foothills at 38 sent you to Stranglethorn Vale, then Hillsbrad, then Arathi.
- Logging in is lighter. The addon now remembers your place in the plan and the trips it worked out, from one login to the next. A level 45 login that took about 0.3 s now stays under 0.03 s from the second login at the same level.
- No more hitch a few seconds after logging in while the addon maps out the flight paths and roads for the first time. That work is now spread over several frames (one 55 ms frame before).
- Plan times read about 2 hours longer than 2.3.0's: Alliance 87.5 hours to 60, Horde 91.5. Part of that is the travel being counted right: 2.3.0's times counted on the Feralas paths that don't exist. Horde plans change zone about 14 times less often.

## 2.3.0 - 2026-11-21
- Built-in plans skip the worst collection quests: the ones where you kill mob after mob for an item that rarely drops. Alliance plans leave out Pirate Hats Ahoy!, Up to Snuff, Fiery Blaze Enchantments, Skullsplitter Tusks and Centaur Bounty. Horde plans leave out Pirate Hats Ahoy!, Bloody Bone Necklaces and Fresh Meat. Time spent collecting rare drops is about a third less on both factions.
- Plans now use the quest data's real drop rates. Items that drop from nearly every kill used to be planned as a coin flip, so some collection quests were planned as longer than they are.
- Horde plans are about 2.5 hours quicker to 60 (90 hours instead of 92), Alliance about 2 hours (85.5 instead of 87.5), and Alliance plans change zone a little less often. Horde plans do return to zones you've left more often than in 2.2.0 (about 66 times instead of 50).
- The map line now finds its way around every capital city. Orgrimmar, Ironforge, Thunder Bluff, Darnassus and Undercity are new, and Stormwind is redone. In Ironforge it often found no way through the city and fell back to a straight line; it now follows the walkways, ramps and stairs.
- Standing near a quest giver whose quest your plan doesn't hold no longer costs a small hitch every few seconds. The addon checked that quest against every step left in your plan, up to level 60; it now looks only at the levels that matter (about 4 ms down to 0.5 ms or less in our tests).
- The Target button no longer says "You can't do that right now" when the mob isn't around. It only puts the star on something you actually targeted.

## 2.2.1 - 2026-11-20
- Fixed: right after picking a zone, Horde characters around level 20-30 could be sent far south of Camp Taurajo first, to pick up the Cozy Sleeping Bag note, a quest handed in on the other continent. A side-trip quest now joins your path only if its hand-in is on the way too.

## 2.2.0 - 2026-11-20
- Every built-in plan rebuilt on the latest quest data (QuestieDB 1.1.3): 60 new quests, among them the new level 53-55 quests around Blackmaw Hold and the Timbermaw, and 345 corrected, with Forever's own XP figures for 31 quests that had none.
- Horde plans are about 6.5 hours quicker to 60 (92 hours instead of 98), with 8 fewer zone changes.
- Alliance plans change zone 20 times less often (52 zone changes instead of 72), at the same time to 60.
- Dungeon routes are rebuilt on the new data too.
- The quest log check's "Bring back" button no longer shows a stray "Go" behind it.

## 2.1.0 - 2026-11-19
- Dungeons: a group's going? `/bee dungeons` (or the sword button on the card) now lists every dungeon with quests for your race and class, from the Deadmines to Stratholme, and Forever's Krol'dok Stronghold. Pick one and the card gets you every quest for it, including the earlier quests that unlock them, then takes you to the entrance, then hands everything in. Your plan waits; "Back to plan" returns to it.
- The dungeons for your level come first, each with how many of its quests you still have left. Dungeons whose quests you've all done drop off the list. Class quests and special rewards follow the dungeons.

## 2.0.0 - 2026-11-19
- ForeverRoute is now Beeline. Another addon is also called ForeverRoute, and the two were easy to mix up. Same addon, same plans, new name.
- The command is /bee (or /beeline). /fr still works for now, and so do /bl and /bline when no other addon uses them.
- After updating, restart the game once (a /reload isn't enough): the game only finds the new Beeline folder when it starts.
- Your settings, key bindings and the flight paths and boats the addon learned come over by themselves, the first time each character logs in.
- An empty ForeverRoute folder stays in your AddOns: it only holds your old settings for Beeline to read. Delete it once each of your characters has logged in.

## 1.7.1 - 2026-11-19
- Handing in a quest is quicker. Each hand-in used to look over your whole plan again from its first step: about 1,500 steps at level 38 and 2,000 at 51. It now looks only around your place in the plan. A hand-in at level 51 went from about 35 ms to 22 ms in our tests.
- No more small hitch every 5 minutes. The addon's own timing check read the memory of every addon you have loaded, about 76 ms with 30 addons. It now does that only when you log out.
- Opening a flight master's map no longer recalculates your route unless you learned a new flight path there. It cost about 50 ms each time.
- Priests: the racial spell quests are two stops, at the level each one opens. Feedback (and Elune's Grace, Shadowguard and the others) was picked up at 18 or 19 and had to wait for 20.

## 1.7.0 - 2026-11-18
- Class quests send you to the nearest NPC. Horde shamans hand in Call of Earth in their own starting zone instead of flying to Dun Morogh. Horde warlocks bind the Succubus and Incubus in Orgrimmar instead of Undercity. The dwarf shaman's Call of Air and the undead paladin's Trevan Rol are fixed the same way.
- A class quest's work is planned where its mobs are thickest. Essence of the Exile's charms are all at Drywhisker Gorge.
- The card is quieter. A step picked out of your plan's order no longer has a tag under it ("nearby · +700 XP", "while you're here · saves ~3 min"). The ? button still says why.
- Joining near the end of your plan with finished quests from earlier in it, the card sends you to hand them in instead of saying "Route complete". A level 59 in Azshara had four ready in the log.
- Skipping your faction's copy of a starting quest also drops its follow-ups. After Welcome to Shen'dar Village, the card no longer offered six follow-ups the game would never give you.
- On a zone you picked, when what's left waits on quests you skipped, the card says "done for now". It no longer shows a hand-in as "Not finished": a level 51 on the Tanaris route was shown Super Sticky's hand-in with the tar in Un'Goro passed over.
- Built-in plans rebuilt with these class-quest fixes. All 56 were played from 1 to 60 by simulated players: none broke, none had to grind.

## 1.6.12 - 2026-11-18
- Rebuilt built-in plans on the latest Forever quest data (QuestieDB 1.1.2). In about 5,800 test characters logging in at random levels and places, 908 got a better card and over 460 kinds of problem went away, most of them a card offering a quest you couldn't actually take.
- About 120 quests are back in the plans. Their item comes from an object the quest data had no place for, such as Robbie's Hat for Hats Off, in a clam shell by the river near its giver in Riverglades (2,150 XP). The objects' places now come from Wowhead.
- Quest chains whose first quest only sends you on are planned again. Rog'mar Supplies, The Rog'mar Situation, Brewer's Trade and Something's in the Water had been left out.
- The card never sends you to the other faction's flight master. In Booty Bay, an Alliance gnome was told to fly from Gringer, and a Horde troll landed at Gyll.
- When your next step is quests far away, the card's headline is the way there. At the Booty Bay flight master it read "Do these here" under a flight icon and never said where to fly.
- A flight's time saved says "N min less riding" once you have a mount, not "on foot".
- While the card has you finish your zone's quests before the plan's next trip, the way to them stays in the zone. A player in Stranglethorn was flown to Westfall to ride back through Duskwood. On landing in Westfall, the card dropped Stranglethorn for the plan's trip to Arathi.
- A quest whose item can only be gathered needs that gathering skill. Without Mining 75 you're no longer sent to Arathi for Favor for Krazek's Lesser Bloodstone Ore. If such a quest is already in your log, its work and hand-in stay off your route until it's finished.
- Caught in a zone far above your level, the card finds the short way out. A level 41 who flew into Morgan's Vigil in the Burning Steppes was routed out through Redridge, past the step that was right at the Riverglades border. A ride of up to 400 yards inside the dangerous zone now counts as a way out.
- The Stepping Stones chain works again for both factions. It starts with "...and that note you found", Horde in the Barrens and Alliance in Westfall.

## 1.6.11 - 2026-11-17
- The game's own 3D navigation marker now shows where to go: a marker in the world with the yards to it, at the screen's edge when it's behind you. On a quest you're doing, the addon focuses that quest, as clicking it in the quest tracker does, and the game draws its marker when it has one. Everything else gets a map pin where the arrow points: a pick-up, a flight master, a boat, a quest the game doesn't mark. The game's setting for the marker is hidden on Forever; the addon turns it on for you. A map pin of your own is left alone. Turn it off in Options, Map: "Game's navigation marker".
- Clearer card note when the card does quests here before the plan's next trip: "before the trip" instead of "you're here already".
- The addon does less work every time it updates your route. Each update used to re-check, step by step, which parts of the plan are behind you, millions of times over a long play. It now remembers the answers until something changes. Logging in or reloading is quicker, and weaker PCs get fewer hitches.
- No more trips across the world for a single hand-in from a zone you skipped. A level 46 who had left Azshara out, but still carried three quests picked up there, was sent 9,700 yards from Tanaris to Azshara for one hand-in while the plan went on in Searing Gorge. Quests you carry from a part of the plan you've passed no longer pull hand-ins there.

## 1.6.10 - 2026-11-17
- Logging in or reloading is lighter. The addon now works out your route twice at login instead of four or more times. On a level 51 paladin that cut the work from about 0.5 s to 0.2 s, and the biggest single hitch from 0.4 s to 0.06 s.
- With a full quest log, the card no longer sends you across the map to pick up a flight path on its own. A level 27 in Thousand Needles was sent to Thunder Bluff only for its flight path, while every quest there waited on room in the log. An added flight path now shows only when the step after it can be done.

## 1.6.9 - 2026-11-17
- Rebuilt built-in plans.
- Hints of a New Plague? now sends you to the Forsaken Courier in Arathi Highlands for the Sealed Folder. It used to send you to the yeti cave in Hillsbrad.
- No battleground quests in the plans at all (Marks of Honor quests, The Sovereign Imperative and the rest). 1.6.7 only had the card skip them.
- Zone routes in Where to? are named for where their quests are. "Westfall" at 40 did its quests in Stranglethorn and is now called Stranglethorn Vale. Shen'dralar routes are now Desolace, some Tanaris routes Un'Goro, some Felwood routes Winterspring. A zone you picked under its old name keeps working.
- Zone routes stay in their zone. They no longer fly out to pick up a flight path or set your hearthstone, and they drop trips out that aren't worth the travel.
- A short trip out that is worth it stays, and the card's "?" says why. For example, a Stranglethorn route flies to the Badlands for Pearl Diving: "Looks odd, but it's the quickest way: Pearl Diving's giver is in the Badlands, and the Blue Pearls are here in Stranglethorn." The card says "Fly to Badlands" with "Pick up Pearl Diving, then back" under it. Where to? shows "+ Badlands pick-up" on that row when there's room.

## 1.6.8 - 2026-11-17
- A home base you picked keeps the quests you carry for it after a /reload or login. They used to drop off the route, so green quests in your log for that zone got no stops (Stranglethorn: The Second Rebellion, Some Assembly Required).
- Logging in or reloading while on a flight, the card works out your step before it holds it for the flight. It used to grab the plan's next step and keep it the whole way (a trip to the Badlands on a Stranglethorn home base).
- Starting partway through your plan, the card no longer sends you to hand in a quest whose objective isn't done yet (Buy 10 Heavy Leather, Collect 4 Fresh Manure): the hand-in waits, and a follow-up the game won't offer until it's handed in says "Needs ... handed in first".
- A trip on the card now says what to do now: the leg you're on is the title ("Fly to Westfall", "Run to Thorgrum Borrelson", "Take the boat to Menethil Harbor"), with where the trip ends under it ("then on to Stranglethorn Vale"). It used to say "Travel to Stranglethorn Vale" over a numbered list of every leg. On a long trip the next leg shows dimmed; all of them are under the new "?" button.
- A flight path to pick up where you stand is its own short line on the card ("Get the flight path from Lanie Reed first"), not a clause at the end of the leg.
- A trip that leaves your zone says what it's for in one line ("For Pearl Diving and 6 more quests at your level").
- New "?" button on the card's header: click it to see why the card sends you there, for example "Looks odd, but it's the fastest way: doing it now saves a trip back later (~8 min)" or "Short hop worth it: 2 hand-ins in Stormwind for ~3k XP, back in about 4 min". It uses the minutes or XP the route worked out when it has them, and the trip's legs in full.

## 1.6.7 - 2026-11-16
- The card no longer sends you for battleground quests: Darkspear Islands Clash, Conflict at Darkspear Islands, Fight for Warsong Gulch, Concerted Efforts and the other quests whose Marks of Honor come only from PvP matches. The built-in plans still list them, and the card now passes over their pick-up, objective and hand-in. A level 38 on the gnome warlock plan was sent across Stormwind to the Brigadier General for one. If you already have one in your log, the quest log check says it's a battleground quest, and the card takes you to its hand-in once it's finished.
- The last leg of a trip now names who you're going to ("Walk to Angus Stern"), not the city you just flew into ("Ride to Stormwind" right after landing in Stormwind).
- A flight leg reads "Fly to Stormwind City" when the leg before it takes you to the flight master, and "Fly from Gretchen Mayberry to Stormwind City" otherwise. It used to read "Fly to Stormwind City (Gretchen Mayberry)", as if she stood in Stormwind.
- Level 60: the card celebrates ("Level 60 - you made it!") and your route is done, whatever quests the plan had left. It no longer works out the route for a 60. "Finish my quests" on the card routes the quests you still hold - their objectives and hand-ins, nothing new picked up - and clicking it again, or the house button, goes back. Zone and dungeon routes you pick at 60 still run. Finishing your plan below 60 offers your next home bases instead of a bare "Route complete".

## 1.6.6 - 2026-11-16
- "Change home base" is now a house button with the card's other controls (shown when you hover the card). As a text button on the card's bottom line it sat under those controls.

## 1.6.5 - 2026-11-16
- Trying the addon partway through levelling now starts you where you stand. A character levelling in the Barrens was sent through Orgrimmar, the zeppelin and the Undercity to Silverpine while the Barrens still had quests for them.
- The flight paths you already have are now guessed from the quests you've handed in near them, until you open a flight master's map (Forever's world map doesn't say which ones you know). The card used to send you to pick up a flight path you already had. Opening any flight master's map corrects the guesses.
- A flight path to pick up where you stand now reads "before you go, get the ... flight path from ... nearby" instead of sounding like an errand to another town.
- The card no longer tells you to hand in a quest whose objectives aren't done (Preventative Measures at 0/12 Rog'mar Trainees): it shows the objective first.
- After the card let go of a quest from earlier in your plan, it no longer stays on a step that's already done.
- Walking no longer plans the trip to the step on the card again every second: only once you've moved a little way (20-50 yards), the step changed or you learned a flight path. That took up to 3 ms out of one frame a second.
- The route window opens about twice as fast (at level 12, 77 ms down to 38), and with less memory churn: it works out each step once instead of three times, and the check for skipped chains no longer makes throwaway data for every step.
- Standing in a zone your plan comes to only after another whole zone, the card no longer starts that zone's quests early and then sends you off with them half done. In Duskwood at 24 with the plan going to the Wetlands first, it took up the Duskwood quests you could do, flew you to the Wetlands with them in your log and brought you back for the rest. It now goes to the Wetlands and does Duskwood after, in one go. A short errand first (a hand-in in Stormwind) still waits until you've done the quests where you are.
- Taking up a quest from earlier in your plan no longer brings back a training stop or a flight the plan had already passed, which made the card switch to the flight out while you stood still (Reading Room in Stormwind).
- Fixed an error when landing from a flight while the game had no position for you yet.
- The card no longer shows a step that is already done after it offered a quest from earlier in your plan whose follow-up comes later (Return to Verner, then A Baying of Gnolls).
- Picking a zone in Where to? no longer freezes the game for a moment at high levels.
- Accepting quests for you never takes an escort quest: an escort starts at once and fails if you're not ready, so the quest window stays open for you.
- Looting a corpse no longer makes the game hitch while you're on a kill or collect step and not Well Fed: the food check used to read the tooltip of every item in your bags after every loot. It now reads only food, and each food's tooltip only once.
- With the quest log check or the side trips window open, a kill or a loot redraws it once instead of two or three times.
- A kill, a loot or a quest log update asks the game about each quest in your log once instead of three times. With 20 quests in your log that is about 30 calls per kill instead of 65.
- On a book or collectible step, looting other items no longer rebuilds the route each time. It updates when the step's own item arrives.
- The card no longer shows a step that is already done after it offered a quest from earlier in your plan: that quest is shown as an extra while you do it, and your place in the plan stays where it was (a level 19 joining Darkshore saw For Love Eternal as done).
- A quest from earlier in your plan that the card offered stays on the card as a step to do while you walk to it (it could turn "done" on the way).
- The card no longer offers a quest from earlier in your plan that the game won't give you anyway, such as a breadcrumb to a quest you already have (Raven Hill with Worgen in the Woods done).
- Where to? offers each zone's route for your level. At 28 it offered Hillsbrad's route for level 22, whose quests you had done, and picking it left the card empty.
- A zone you pick whose own quests are all done still takes the quests you carry there: the card flies you there and has you hand them in, instead of showing nothing.
- Where to? opens faster again, and asks the game about fewer quests when it does.
- Where to? no longer offers a zone that has nothing for you: pick-ups it never hands in, or a gray quest waiting on an earlier one. A zone offered for hand-ins counts their XP instead of reading "0 XP".
- After you pick a zone, a side quest in your log only gets stops in that zone. Picking Thousand Needles no longer sent you to Stonetalon first for a Shredding Machines objective.
- With your quest log nearly full, a quest giver right beside you is no longer passed over for a flight out. The card used to plan more of the plan's pick-ups than your log had room for, and then gave up on the quest next to you.
- Picking a zone for the one quest you carry there no longer leaves the card empty. That quest is no longer skipped as "not worth the trip" when it's the last thing on the route.
- Skipping a quest, or saying you're not doing it, now also takes the rest of its chain off your route. The card used to keep showing the next part's pick-up, which the game never offers without the part you skipped (Samophlange in the Barrens).
- A quest 5 or more levels above you (red in your quest log) waits until you're within 4 levels of it, like a quest that needs a level. Behind the plan's levels, the card used to hand you red quests from further along the plan (Worth Its Weight in Gold, level 36, at 31). Deliveries, with nothing to fight, are still picked up when the plan has them.
- A training stop with nothing to learn yet waits for your level. With a full quest log the card no longer flies you through the plan's later zones to "train level 46 spells" at 35: it keeps the pick-up in front of you and asks you to make room.
- On a zone you picked, finished quests are handed in there only if their quest giver is in that zone. The rest wait for your way back to your plan. A short zone route used to end with hand-ins in Felwood, Winterspring and Un'Goro one after another.
- With a full quest log, the card keeps the pick-up in front of you even when a quest waiting for a level, a hand-in not in your log or a dungeon quest comes before it in the plan. It used to fly you on through later zones.
- Where to? no longer counts quests you can't take there: the next part of a chain whose start you skipped or refused (the row said "needs ... first", and picking the zone gave an empty card), a quest you said you're not doing, or a quest red to you, in your log or not. A red quest in your log no longer makes a zone read "continues ...".
- Where to? updates right away when you skip a step, say you're not doing a quest, bring one back or undo.
- A quest the game showed you on offer is no longer dropped because the quest data says it needs an earlier quest you skipped.
- A training stop that waits for your level says "Nothing to learn until level N" on the card, and its map pin says the level instead of "at level 0".
- With your quest log nearly full, the card no longer plans one pick-up more than you have room for when an optional hand-in comes first.
- When nothing on your plan can be done yet (its next steps wait for a level), the card says "Route done for now", the level they open at, and offers your next home bases. It used to sit on a training stop reading "Nothing to learn until level 60".
- Visiting your trainer before a training stop's level no longer ticks that stop: you learned nothing there, and it comes back when you reach the level.
- When you level up, a quest that opens at the new level right beside you goes on the card at once, before the card sends you out of town.
- With your quest log nearly full, the quest giver the card has you visit before leaving town is one you have room for. A giver with no room left made the card send you out past another one right beside you (Auberdine).
- A gray quest in your log is off your route unless its chain leads on to a quest yellow or harder for you: the card no longer sends you to its objectives or its hand-in, adds no stop for it on the way, and the quest log check says to drop it. One that leads on stays, and the quest log check says what it leads to. The route used to keep every gray quest in your log while the quest log check said to drop it.
- Where to? no longer offers a zone for a low chain you carry there. A chain counts only when it leads to a quest yellow or harder for you: a level 57 was offered The Barrens for a level 18 quest whose next part, not on the plan, counted as worth it.

## 1.6.4 - 2026-11-16
- Landing somewhere other than where your plan expected (the flight path you know): the quests right around you come first, instead of a long walk to the plan's next one and back.
- The card doesn't send you to another zone while your path still has quests where you are, unless that quest starts a chain for your zone (it sent a player from Riverglades to the Badlands with eight quests ready to hand in).
- Before the card sends you out of town, it has you pick up the quests the plan takes in that town, so you work on them on the same trip (Farholde Keep sent players out for the Foreman's Crate with the quest givers beside them).
- The arrow points at the game's own quest marker for an objective whose place the quest data doesn't have, instead of disappearing.
- Dead: the card no longer changes as your ghost runs past quest givers; it picks up again once you're alive.
- Your place in the plan only moves forward. A quest you take up again from a part you passed no longer pulls the card, its Base and the zones ahead back to an old zone; it is offered when you are near it.
- A side quest or a quest from earlier in the plan is never filed into the part of the plan you passed (one sent a player back to Wetlands).
- Time is priced at Forever's real pace for your level, not a fixed level an hour: what a trip is worth, whether a leftover is worth it, whether to hand in now.
- A finished quest's hand-in, side quests' too, is weighed by the XP it would lose by waiting; while you farm the card's own pick, it stays on the card.
- The quest log check uses the same "gray" as the route, and no longer says "on your route" for a quest the route skipped.
- Fixed: training, hearthing or a flight path could be ticked from the step you were looking at in the route list.
- A flag on the card: if something looks wrong, click it and send /bee report - your report then shows us exactly what happened.

## 1.6.3 - 2026-11-15
- The Drowned City: inside, the card shows its quests from your log (Shady Saltseers, The Saltseer Captain, Ancient Gurubashi Secrets) instead of your next step outside.
- Joining your plan partway into a zone no longer drops that zone's earlier quests: anything there at your level stays on your route (half of Riverglades - Gnoll Infestation, Bats in the Belfry - was left out, and the card jumped between them as you walked).
- In a town the card keeps its stop until you do it, instead of switching sides as you walk through; a hand-in jumps the queue only when you are at its NPC.
- Collapsing the card hides everything under it (reminders, Zones, Change home base and the next-zone line stayed).
- A quest behind you that the card picked up stays on the card while you walk on, and says what it pays ("+2.4k XP") instead of a time it doesn't save.

## 1.6.2 - 2026-11-15
- New options window: tabs down the side (General, Auto, Map, Size, News, Help) instead of one long list, short labels, a Reset tab link on each, and a search box that finds any option ("food", "arrow", "scale").
- Turn each card line on or off: step notes, the next-zone line, zone suggestions, quest items in your bags, and the reminders (bags full, Well Fed food, warlock grimoires). Or pick a look in one click: Full, Compact or Minimal.
- What's new lives in the options now: the newest version open, older ones one line each, new ones marked. Turn off the bar after updates if you like.
- Reset positions puts the card, arrow and Target button back; Help has the main commands and "Bring back skipped steps".

## 1.6.1 - 2026-11-15
- A quest you finish early no longer waits for your plan to pass its hand-in levels later, gray by then: when going now is worth more than what waiting would lose, it is your next stop.
- "Do it now" on a hand-in nearby: the card's Base count and the zones ahead stay on your plan while you hand it in (they showed the far part of the plan the hand-in was filed under), and the card goes back to your plan after.

## 1.6.0 - 2026-11-15
- Every built-in plan rebuilt on the latest quest data (QuestieDB 1.1.1: 21 new quests, 296 corrected). Each was played from 1 to 60 by the simulated player and by one hopping between zones before it shipped.
- Your home base: the zone you work from, and the card always says which ("Base: Stranglethorn"). On your plan it is the plan's zone; "Change home base" on the card opens Where to? to pick another. It brings along the quests you already carry there. Near its end the card tells you once how much XP is left and the next bases; when nothing is left but quests that open later ("2 quests here open at 40"), it lists your next home bases to click. "Back to plan" takes you back to your plan, wherever you are.
- Finishing an objective, taking or handing in a quest, levelling up or entering a zone costs much less again: the addon reads your quest log once per change instead of asking the game about every quest on your route, and remembers how far your plan is done.
- When the card puts a stop before your plan's next one, it says so in a few words and what it saves ("while you're here · saves ~3 min"); hover it for the whole reason and your plan's next step.
- Where to? says how far each zone is ("6 min away") and ranks zones by the XP an hour they give you counting the trip there, so a big zone two continents away no longer beats the one next door.
- No more trips across the world for the one quest you left of a zone: when you did the rest ahead of your plan or dropped them, a far, poorly paying leftover that nothing later needs is skipped (/bee undo brings it back).
- The card no longer flicks to your plan's step and then to a better stop a moment later: it waits for the better stop (a fraction of a second) and changes once.
- A chain start added to a zone you picked says what it costs and opens ("+4 min, opens ~12k XP"), and "skip chain start" on the card takes it off for good.
- The travel line is shorter: "Run to Stranglethorn Vale via Duskwood" instead of every border crossed, and "2 quests there: ..." under it.
- A quest new in Forever shows a small "Forever Quest" tag (hover it for what that means) instead of three lines of text.
- The "won't do" link stays on the card while you hover it.
- No more gear-repair reminder: other addons do that. The bags-full one stays.
- Clicking the step you are on in the card's list takes you back to it (as in the route window) instead of "just looking" at it.
- "N won't do" on the card is "N off-route" now, and the card's notes are shorter and plainer.
- A finished home base shows "Carry on" right away, and nothing on the card offers to save and replan on a flight any more.
- The quest log check only suggests dropping gray quests and ones you said you won't do. A quest another zone has is marked yours, with Go to make that zone your home base; anything else off your route is yours to keep. Abandoning asks first and says it also leaves your route.
- Dead: the map no longer draws your step's trail from somewhere else while you run back to your corpse.

## 1.5.2 - 2026-11-15
- No more hitch every few steps while you walk or ride: working out your next stop now runs in the background, a sliver of each frame, instead of all at once (the worst frame walking went from about 30 ms to under 2).
- Finishing an objective, taking or handing in a quest, levelling up or entering a new zone costs about half as much as before: one route update per change instead of up to three, and the next stop worked out in the background. The card shows your plan's step at once and moves only if a better stop turns up a moment later.
- The quest log check and the log bookkeeping no longer walk your whole route on every change.

## 1.5.1 - 2026-11-14
- No more frame drops when you kill a quest mob or loot a quest item: a count moving ("Gnoll Paws: 3/8") now only updates the card's counts instead of re-planning your whole route each time, and quests you haven't handed in are looked up once instead of on every update.
- The built-in plans download is less than half the size (about 15 MB per faction, was 38): the steps every plan of a faction shares are kept once and put back for your plan when it loads.

## 1.5.0 - 2026-11-14
- Pick a zone whose quests need an earlier part you haven't done, and those steps come first, cut from your own plan, when they're close by. When they aren't, the card says what was left out and what it needs.
- "Planned route" goes back to where your plan still has quests for you, however much you wandered, not to where you left it.
- A zone row's tooltip shows the chain behind it: how far you are, the XP left in it, where it goes on and when it turns gray. If it needs a chain start, it says how much more XP doing that first would open up there.
- Going elsewhere, the tooltip warns when a chain you carry is about to turn gray.
- Picking a zone no longer replaces your plan's zones with that one zone: the companion's replan kept treating the zone you picked as your whole path.
- "Where to?" is in the route window for everyone, not only with the companion, and offers many more zones: the built-in plans now carry a ready route for every zone worth going to at your level (Alliance 64, Horde 69, was 45 and 47).
- Each zone shows the XP it has for you and the level that gets you to ("~71k XP · to 36.4"), and the header how much you need for your next level.
- A quest picked up in a capital on the way is no longer shown as the zone you go to: Desolace, "pick up Reclaimers' Business in Ironforge first". A zone whose route is all in another zone is listed once (Shen'dralas and Desolace).
- A zone whose route also works a neighbour says so: "Hillsbrad + Alterac" (Alterac's quests are given in Southshore, so it never had a route of its own).
- "Not now" on a stop the card pulled forward (a trainer, a hand-in while you're here) holds: it came straight back when a stop was added before it.
- Inside a dungeon and after leaving one, quest titles from before no longer float over the card.
- Picking a zone: the zone you picked says YOUR PICK, "Planned route" points where your plan was going before you left it, and the Plan tab shows your plan ahead from there. A zone with no route yet does nothing when clicked.
- The card names its zone once ("OUT IN REDRIDGE"), and its "Next zone" line agrees with Where to?. A finished zone says what's next on your plan.
- A chain you carry that is about to turn gray is named at the bottom of Where to?.
- No more wording about a planner or "Path 1 of 3" for the built-in plans; no side-trip offer inside a dungeon.
- The card no longer jumps between two next steps as you walk: a quest added to your route (one you finished early) no longer throws off which step it is on, a quest you abandoned once a later part of its chain was handed in is no longer offered again, and nothing on another continent comes first.
- The arrow: beside a long straight path it points the way the path goes instead of back onto it first, and it follows the step the card shows after a stop is added.
- The route window no longer makes the game stutter on a flight or when you scroll it.
- Side trips read as side trips ("Side trip: Felhunter"), the card names its zone once, and its buttons and the "won't do" link no longer overlap.
- Built-in plans rebuilt with the data for all this; the plans download grew by about 0.3 MB.

## 1.4.10 - 2026-11-14
- "Where to?" has two tabs on a rail at its left. Zones lists the zones you could go to now, one row each: about how much XP is left there for you (and what share of your level that is), the quests you can still do there, and one reason - hand-ins waiting, a quest you carry there, or a quest it needs you to do first (and where). The XP counts what you could do there before you run out and have to move on: follow-ups once their first part is done, quests that open as you level, not ones you would outlevel first. Your plan's next zone is marked PLANNED NEXT.
- Plan shows the zones ahead on your plan with their quests. The companion's other full plans fold under it.
- On a zone you picked, a quest whose earlier part you haven't done waits instead of sending you to a giver with nothing for you, and "Planned route" picks up where you left your plan.
- When a zone you picked is done, the card offers "Carry on" to where your plan picks up.
- The window keeps its size and scrolls; hovering a row or tab says what it does.
- Plans name each part after the zone its quests are in (a stretch planned from Shen'dralas but all in Desolace now reads Desolace), and long chains whose items the quest data doesn't place are kept (Linken's chain in Un'Goro).

## 1.4.9 - 2026-11-14
- New built-in plans for every race and class. Each race starts on its own, then all of a faction's races share one main route from about level 21: no grinding anywhere from 1 to 60 (the old plans had 50 to 150 hours of it). Every plan was played from 1 to 60 by the simulated player first.
- Horde Skyborne (Windshaper) have built-in plans now: druid, hunter, rogue, shaman and warrior.
- Pick your zone: the route window lists the zones that fit your level with their XP per hour. Click one and the card takes you there, with the pick-ups on the way. No companion app needed.
- On a zone you picked, "Change zone" on the card opens the zone list, and its first button is your planned route, where it picks up at your level. When a zone is done, the card says so and opens the list.
- Plans keep the quests you carry instead of telling you to drop them, and long chains run to the end (The Missing Diplomat now reaches Jaina).
- A quest the giver didn't offer no longer flips on and off your route while the world map shows it somewhere else.
- Stormwind shows as one zone in the route list, not as both Stormwind and Stormwind City.

## 1.4.8 - 2026-11-13
- Quests started by an item (a page, a head, a strange object) are offered on the card when the item is in your bags: "use it" with the use-item button above the card, or the X if you won't do it.
- On a flight the card holds the step you took off with until you land; it no longer re-picks as you pass over other zones.
- A quest that needs a profession rank or reputation you don't have yet (Goblin Engineering needs Engineering 200) is left off your route, instead of walking you to a giver who has nothing for you. It comes back once you have it.
- Faster: the card refreshes about twice as fast, and working out a trip (walk, fly, boat, hearth) about ten times as fast. Picks and directions are the same.

## 1.4.7 - 2026-11-13
- Flying is time you can look away; walking isn't. A trip that flies and walks a little now wins over walking the whole way when it's about as quick: the card says "about as quick as walking, and N min less on foot".
- The card's footer says where the plan goes next: "Next zone: Duskwood, after 4 quests here" (it said "planned for level 33 · plan goes to level 43").
- The route list's header reads "To level 43 · about 38 h left · 26 of 893 steps done"; when the plan was made is in its tooltip.
- "Not doing this quest" and "the giver doesn't offer it" are small buttons (a red X, a struck-out !) with tooltips, beside Map, instead of two lines of text.
- Map opens the world map where the step is - for a trip, where it takes you - and its pin flashes once the map shows it.
- The "N won't do" link stays put while you hover the card (it moved away under the mouse).
- Quests with the same name and different givers are alternatives: once you've taken one, the others leave your route.
- The next step weighs going now against coming back later with the real trip, so a stop it fits in is one that's worth it.
- Plans from the companion app: far less grinding (a quest that pays better than grinding is never dropped as "too many kills" or "annoying"), quests up to 3 levels above you from level 20, chains that run through several zones are followed (The Tower of Althalaxx), quests whose work is in another zone are picked up and carried, and walking lines go round the other faction's towns.

## 1.4.6 - 2026-11-13
- Arrived somewhere the plan comes back to later (you hearthed to Stormwind, flew into a town): if all of that later visit can be done now, it's done now and the trip back is dropped - "the plan comes back here for this later".
- Already where your plan goes after its next trip (you flew on ahead, or rode there yourself): the card starts on the plan's quests where you are, and the trip waits.
- A pick-up is never offered before the quest that leads to it is handed in, whatever the plan says (For Further Study without Gleaning Our Future).
- Plans made with quests already finished in your log no longer fly you back and forth to their givers.
- A step that needs a flight, a boat or your hearthstone reads "Travel to Wetlands", with the step itself under it.
- The arrow: on the Deeprun Tram it says to ride it; riding to a flight master it aims at him once you're past the trip's first waypoint (Theramore); a ride aims at the border, not a flight master the road passes; a line that loops back past you can't pull it backwards; after you die it points to your corpse.
- Turtle Meat and similar: "A few in Hillsbrad Foothills too - the plan farms the bigger group in Alterac Mountains".
- Horde: the zone-choice prompt knows every capital, and warlocks get the grimoire errand in Orgrimmar and the Undercity.
- A dungeon or class route you didn't pick is never where a new plan puts you (a plan with no leveling path put a player on Gnomeregan).
- A flight-path step ticks only for its own flight point, not another in the same zone; automatic ticks no longer count as "ticked by hand".
- The other faction's towns are named (Southshore, Refuge Pointe - not "Darla Harris's town").
- "Save & replan" on a flight only shows when the companion app plans for you. The route list's zone chips show names only.
- Quest data: QuestieDB 1.1.0.

## 1.4.5 - 2026-11-13
- A zone change says why: "Going to Alterac Mountains for 2 quests (Soothing Turtle Bisque, Alterac Granite), then Hillsbrad Foothills" on the card, above how to get there.
- Zones ahead: a small panel beside the card (the tab on its edge) lists where the route goes next and how many quests in each. The route list's zone chips start from where you are, not from level 1.
- A Target button for each mob a step names (Snapjaw and Cranky Benj both drop Turtle Meat), stacked with the first; Ctrl+drag the top one to move them together.
- Clicking Map makes the step's pin blink on the world map, and our pins sit on top of the map's own markers.
- The arrival ring pulses three times and stops, instead of the whole time you're there.
- "Quests you won't do" is a small link in the card's footer, not a row of its own. The footer reads "planned for level 29 · plan goes to level 60".
- Fixed: the Target button clicked or dragged in combat raised a "blocked action" error.

## 1.4.4 - 2026-11-12
- A trip with an extra change (a boat, the tram, a portal) has to save real time to win: Refuge Pointe to Stormwind is the flight to Stormwind again, not a flight to Ironforge and the tram for 3 seconds less. The walk off the tram no longer reads "from Stormwind to Stormwind".
- "Not now" on the card for a stop the route fitted in from where you are (a hand-in while you're here, a quest just behind you): it goes back to the plan's next step, and offers the stop again once you've moved on.
- Every built-in plan rebuilt with each quest's expected time to do, so the next step weighs a quick quest nearby against a long one properly; each plan played from 1 to 60 by simulated players, none broke a check.

## 1.4.3 - 2026-11-12
- No more walking over the mountains from Dun Morogh into the Wetlands: the way there is through Loch Modan and Dun Algaz, and the arrow takes it.
- The Dalaran portal to Stormwind is one way: trips no longer count on a portal from the Mage Tower to Dalaran.
- Quest items in your bank (a rested-XP stash, or put there yourself): the card says to take them out, since the quest only counts what's in your bags.
- Setting your hearthstone at the plan's inn is recognised, so the route stops asking you to do it again.
- Hover a step in the list to see why it isn't the next one yet.

## 1.4.2 - 2026-11-12
- New option: take the flight your route needs when you talk to a flight master (Options, off by default; hold Shift to choose yourself).
- What to do next is now worked out from where you are: the plan's next steps in the order that makes the whole way shortest, and finished quests whose hand-in is close by ("while you're here"). Back in town to sell or to group up, the town's hand-ins come first; a hand-in across the world is left for when the route passes it. The card says why when it leaves the plan's order. (Options: "Choose the next step from where I am".)
- Bags nearly full (or gear wearing out): the vendor visit is fitted into your way where it costs least, and the errand line says which vendor and when. A quest below you stays on your route while its chain leads to quests still worth XP.
- The hub hand-in run: out in the field, a finished quest waits for the town the route returns to (unless its chain goes on right there), so you quest a good while and then hand in a pile at once - and the card names the run: "Hand-in run here: 6 quests, about 8,400 XP". Plans hold at most 30 quests, leaving 10 slots of your log for dungeon quests and anything else you pick up.
- Long quest chains are valued as a whole when plans are made, so their first parts aren't cut; a trip to a capital has to be worth it.
- Joining the built-in plan partway: quests right next to you that still give XP are offered instead of being skipped as "behind you", and a quest worth XP close by comes before a grind step.
- Quests count as gray by the game's own line (5 levels below you early on, more later): a level 7 is no longer sent to a level 1 quest.
- A quest its giver turns down at two different levels stays off your route; once, it's tried again a level on (Forever asks more than the quest data for some). No more "your path was switched" message when you've just finished a zone.
- Every built-in plan rebuilt with the planner fixes below, and each one played from 1 to 60 by simulated players.
- NPCs Forever renamed are found by their Forever names (Corma Villard, Velarok Windblade, and two more): the Target key and the quest checks missed them.
- Steps say what the quest asks: The Missing Diplomat's fight with Tapoke Jahn said "Speak with", and some kill quests read "Speak with Mottled Boar". The escort tips are only on real escorts.
- Quests handed in at a chest or object in town (The Lost Ingots chain in Menethil) are on the route.
- Quests for Forever's new dungeons stay in the dungeon: Horrors in the Highland (Excavation Site: Wetlands) was a step outside, as if its boss were in Menethil.
- No more "hand it in" right after picking up a quest whose work the quest data doesn't describe (Brewer's Trade in Southshore, and about 90 others): one that leads to a follow-up stays on your route with a "do the work" step that says to follow your quest log, and An Alarming Request is handed in near Dalaran, not in Southshore.

## 1.4.1 - 2026-11-11
- The arrow points the way instead of herding you onto the dotted line: step off it and the line is redrawn from where you are, it looks further ahead along straight stretches, and roads only win when they're nearly on the way.
- Forever Route Targeting now really marks the NPC with a star (it was blocked by the game).
- Logging out is quick again: a timing check rebuilt the route ten times at logout and ran past the game's limit on long plans. The options window opens on screen again.
- A quest its giver turned down once you had the level for it stays off your route, instead of coming back every level.
- Hearth steps only when the game says you're bound there and the hearthstone is ready.
- Good quests nearby that the plan can't hold (giver in a city, objectives elsewhere, or work the quest data doesn't describe, like Brewer's Trade) are offered when you're at the giver.
- The quest log check lists quest items in your bags that are safe to delete.
- The Target button floats just above the card; `/bee target reset` puts it back. "Not doing this quest" no longer covers the title.
- Your path stays put when a new plan arrives, and a switch is announced in chat (`/bee paths`).
- No more stray path flashing on the map.

## 1.4.0 - 2026-11-11
- Horde: built-in plans for every Horde race and class.
- Every Alliance plan rebuilt: through Forever's new zones (Riverglades, Shen'dralas), grinding a level where the quests run out instead of sending you into dungeons.
- The built-in plans are two addons, one per faction, instead of one per race and class (a much shorter addon list).
- The arrow aims a little ahead along the path, so it no longer swings at every corner.
- Walking paths follow the roads and keep away from hostile camps (Elwynn Forest, the Wetlands so far).
- The Forever Route scale slider applies when you let go (it used to jump to its end while dragging); the card can no longer end up off the screen (`/bee card reset` brings it back).

## 1.3.2 - 2026-11-11
- The Target button stays on the card in combat.
- Built-in plans are grouped under Forever Route in the addon list.
- Scrollbars in the route list and the quest log check can be dragged and clicked.
- Option: accept route quests and hand in finished ones automatically (not when there's a reward to choose; hold Shift to skip). Off by default.
- The card no longer fades in combat by default (an option if you liked it).
- One Forever Route scale for the card, arrow, route list and every window (`/bee options` or `/bee scale`); on screens where our text is small (e.g. 4K with ElvUI), a bar offers a bigger size. Clearer grey text.
- Smaller saved files: without the companion app, walking trails and learning data aren't recorded (only the companion uses them) and old ones are cleared. `/bee storage` shows what's kept.
- A long walk inside a zone can become a flight: when a flight path you know lands clearly nearer the spot (Darkshire to Sven's camp by way of Sentinel Hill), the card and the arrow send you to the flight master first.
- Flight points now come from Forever's own flight tables: Mount Hyjal's Tainted Foothills added, both Hyjal points for the Horde too, the Riverglades flight masters at their real spots. Knowing one flight path of a zone no longer counts as knowing its other one.

## 1.3.1 - 2026-11-11
- The Target button sits with the card instead of over every window (the character sheet covers it now).
- Ctrl+drag the Target button anywhere; `/bee target reset` puts it back.
- What's new: resizable, and "Older versions" shows earlier notes.

## 1.3.0 - 2026-11-11
- Starting at any level: the built-in plan picks up where you are, choosing the best nearby part of the plan for your level.
- No more far-away stops (like another zone's flight path) put in front of you.
- In a dungeon, the card shows your quests for it with live progress, and which ones you could have picked up.
- Quest log full: the card goes to hand-ins and objectives first; pick-ups wait until there's room.
- New key: Keybindings > AddOns > "Forever Route Targeting" targets the step's NPC and marks it with a star.
- `/bee report`: copy an anonymous bug report to paste to us.
- What's new: after an update, a bar under the card links to these notes (`/bee news` any time).
- "Run to" until you can ride. Card scale up to 2.0, arrow up to 2.5.
- Correction: 1.2.1's flight path pickup doesn't work on Forever's client; the card now asks you to open any flight master's map once.

## 1.2.1 - 2026-11-11
- Map dots behind you now disappear.
- No more "Error loading ForeverRoute/Route.lua" warning.
- Travel for Riverglades, Shen'dralas and Mount Hyjal.

## 1.2.0 - 2026-11-10
- Calmer card: kill and loot steps take over only when they count; finished quests nearby are offered.
- "Won't do" quests come back if you finish them anyway.
- Route list follows you; minimap shows one pin; greyed world-map pins say why.
- Walking line along the ground in Stormwind, Elwynn and the Wetlands.
- QuestieDB 1.0.14. Elite quests and dungeons are never forced.

## 1.1.1 - 2026-11-10
- Finished quests with their NPC nearby come first.

## 1.1.0 - 2026-11-10
- First release: 1-60 routes for every Alliance race and class.
