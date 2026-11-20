# Story Mode: Script

Notes for implementers:
- Company name: Halcyon Minerals Inc. (Halcyon Minerals in running text). Only the data logs mention it.
- The horror's name for the keeper: 'you' through the descent, 'my sweet' at b8, 'little digger' in the boss chamber and the doom thanks.
- The logs come from other keepers before you (Dale Okafor, Ines Varga, Jay Nguyen, Uki Akamora, Daemin Barnet, Sol Haddad, Pavi Khan), by dig day, plus the company's memos (keeper_welcome, log_b2).
- Narration: a line starting with '> ' is the narrator, not the horror (#137). The user rewrote the beats, logs, endings and boss text by hand (2026-11-13 to 2026-11-19, #285); the pleas are still the first draft.
- Line cues: a horror line may open with {small}, {smaller}, {big} or {huge}, and/or shake and glitch ({smaller shake}, {huge shake glitch}), to size, shake or glitch just that line (beats/BeatBox.gd).
- Data logs: one paragraph per line; the log box puts a blank line between paragraphs and pages long logs.

## Horror's name

- Velle: Latin for 'to want'. It's soft, two syllables, almost a girl's name, and it's the same word as the keeper's greed. The horror and the keeper want the same thing.
- Somna: from sleep, and it sounds like a lullaby. Too on the nose, though: it tells players what it is before they're scared of it.
- Lume: light, a lamp in the dark. It fits the glowing tier-3 text, and it's what draws the keeper down. Pretty, but it doesn't feel ancient.
- Ommoreth: heavy, old and grinding. It sounds like a god under a planet, but also like every fantasy villain, and it fights the sweetness.
- Hush: what the monsters sing to keep it asleep. It's chilling, but the word turns up in normal speech too often to work as a reveal.

Chosen: Velle

## Story beats

Cut in the user's passes (#285), triggers kept in code so a beat can come back: biome_b4, first_gem, unobtainium_1, _3, _5, _7, _10 (2026-11-18), lava_death_2 to _5 (2026-11-19).

### biome_b2 (tier 1)
> You hear a quiet voice whispering something softly. You can't quite tell if the sound is coming from deep below, or from the walls themselves.
---
> You strain to listen, and think you hear faintly:
Hello digger.

### biome_b3 (tier 1)
> You hear a voice again. You're still not sure if the sound is coming from the walls or the deep. You have a passing thought, but try and dismiss it. Maybe the voice is inside your head.
---
I'm so happy you're here.

### biome_b5 (tier 2)
> The heat down here is causing sweat to build up on your face. With no way to wipe it away, the moisture fogs the inside of your visor. Through the fog and rock dust, you think you see something moving.
---
> No. Not moving.
---
> Something watching.

### biome_b6 (tier 2)
> The heat is getting more intense the deeper you drill. You hope it's only from the heat and exhaustion, but you hear the voice again. You really hope it's the heat.
---
They are trying to kill you, the monsters above. It's what they did to me. It's what they did to the others.
---
The others like you.
---
The monsters ripped their homes. Then they ripped their bodies. Only bones remain.  I can help you.  I can save you.

### biome_b7 (tier 3)
> You continue to push through the heat and the rock. As the days pass, you begin to wonder why the monster attacks are getting stronger every day. But these thoughts are interrupted by the voice again. Only this time, the sound is sweet. Like the voice of a long-lost friend.
---
You're trapped here, aren't you?
---
Just like me.
---
They abandoned you.
---
Like a bird with broken wings. No way to fly home.
---
But I can heal your wings.

### biome_b8 (tier 3)
> The heat here is suffocating. But you have no choice except to continue mining. The valuable gems down here are necessary for fending off the waves and waves of brutal assaults on your dome.
---
> Your bones ache from mining. You're sleep deprived. Every night you are awoken by the siren of another attack. You're certain now it's a hallucination when you hear the voice again echo though the cavern.
---
You are almost home, my sweet. Keep digging just a bit more. I have what you need to fly home. Simply break the chains.

### lava_ocean (tier 3)
> You crack the final rock, you are blown back by a wave of intense heat. You regain your bearings, and look down. Below you floats a bubbling ocean of lava.
---
> The voice rises from below the lava. This time loud and booming. The voice fills the chamber, clearly heard over the loud churning of the lava.
---
Dive in. Take them.
---
Then fly free from this prison.

### gate_broken (tier 2)
> The metal shards explode in a deafening boom. You wipe the dust from your visor as an eerie silence settles on the cave.
---
> ...
---
> You hope it's your imagination, but you think you hear the faint voice again from somewhere deep in the gloom.
---
{small} Thank you.
---
{smaller shake} Only one more seal to break.

### lava_death_1 (tier 2)
> Your suit overheats. The temperature rises so quickly that your vision fades to black, certain this is the end.
---
> You open your eyes and you are back in the dome.
---
> Confused and dazed and not sure if you are dreaming, you can't shake the feeling someone, or something saved you.

### translator_1 (tier 1)
> You bring the alien artifact back into your dome for closer study. It's covered in alien symbols and hums and sings quietly. It sounds just like the animals outside your dome.
---
> You struggle to understand the meaning. After some frustration, you shout: "Please! Help me understand!"
---
> The machine responds, singing back. Excited, you try again. "Please. Help me." you repeat. It sings the same sounds. You realize this might be a crude translator.
---
> You practice and think you learn a few words.
---
> Just as you are getting the hang of it, the machine starts to buzz and pop, then goes quiet. With no way of knowing how to fix it, you stash it away and get back to work.

### translator_2 (tier 2)
> You find a second device, this one still seems to be working.
---
> You were correct on this being a translator because you've been starting to understand the creatures outside the dome.
---
> Excited, you practice and memorize more words.
---
> Eventually however this one also starts to fizz and pop and goes quiet. You are not sure why and have no way to repair it, but at least you've learned more.

### translator_3 (tier 3)
> You find a third translator, this one seems to be in better condition than the first two. The sounds are clearer and more responsive.
---
> With this one working so well, you are able to replay the dome's recorded sound from the daily attacks, and start to piece together every word they are saying during the attacks.
---
> You're not sure if knowing what they say brings you comfort, or dread.

### boss_chamber (tier 4)
Why did you come here, little digger? We are both free now. You could have flown home.
---
But, now that you are here. I am so very...
---
{big shake} hungry.

## Pleas

### Stage A (B1 to B2): warning

#### arrive
- *Stop*. Go home, small digger.
- Ground is *sleeping*. Let it sleep.
- You dig *wrong* place. *Leave*.
- Not for you. Go *away*, please.
- We *warn*. We only warn.
- Quiet the drill. Something *listens*.

#### fight
- *Why* you *dig*? Why?
- No more *holes*. No more!
- *Stop* the drill!
- We not want *hurt*. Just *stop*.
- Down is *bad*. Down is bad!
- You *hear* it? Do not *listen*.
- Go *up*. Go *home*.
- Leave the stones. Stones keep it *asleep*.

#### death
- Please... *stop*...
- Tell it... we *tried*...
- *Warned* you. Warned you...
- Not us... *it*... it wakes...
- Go *home*, digger...
- So *quiet*... soon so quiet...

### Stage B (B3 to B5): begging

#### arrive
- *Please*. We beg you. *Please*.
- *Stop* digging. We give anything.
- It *sleeps* under you. Please!
- Small digger, *listen*. Only listen.
- We bring no anger. Bring *fear*.
- Every hole you make, it *breathes*.

#### fight
- *Please*! Please stop!
- It *talks* to you. It *lies*.
- Warm rock is *it*. Not warm. *It*!
- Do not go *deeper*!
- We have *children* up here!
- It *whispers*? Cover your *ears*!
- You are *helping* it!
- *Stop*, stop, stop!

#### death
- Please... *please*...
- My *children*... keep them...
- It says... *deeper*... do not...
- You... *heard*... us?
- Not angry... *afraid*...
- *Sorry*... sorry we hit dome...

### Stage C (B6 to B8): despair

#### arrive
- Too *deep*. You are too deep.
- Others came *down*. *Never* came up.
- *Why*? Why you not stop?
- We fight. Nothing *else* left.
- *Bright* stone holds it *down*.
- Leave the *seal*. It is last.

#### fight
- *Turn* back! Still time!
- It does not *love*. It *eats*.
- We are *dying* for this!
- Last *seal*! Last one!
- Not *hate* you. *Fear*!
- Hear *us*! Not it. Us!
- *Bones* below. Miner *bones*. Look!
- For *shiny*? All this for shiny?

#### death
- No more... *time*...
- It *smiles*... we feel it smile...
- Was our *home*... was home...
- You will... *wake* it...
- *Remember* us...
- Go *up*... while sky still...

### Stage D (lava ocean and below): grief

#### arrive
- *Too* *late*. Too late now.
- It is *waking*. You did this.
- We came to say *goodbye*.
- No fight left. Only *sing*.
- We sing it to *sleep*. It not listen.
- The *ground* is *breathing*.

#### fight
- Was there *nothing* we could say?
- *Shiny*. All this for shiny.
- Our young hide. *Nowhere* to hide.
- Hit dome. *Nothing* else to do.
- Stop *now*? Please? Even now?
- It *sings* to you. We *hear* it.
- You were *warned*. Every day, warned.
- *Sky* goes *dark* soon.

#### death
- *Goodbye*... digger...
- At least... I *sleep* first...
- I *forgive*... I try to...
- *Home*... was so *pretty*...
- You took... *everything*...
- *Dark* now... very dark...

## Data logs

### keeper_welcome
Title: MEMO: Keeper Onboarding and Welcome
Congratulations on your new assignment and safe landing, Keeper!
From everyone here at Halcyon Minerals, thank you! You are the CORE of what we do!
Be aware that local fauna are agitated by mining operations. They can be easily managed with your company-issued Dome Defense™ equipment.
Please also be aware that all mined Minerals are company property. Do not attempt to modify the stock Dome Defense™ with mined Minerals, as this will be docked from your pay and could result in penalties up to and including termination.
We are looking forward to a long and productive dig.
— Halcyon Minerals Inc.

### log_b1
Title: Personal Keeper Log // Dale Okafor // Dig Day 3
The bugs hit the dome again. More bugs today than yesterday. The company-issued laser held them off, but one hit the dome and caused a small crack.
I'm worried if more bugs come, I'll need to use some minerals to upgrade the laser power. Technically against the rules. But I don't want to imagine what will happen if the dome crack spreads.

### log_b2
Title: Halcyon Minerals Inc // Keeper Memo // Alien Artifact Policy
MEMO - ALL KEEPERS: We have received reports of unknown alien artifacts discovered during some Keeper digs. These artifacts may be dangerous, do not extract or investigate.
For your own safety, under no circumstances should you bring them into the dome.
As a reminder, bonuses will continue to be awarded for minerals extracted from Layer 4 and beyond.

### log_b3
Title: Personal Keeper Log // Ines Varga // Dig Day 7
It's been a week of mining. The bugs keep getting stronger. I'm starting to hear their screams even in my dreams. Been hard to sleep.
I'm probably just tired but I'm starting to hear voices down in the mine.
The company said not to waste resources on the dome, they said the dome is strong enough to hold.
But they can't hear the screams.

### log_b4
Title: Personal Keeper Log // Jay Nguyen // Dig Day 9
I found something down here. Not just gems or minerals. It was some type of alien machine.
I read the company memo about not researching alien artifacts. But I also read the company memo about not using minerals on dome defenses, what a joke. The waves of bugs are getting really strong now, I would be long dead if I hadn't fixed up the dome. Still probably need to make it stronger.
Anyway, the artifact seems to let me understand the creatures, a little bit at least. I think they are saying "help" and "please". It doesn't make sense. They are trying to kill me.
Will continue further research on the artifacts.

### log_b5
Title: Personal Keeper Log // Uki Akamora // Dig Day 14
It's creepy down here. Not to mention hot. The suit's heat shielding is barely keeping up anymore. Is this an old volcano or something?
I've just got this sense of dread with every rock I drill. Can't shake the feeling I'm being watched. Starting to think about calling for the evacuation soon.
Between the monster attacks, the intense heat, and this... voice. The pay just doesn't seem worth it.

### log_b6
Title: Personal Keeper Log // Daemin Barnet // Dig Day 16
Ok that's it, I'm calling for the evacuation. Today's my last day digging. Don't care if they dock my pay or fire me.
I heard that voice again. It was clear this time, not whispers like before. It said the monsters will rip me apart.
There's monsters above me. And there's something down here with me. Get me out of here!

### log_b7
Title: Personal Keeper Log // Sol Haddad // Dig Day 18
No? No, no, no, no!
I called for evacuation. Request denied? What the hell do they mean request denied?
There's... something down there, and there's monsters beating at my dome. It's barely intact. The cracks have spread across the entire dome.
Request denied??
I'm not going down there. But I can't stay here.
What do I do?

### log_b8
Title: Personal Keeper Log // Pavi Khan // Dig Day 21
This will be my last log.
My dome was breached. The monsters kept getting more aggressive the deeper I went. I couldn't hold them off. I'm sheltering down here, hoping, praying they, or IT won't find me.
I won't last long without my dome. There's no food, no water. The heat is unbearable. I'm low on oxygen. But I would rather die down here than be ripped to pieces.
If you are reading this, I finally finished the translator. The bugs are pleading me to stop mining, that if I keep going I'll awaken IT. But if I stay here I'll die.
I don't really have a choice but to keep going and see what's down there.

## Doom ending

### horror_thanks
Oh, sweet, sweet air. I'd forgotten the air.
---
Thank you, now we are both free. Fly home little digger and never return.
---
Oh, look at all the sheep up here... I'm salivating....
---
It's time to
---
{huge shake glitch} feast.

### planet_end
The keeper fled the planet, heavy with minerals.
Below you, the ground shook and opened like an eye.
Safe in your ship, you were spared from hearing the screams.

### monsters_last
- Why, digger, *why*?
- We *tried*. We tried so hard.
- *Sleep* now, little ones. Close your *eyes*.

## Saved ending

### saved
The voice inside your head finally went quiet, and stayed quiet.
The creatures stopped attacking the dome.
You could finally breathe easy.
You stopped mining and finally got some rest as you awaited the scheduled pickup.
As your ship was departing, in the distance you could still hear them singing.

## Boss

Draft lines for the boss sequence (`data/boss_text.gd`).

### monsters_thanks
- We are finally *free*.
- The *hunger* is *still*. We *thank* you.
- *Sleep* now, deep one. Go in *peace*, digger.

### fallen
You are gripped and squeezed tight by the horror's tentacles.
The last thing you see before everything goes dark
Is the great eye.
Then, the teeth.

## End screen titles

Doom title: The Planet Is Lost
Doom subtitle: The company gave you a 5% bonus.

Saved title: The Planet Is Saved
Saved subtitle: Saved by the hands that nearly ended it.

Fallen title: The Planet Is Lost
Fallen subtitle: You woke it. Nobody was left to stop it.
