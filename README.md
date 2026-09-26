# RGB LED driver for musics and stuff

Pretty lights + music are nice, yes?

## PWM driver

MOSFET + arduino/teensy schematic not included. it's pretty simple, though.

<img src="https://i.imgur.com/jEZeXox.jpg" />

<img src="https://i.imgur.com/YjINdCb.jpg" />

### Watch it in action

[![demo](https://img.youtube.com/vi/ucP3iEoqw-0/0.jpg)](https://www.youtube.com/watch?v=ucP3iEoqw-0)

## Browser USB control

The standalone browser project lives in `control-js`. Its production build is one self-contained HTML file:

```sh
cd control-js
pnpm install
pnpm open
```

`npm install && npm run open` works too. The command builds `dist/index.html` and opens it with `xdg-open` on Linux, `open` on macOS, or `start` on Windows. Stop `flashist.service`, then grant WebHID access. There is no backend or device proxy.

The source is native ES modules:

```js
import {Flashist} from './src/flashist.js';
import {gameShowEffects} from './src/game-show-effects.js';

const flashist = new Flashist();
await flashist.connect();
await flashist.replace(gameShowEffects.thinking({difficulty: 7}));
```

`enqueue(effect)` runs async effect callbacks in FIFO order. Each callback receives `setColor`, `fadeTo`, `hold`, `sineWave`, `wavegen`, `blink`, `repeat`, and `wait` primitives. `replace(effect)` cancels the current effect and queued work. `stop()` cancels everything and sends black; `disconnect()` also closes the USB device.

| Preset | Default cue |
| --- | --- |
| `stepRightUp({attention})` | Carnival invitation scaled from attention 1–10 |
| `betweenRounds()` | Slow, subdued color drift while the game waits between rounds |
| `roundStart()` | Rising blue launch cue into active play |
| `thinking({difficulty, durationMs})` | Green-to-red breathing pulse scaled from difficulty 1–10 |
| `lockedIn()` | White-to-amber confirmation while the answer is accepted |
| `reveal()` | Slow violet suspense pulse until the result arrives |
| `timeUp()` | Three white/red timeout hits settling into dark red |
| `rightAnswer({flashes, holdMs})` | Three eased green flashes, then green hold |
| `wrongAnswer({flashes, holdMs})` | Three eased red flashes, then ember hold |
| `youWon({durationMs, holdMs})` | Gold charge, white jackpot bursts, color storm, gold finale |
| `youLost({durationMs})` | Slowing dim-red pulse fading to black |

