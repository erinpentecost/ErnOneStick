# ErnOneStick

OpenMW mod that allows you to play the game on devices that only have one analogue stick (or D-pad).

## Stick Controls
You change which mode you're in with the `Lock Button`, which you assign in the mod settings. You won't need the button that changes between first and third person (the mod assumes all control of camera modes).

In *travel mode*, you have tank controls. Forward and back move your character, left and right yaw the camera. Hold the Lock Button and then use your stick to enter *freelook mode*, which makes your stick pitch and yaw the camera, but you can't move. When you release the Lock Button, you'll go back to *travel mode*. Instead of holding, just tap the Lock Button to enter *target selection mode*.

In *target selection mode*, push your stick up or down to cycle through actor targets. Push your stick left or right to cycle through all other targets. Tap the Lock Button to lock-on to your selected target and enter *lock-on mode*.

In *lock-on mode*, your camera will remain pinned on your target. Your stick moves back and forward and strafes. Tap the Lock Button to go back to *travel mode*.

## Installing

Download the [latest version here](https://github.com/erinpentecost/ErnOneStick/archive/refs/heads/main.zip).

Extract to your `mods/` folder. In your `openmw.cfg` file, add these lines in the correct spots:

```ini
data="/wherevermymodsare/mods/ErnOneStick-main"
content=ErnOneStick.omwscripts
```

## Notes

### Shaders
Shaders are copied from [Max Yari's Dynamic camera effects and target lock](https://www.nexusmods.com/morrowind/mods/55327) mod, with permission.
