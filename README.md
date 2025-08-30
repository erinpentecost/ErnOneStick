# ErnOneStick

OpenMW mod that allows you to play the game on devices that only have one analogue stick (or D-pad).

## Stick Controls
You change which mode you're in with the `Lock Button`, which you assign in the mod settings. You won't need the button that changes between first and third person (the mod assumes all control of camera modes).

In *travel mode*, you have tank controls. Forward and back move your character, left and right yaw the camera. Hold the Lock Button and then use your stick to enter *freelook mode*. Instead of holding, just tap the Lock Button to enter *target selection mode*. If enabled, attacking an NPC or Creature while in this mode will automatically put you into *lock-on mode*.

In *freelook mode*, your stick pitches and yaws the camera, but you can't move. When you release the Lock Button, you'll go back to *travel mode*. You'll need to enter this mode to aim up or down when swimming or levitating.

In *target selection mode*, push your stick up or down to cycle through actor targets. Push your stick left or right to cycle through all other targets. Tap the Lock Button to lock-on to your selected target and enter *lock-on mode*. Alternatively, use the `Activate` button to use the thing or talk to the person you are looking at. After using `Activate`, you be placed back into *travel mode*.

In *lock-on mode*, your camera will remain pinned on your target. Your stick moves back and forward and strafes. Tap the Lock Button to go back to *travel mode*.

## Super Toggle Button
You can optionally map a multi-function toggle key, if you are running out of buttons. Tap it to cycle through Hands Down, Ready Spell, and Ready Weapon. Long press to toggle Sneak.

## Installing

Download the [latest version here](https://github.com/erinpentecost/ErnOneStick/archive/refs/heads/main.zip). The mod's Nexus page is [here](https://www.nexusmods.com/morrowind/mods/57315).

Extract to your `mods/` folder. In your `openmw.cfg` file, add these lines in the correct spots:

```ini
data="/wherevermymodsare/mods/ErnOneStick-main"
content=ErnOneStick.omwscripts
```

After installation, **you must assign a button to the Lock Button action in the mod settings.**

## Credits

### Shader

The shader is copied from [Max Yari's Dynamic camera effects and target lock](https://www.nexusmods.com/morrowind/mods/55327) mod, with permission.

### Sounds

- Wind 1 Loop by jasoneweber -- https://freesound.org/s/179110/ -- License: Attribution 3.0
- ping.mp3 by jolup123 -- https://freesound.org/s/668790/ -- License: Creative Commons 0
- Breath In by mooncubedesign -- https://freesound.org/s/319247/ -- License: Creative Commons 0
- cancel.wav by pierrecartoons1979 -- https://freesound.org/s/90119/ -- License: Attribution NonCommercial 3.0

## Contributing

Submit a merge request or file an issue in the [GitHub repo](https://github.com/erinpentecost/ErnOneStick). Any code submitted must be your own work. See the [CONTRIBUTING document](https://github.com/erinpentecost/ErnOneStick/blob/main/CONTRIBUTING) for more info.
