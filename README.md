# yazbg
yet another zig block game! 

![Screenshot of yazbg](screenshot.jpg)


block games [tm] have always been my goto project for learning a new language. so here we are, my first zig program.

raylib is used for graphics and input handling.

https://www.raylib.com/

## install
```bash
git clone https://github.com/pkdindustries/yazbg
cd yazbg
zig build benchmark
zig build run
```

## controls
```
  left/right: move
  up: rotate
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
