import {Flashist} from './flashist.js';
import {gameShowEffects} from './game-show-effects.js';

const status = document.querySelector('#status');
const keepalive = document.querySelector('#keepalive');
const effectStatus = document.querySelector('#effect-status');
const connectButton = document.querySelector('#connect');
const disconnectButton = document.querySelector('#disconnect');
const effectDefinitions = [
  {
    id: 'step-right-up',
    label: 'Step right up',
    factory: 'stepRightUp',
    options: [
      {name: 'attention', label: 'Attention (1–10)', value: 7, min: 1, max: 10, step: 1}
    ]
  },
  {
    id: 'between-rounds',
    label: 'Between rounds',
    factory: 'betweenRounds',
    options: []
  },
  {
    id: 'round-start',
    label: 'Round start',
    factory: 'roundStart',
    options: []
  },
  {
    id: 'thinking',
    label: 'Thinking',
    factory: 'thinking',
    options: [
      {name: 'difficulty', label: 'Difficulty (1–10)', value: 5, min: 1, max: 10, step: 1},
      {name: 'durationMs', label: 'Duration (ms)', placeholder: 'until stopped', min: 0, max: 86400000, step: 100}
    ]
  },
  {
    id: 'locked-in',
    label: 'Locked in',
    factory: 'lockedIn',
    options: []
  },
  {
    id: 'reveal',
    label: 'Reveal',
    factory: 'reveal',
    options: []
  },
  {
    id: 'time-up',
    label: 'Time up',
    factory: 'timeUp',
    options: []
  },
  {
    id: 'right-answer',
    label: 'Right answer',
    factory: 'rightAnswer',
    options: [
      {name: 'flashes', label: 'Flashes', placeholder: '3', min: 1, max: 12, step: 1},
      {name: 'holdMs', label: 'Final hold (ms)', placeholder: '900', min: 0, max: 30000, step: 50}
    ]
  },
  {
    id: 'wrong-answer',
    label: 'Wrong answer',
    factory: 'wrongAnswer',
    options: [
      {name: 'flashes', label: 'Flashes', placeholder: '3', min: 1, max: 12, step: 1},
      {name: 'holdMs', label: 'Final hold (ms)', placeholder: '700', min: 0, max: 30000, step: 50}
    ]
  },
  {
    id: 'you-won',
    label: 'You won',
    factory: 'youWon',
    options: [
      {name: 'durationMs', label: 'Celebration (ms)', placeholder: '8000', min: 1500, max: 30000, step: 100},
      {name: 'holdMs', label: 'Final hold (ms)', placeholder: '4000', min: 0, max: 30000, step: 100}
    ]
  },
  {
    id: 'you-lost',
    label: 'You lost',
    factory: 'youLost',
    options: [
      {name: 'durationMs', label: 'Pulse duration (ms)', placeholder: '3200', min: 1000, max: 30000, step: 100}
    ]
  }
];
const effectsHost = document.querySelector('#game-show-effects');
let latestEffect = 0;

function optionControlMarkup(effectId, option) {
  const id = `${effectId}-${option.name}`;
  const value = option.value === undefined ? '' : `value="${option.value}"`;
  const placeholder = option.placeholder === undefined ? '' : `placeholder="${option.placeholder}"`;
  const constraints = ['min', 'max', 'step']
    .map(name => `${name}="${option[name]}"`)
    .join(' ');
  return `<label for="${id}"><span>${option.label}</span><input id="${id}" type="number" data-option="${option.name}" ${value} ${placeholder} ${constraints}></label>`;
}

effectsHost.innerHTML = effectDefinitions.map(effect => `
  <section class="effect">
    <div class="effect-header">
      <button id="${effect.id}" type="button" disabled>${effect.label}</button>
      ${effect.options.length ? `
        <details>
          <summary>Options</summary>
          <div id="${effect.id}-options" class="option-grid">
            ${effect.options.map(option => optionControlMarkup(effect.id, option)).join('')}
          </div>
        </details>
      ` : ''}
    </div>
  </section>
`).join('');

const effectButtons = [...document.querySelectorAll('.effects button')];
const stopButton = document.querySelector('#stop');

function setConnected(connected) {
  connectButton.disabled = connected;
  disconnectButton.disabled = !connected;
  effectButtons.forEach(button => { button.disabled = !connected; });
}

function watchEffect(name, promise) {
  const id = ++latestEffect;
  effectStatus.textContent = `Playing: ${name}`;
  Promise.resolve(promise).then(result => {
    if (id !== latestEffect) return;
    effectStatus.textContent = result?.cancelled ? `Cancelled: ${name}` : `Finished: ${name}`;
  }).catch(error => {
    if (id === latestEffect) effectStatus.textContent = `Effect failed: ${error.message}`;
  });
}

const flashist = new Flashist({
  onStatus: message => { status.textContent = message; },
  onKeepalive: active => { keepalive.textContent = active ? 'Keepalive active (every 2 seconds)' : 'Keepalive inactive'; },
  onDisconnect: () => {
    setConnected(false);
    latestEffect++;
    effectStatus.textContent = 'Effects idle';
  }
});

if (!window.isSecureContext || !navigator.hid) {
  status.textContent = 'WebHID is unavailable. Open this page in a supported Chrome or Edge browser.';
  connectButton.disabled = true;
} else {
  status.textContent = 'Not connected';
}

connectButton.addEventListener('click', async () => {
  try {
    if (await flashist.connect()) {
      setConnected(true);
      effectStatus.textContent = 'Effects idle';
    }
  } catch (error) {
    status.textContent = `Could not connect: ${error.message}`;
  }
});

disconnectButton.addEventListener('click', async () => {
  try {
    await flashist.disconnect();
    setConnected(false);
    latestEffect++;
    effectStatus.textContent = 'Effects idle';
  } catch (error) {
    status.textContent = `Disconnect failed: ${error.message}`;
  }
});

function readEffectOptions(effect) {
  const controls = document.querySelector(`#${effect.id}-options`);
  return effect.options.reduce((options, option) => {
    const input = controls.querySelector(`[data-option="${option.name}"]`);
    if (!input.checkValidity()) throw new TypeError(`${option.label} is invalid`);
    if (input.value === '') return options;
    options[option.name] = Number(input.value);
    return options;
  }, {});
}

effectDefinitions.forEach(effect => {
  document.querySelector(`#${effect.id}`).addEventListener('click', () => {
    try {
      const options = readEffectOptions(effect);
      const detail = effect.id === 'thinking'
        ? ` (difficulty ${options.difficulty || 5}/10)`
        : effect.id === 'step-right-up' ? ` (attention ${options.attention || 7}/10)` : '';
      watchEffect(`${effect.label}${detail}`, flashist.replace(gameShowEffects[effect.factory](options)));
    } catch (error) {
      effectStatus.textContent = `Invalid effect options: ${error.message}`;
    }
  });
});

stopButton.addEventListener('click', async () => {
  latestEffect++;
  await flashist.stop();
  effectStatus.textContent = 'Stopped; lights off';
});
