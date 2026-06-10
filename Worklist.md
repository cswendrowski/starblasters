### Core
Go to Forward+ renderer, and commit to a windows-only build for enhanced graphics and performance. This will be the new itch publishing setup going forward. The site should already be configured for this.
### Play Area
- Off-screen enemies need to not be killed if hit by bullets or bomb waves.
- Build the Pillar 2 Recycler concept based on the recycler overhaul, and merge the missile cruiser encounter to it, rather than using its bespoke version. Merge existing enemies onto the new recycler system.
- Build a wreck_layer. This will sit at roughly the same visual depth and color grading style as the near parallax layer. Enemies that die will "fall" into this layer. This will initially be used for the EM torpedo (detailed below) as the testbed. If it works well we will build out more death styles, such as for the bomber encounter, where enemies fall into this layer for special death animations.
### Outpost
- Primary vs core blaster disambiguation is necessary, the concept has been confusing players. Blaster is "Blaster" and Primary cannons are "Primary Weapons" now.
- The label of the item should pick up the rarity color.
- Remove "Tier" from the item subtitle, it's proven confusing, just note the type IE: "Secondary Weapon" 
- Players can end up with multiple equipped cannons, build a safeguard into the outpost that catches this and makes sure the player only has one of each thing equipped, moving the excess items to their hold. Ideally it keeps the higher mark item and stows the lower one, if they are the same, pick one at random.
- Upper right label on the outpost menu should state "Defeat boss to restock."
- Make sure items rolled don't dupe, and don't roll items the player already has unless they are better. So if the weapon has a MK2 rotary laser and a MK1 autolaser in hold, and a mk2 blaster, don't roll any of those items unless they are 1 mark higher.
- Item cards should show what the buyable item does, so devise a way for dynamic item cards with text that shows that mark's stats or specific improvement. Ideally we avoid every item having 9 strings for its upgrades.
### Onboarding
- Overhaul onboarding text where it is most stale and to cover missing gameplay elements. Rather than adding new pages, attempt to utilize the existing pages better, adding pages only if necessary.
### Music
- Music is not ramping properly at all.
- Intensity 1 should ramp up to Intensity 2 when the first waves arrive.
- Intensity 2 should ramp up past wave 4 to Main.
- When a boss fight starts always ramp up to Main.
- Ramp down to intensity 1 when a level is cleared.
### Patterns
Adjust Omni movement to avoid leaving the firing zone, and respect the no-fly zone at the bottom of the screen unless choosing to exit. This prevents the enemy from getting down into that space where the player can't reach.
Lane Hook pattern is not leaving the play area properly.
### HUD
- Flash the weapon light when a weapon is regenerating ammo (autolaser, rotary laser)
- Darken the weapon light when a weapon has no ammo.
- Ammo count should always show during a level, even if it's 0. 
- There's a weird out of ammo glyph like the font character is missing.
### Enemies
Supremacy Push enemy needs to come in controlled numbers, one to a lane, or one per crossing so they don't bunch up and overlap. We have them appearing in huge, overlapping globs that look awful.
### Enemy Bench
- Let me tag if an enemy should be able to recycle, how many times, and chance to recycle or flee.
### Sector Map
- Manage ship needs to let you see and manage your shift mode items.
- Music intensity should ramp up permanently by 1 step when the player beats a boss.
### Visual Effects
Move all zealot enemies to the new ball explosion, and play this explosion only if they die and don't drop a firecore. Also give the firecore this explosion. If a zealot enemy dies and does drop a core, play the normal explosion.
### Enemy Weapons
Cannons still wrong, they aren't animated, the frame for the projectile is randomly chosen on firing. Glow is still being applied to the entire sprite, not the chosen frame.
### Player Weapons
The Rotary Laser should use the same laser projectile/sprite as the auto laser from MK5 onward. Damage, rate of fire, etc, remain unchanged from what exists now.
## DEV
Hangar muzzle flashes colored green, bullets missing. Do a deep dive on what the hell is wrong with the hangar and rebuild the subviewport so it works correctly.
### Phase Mode
- Make phase mode look like something when active. Turn blue and leave fading blue after-images.
- Make phase mode actually work: make the player invulernable, disable hitting enemies, and let the player absorb enemy bullets, restoring 1 shield point per bullet absorbed. Have it last for a 3 second window, but also disable shooting.
### Hyper Mode
- Make the player outline pulse orange while active, speeding up as it begins to run out.
### Audio
- Enemy firing sounds replaced with .OGG files, update audio to account for this file change.
- Multiple new sounds added for incoming weapons
- Replaced audio for rotary laser and wave gun, wave gun now has just one audio set, and doesn't swap at mark5 any longer.
- Added sounds for the auto laser and spread cannon.
- Added sounds for the smart bomb to be played when it detonates.
- Added sound to be played when the player carries out certain actions at the outpost, filenames should indicate intended purpose.
- Process sounds in Explosion folder, they need to be renamed, ex: TomWinandySFX_Explosions Volume I_CloseExplosion_01 >> CloseExplosion_01
- Wire up the new explosion sounds, retire the old ones. Set up a system for playing the close/medium/distant explosion sounds based on the distance of the explosion to the player. 

### New Primary Weapons
Minigun: 
New weapon, this weapon should pattern after the machinegun cannon's starting ammo and mark progression to start. It uses the minigun stop sound when it finishes firing, but this can be interrupted if the player starts firing again. The rate of fire should be the same as the rotary later. The bullets are hitscan, so this is technically a beam weapon that should damage the first enemy its beam of bullets hit. It uses the minigun_tracer sprite for its beam of bullets (no animation). It uses the machinegun cannon's muzzleflash and shell eject, but uses the small shell sprite.

Autocannon: 
This weapon replaces/reworks the Machinegun Cannon but retains some parts of it. Weapon has a 1.5 firing delay as the start sound plays, and plays the stop sound when the last shot fires. It fires the same projectiles and does the same damage, uses the same muzzle flash and projectiles and has the same scaling as the machinegun cannon. It can interrupt the stop sound to spin up again, but the gun must go through the start sound/delay first.

### New Secondary Weapons
EM Torpedo: 
When fired it sends out a large rocket (use the associated rocket projectile) that flies forward for two seconds then erupts into a burst of blue-yellow lightning that hits multiple enemies. Strips and ignores shields, and causes rockets/missiles to explode. It also has an alternate kill effect: Enemies have a 25% chance of exploding, and a 75% chance of becoming inert and drifting (with slight, randomized rotation) toward the bottom of the screen while trailing smoke (use the same smoke effect as the player, but have it respect parent motion).