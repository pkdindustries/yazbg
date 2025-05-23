# yazge
yet another zig game engine! 

because the world clearly needed another "engine" 

its just raylib taped to zig-ecs with bad opinions 

current status: can render falling squares

https://www.raylib.com/
https://github.com/prime31/zig-ecs

![Screenshot of yazbg](screenshot.jpg)


## install
```bash
git clone https://github.com/pkdindustries/yazbg
cd yazbg
# build and run the blocks game
zig build run
# wasm
zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseSmall --sysroot <emsdk>

```

## blocks game controls
```
  left/right: move
  up: rotate
  z: rotate
  down: drop
  space: hard drop
  c: swap piece
  b: next background
  m: mute
  n: next music
  p: pause
  r: reset
```

tested with zig version: `0.14.0`
