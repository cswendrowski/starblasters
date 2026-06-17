### Turret Mechanics
At 75%, 50%, 25%, it loses a random turret. The turret explodes (small circle explode) and is replaced with a burning trail particle effect. If it's in its high hold and jiggle state the particle needs downward force to visually simulate the ship in motion.

The Turrets have these fire modes:
- Cycling Shots: The turrets alternate firing aimed bolt shots at the player. Which turret fires is random, but the cadence is slow and steady, and every turret fires at least once before the next one can fire again.
- Sweeping Shots: The left turrets aim left and fire bolts while swinging right toward the middle of the ship, while the right turrets do the opposite and swing left to the center, both sets of cannons converging their shots in the middle. These aren't aimed at the player, but meant to fill the screen with some bullets.
- Downward Salvo: The turrets aim straight forward (toward front of the ship) and fire three shot bursts downward. They do this three times.
The repeating turret pattern is: Cycle. Salvo. Sweep. However, each time the Shepherd moves to a new phase the pattern should be randomized for that phase.
# Initial Arrival
It should arrive in the same lane as the supremacy missile cruise initially, flying from the bottom of the screen, fly toward the top of the screen, and then "rise" up to the play area. 
## Phase 1
Trigger: Finished arrival.
Once it arrives in the play area it begins firing its turrets at the player while doing a slow jiggle drift at a high hold position.
## Transition 1
Trigger: At 75% health or after 20s 
Becomes invincible for this animation: Its engines flash red three times then flare, creating a damage area to players that are too close, and destroying incoming projectiles. Use the gun muzzle flash sprite strip for now, we'll replace it with new art later.
## Phase 2
The Shepherd accelerates rapidly and flies up, off the screen. Then does a top to bottom pass like a missile cruiser, firing missile salvos that sweep top to bottom, forcing the player to reposition. It holds a high position in the background, fires three cycles of zone strike missiles with 2s gaps.
**Exit Transition:** It flies off the bottom of the screen and does its initial arrival again, returning to Phase 1.
## Phase 1.5
Repeat Phase 1. But after it reaches 50% health or 20s, move to Phase 3.
**Exit Transition:** Use Transition 1.
## Phase 3
The Shepherd returns from the top, now facing the player, and sweeps left and right while firing large rockets downward from its muzzle points. Pattern is left-right-left-right, or left-left-right-right, or left+right x 2, and it cycles that pattern. It also begins releasing its fire cores one after another until they are gone, doing one every few seconds.

It holds Phase 3 until destroyed or the player dies, whichever occurs first.


