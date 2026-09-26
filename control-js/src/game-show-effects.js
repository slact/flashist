function number(value, fallback, min, max) {
  const result = Number(value === undefined ? fallback : value);
  if (!Number.isFinite(result)) throw new TypeError('Effect options must be finite numbers');
  return Math.max(min, Math.min(max, result));
}

function dimColor(color, brightness) {
  const match = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(color);
  if (!match) throw new TypeError('Expected a six-digit RGB hex color');
  return `#${[1, 2, 3].map(index => Math.round(parseInt(match[index], 16) * brightness).toString(16).padStart(2, '0')).join('')}`;
}
async function softBlink(fx, color, dim, options) {
  for (let i = 0; i < options.flashes; i++) {
    await fx.fadeTo(color, options.edgeMs);
    await fx.hold(color, options.onMs);
    await fx.fadeTo(dim, options.edgeMs);
    if (i + 1 < options.flashes) await fx.wait(options.offMs);
  }
}

const thinkingColors = ['#00c878', '#35c85f', '#69c748', '#9ac43a', '#c5bd2e', '#e0aa24', '#ee8d1d', '#f16c19', '#ed4818', '#df271c'];
const stepRightUpColors = ['#ff1744', '#ffb000', '#00d4ff', '#8b5cff', '#ff3cac'];

function stepRightUp(options = {}) {
  const attention = Math.round(number(options.attention, 7, 1, 10));
  const urgency = (attention - 1) / 9;
  const brightness = 0.35 + 0.65 * urgency;
  const colors = stepRightUpColors.map(color => dimColor(color, brightness));
  const edgeMs = Math.round(220 - 160 * urgency);
  const holdMs = Math.round(140 - 90 * urgency);
  const flashes = 1 + Math.floor(attention / 3);

  return fx => fx.repeat(async loop => {
    for (const color of colors) {
      await loop.fadeTo(color, edgeMs);
      await loop.hold(color, holdMs);
    }
    await softBlink(loop, dimColor('#ffffff', brightness), dimColor('#8a3400', brightness), {
      flashes, onMs: holdMs, offMs: Math.round(holdMs * 0.6), edgeMs: Math.round(130 - 70 * urgency)
    });
  });
}

function betweenRounds() {
  return async fx => {
    await fx.fadeTo('#030303', 600);
    await fx.wavegen({colorCyclingSpeed: 0.0007, brightnessCyclingSpeed: 0.001, brightnessCyclingMin: 0.01, brightnessCyclingMax: 0.16});
  };
}

function roundStart() {
  return async fx => {
    await fx.fadeTo('#001020', 150);
    await fx.sineWave('#00bfff', {durationMs: 900, fromHz: 1, toHz: 4, minBrightness: 0.05, maxBrightness: 0.85});
    await fx.fadeTo('#0080ff', 120);
    await fx.hold('#0080ff', 200);
  };
}

function lockedIn() {
  return async fx => {
    await fx.fadeTo('#ffffff', 90);
    await fx.hold('#ffffff', 120);
    await fx.fadeTo('#ffb000', 240);
    await fx.hold('#ffb000', 400);
  };
}

function reveal() {
  const wave = {durationMs: 1600, fromHz: 0.625, toHz: 0.625, minBrightness: 0.04, maxBrightness: 0.4};
  return async fx => {
    await fx.fadeTo('#06040a', 350);
    await fx.repeat(loop => loop.sineWave('#9b5cff', wave));
  };
}

function timeUp() {
  return async fx => {
    await softBlink(fx, '#ffffff', '#ff3000', {flashes: 3, onMs: 120, offMs: 70, edgeMs: 55});
    await fx.fadeTo('#300000', 250);
    await fx.hold('#300000', 600);
  };
}

function thinking(options = {}) {
  const difficulty = Math.round(number(options.difficulty, 5, 1, 10));
  const urgency = (difficulty - 1) / 9;
  const color = thinkingColors[difficulty - 1];
  const cycleMs = Math.round(3400 - 1600 * urgency);
  const wave = {fromHz: 1000 / cycleMs, toHz: 1000 / Math.round(1100 - 700 * urgency), minBrightness: 0.04, maxBrightness: 0.45};
  const durationMs = options.durationMs === undefined ? Infinity : number(options.durationMs, 0, 0, 86400000);
  const pulse = fx => fx.sineWave(color, {durationMs: cycleMs, ...wave, toHz: wave.fromHz});

  return async fx => {
    await fx.fadeTo(dimColor(color, 0.04), 350);
    if (durationMs === Infinity) return fx.repeat(pulse);
    await fx.sineWave(color, {durationMs, ...wave});
  };
}

function rightAnswer(options = {}) {
  const flashes = Math.floor(number(options.flashes, 3, 1, 12));
  const holdMs = number(options.holdMs, 900, 0, 30000);

  return async fx => {
    await fx.fadeTo('#000a03', 120);
    await softBlink(fx, '#00ff50', '#000a03', {flashes, onMs: 90, offMs: 65, edgeMs: 90});
    await fx.fadeTo('#00ff50', 100);
    await fx.hold('#00ff50', holdMs);
  };
}

function wrongAnswer(options = {}) {
  const flashes = Math.floor(number(options.flashes, 3, 1, 12));
  const holdMs = number(options.holdMs, 700, 0, 30000);

  return async fx => {
    await fx.fadeTo('#080100', 120);
    await softBlink(fx, '#ff2400', '#080100', {flashes, onMs: 105, offMs: 75, edgeMs: 90});
    await fx.fadeTo('#8c1400', 120);
    await fx.hold('#8c1400', holdMs);
  };
}

function youWon(options = {}) {
  const durationMs = number(options.durationMs, 8000, 1500, 30000);
  const holdMs = number(options.holdMs, 4000, 0, 30000);

  return async fx => {
    await fx.sineWave('#ffd700', {durationMs: 2000, fromHz: 0.5, toHz: 6, minBrightness: 0.02, maxBrightness: 1});
    await softBlink(fx, '#ffffff', '#7a1800', {flashes: 6, onMs: 45, offMs: 30, edgeMs: 55});
    await fx.wavegen({durationMs, colorCyclingSpeed: 0.028, brightnessCyclingSpeed: 0.05, brightnessCyclingMin: 0.3, brightnessCyclingMax: 1});
    await softBlink(fx, '#ffffff', '#ffd700', {flashes: 5, onMs: 70, offMs: 45, edgeMs: 90});
    await fx.hold('#ffd700', holdMs);
  };
}

function youLost(options = {}) {
  const durationMs = number(options.durationMs, 3200, 1000, 30000);

  return async fx => {
    await fx.fadeTo('#030000', 250);
    await fx.sineWave('#ff1a00', {durationMs, fromHz: 0.65, toHz: 0.18, minBrightness: 0.01, maxBrightness: 0.4});
    await fx.fadeTo('#000000', 1000);
  };
}

export {stepRightUp, betweenRounds, roundStart, thinking, lockedIn, reveal, timeUp, rightAnswer, wrongAnswer, youWon, youLost};
export const gameShowEffects = Object.freeze({stepRightUp, betweenRounds, roundStart, thinking, lockedIn, reveal, timeUp, rightAnswer, wrongAnswer, youWon, youLost});
