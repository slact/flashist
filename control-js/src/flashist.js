const FRAME_MS = 1000 / 30;
const REPORT_SIZE = 64;
const RGB_COMMAND = 0x2a;
const HEARTBEAT_COMMAND = 0x3e;

export class Flashist {
  constructor(options = {}) {
    this.onStatus = options.onStatus || (() => {});
    this.onKeepalive = options.onKeepalive || (() => {});
    this.onDisconnect = options.onDisconnect || (() => {});
    this.device = null;
    this.disconnectHandler = null;
    this.heartbeatTimer = null;
    this.pendingHeartbeatFor = null;
    this.sendQueue = Promise.resolve();
    this.jobs = [];
    this.active = null;
    this.stopping = false;
    this.replacing = false;
    this.replacementGeneration = 0;
    this.closing = false;
    this.currentColor = [0, 0, 0];
  }

  async connect() {
    if (!globalThis.navigator?.hid) throw new Error('WebHID is unavailable');
    if (this.device?.opened) return true;

    const authorized = await globalThis.navigator.hid.getDevices();
    let device = authorized.find(candidate => this._isRawHidDevice(candidate));
    if (!device) {
      [device] = await globalThis.navigator.hid.requestDevice({
        filters: [{vendorId: 0x16c0, productId: 0x0486, usagePage: 0xffab, usage: 0x0200}]
      });
    }
    if (!device) {
      this.onStatus('No device selected');
      return false;
    }
    if (!this._isRawHidDevice(device)) throw new Error('Selected interface is not the 64-byte RawHID output');
    if (!device.opened) await device.open();

    this.device = device;
    this.disconnectHandler = event => {
      if (event.device !== this.device) return;
      this._stopKeepalives();
      this.closing = true;
      this.replacementGeneration++;
      this.replacing = false;
      this._cancelQueued();
      this.active?.abortController.abort();
      globalThis.navigator.hid.removeEventListener('disconnect', this.disconnectHandler);
      this.disconnectHandler = null;
      this.device = null;
      this.closing = false;
      this.onKeepalive(false);
      this.onDisconnect();
      this.onStatus('Device disconnected');
    };
    globalThis.navigator.hid.addEventListener('disconnect', this.disconnectHandler);
    this.onStatus(`Connected to ${device.productName || 'Teensy RawHID'}`);
    this._startKeepalives();
    return true;
  }

  _isRawHidDevice(device) {
    return device.collections.some(collection =>
      collection.usagePage === 0xffab &&
      collection.usage === 0x0200 &&
      collection.outputReports.some(report =>
        report.reportId === 0 &&
        report.items.reduce((bits, item) => bits + item.reportSize * item.reportCount, 0) === REPORT_SIZE * 8
      )
    );
  }

  enqueue(effect) {
    if (typeof effect !== 'function') throw new TypeError('An effect must be a function');
    if (!this.device?.opened) return Promise.reject(new Error('Connect to the device before queueing effects'));
    if (this.stopping || this.closing) return Promise.reject(new Error('Flashist is stopping'));

    return new Promise((resolve, reject) => {
      this.jobs.push({effect, resolve, reject});
      this._runNext();
    });
  }

  replace(effect) {
    if (typeof effect !== 'function') throw new TypeError('An effect must be a function');
    if (!this.device?.opened) return Promise.reject(new Error('Connect to the device before playing effects'));
    if (this.stopping || this.closing) return Promise.reject(new Error('Flashist is stopping'));

    const generation = ++this.replacementGeneration;
    this._cancelQueued();
    const active = this.active;
    active?.abortController.abort();
    this.replacing = true;

    return new Promise((resolve, reject) => {
      const job = {effect, resolve, reject};
      this.jobs.unshift(job);
      (active?.done || Promise.resolve()).then(() => {
        if (generation !== this.replacementGeneration || !this.jobs.includes(job)) return;
        this.replacing = false;
        this._runNext();
      });
    });
  }

  _runNext() {
    if (this.active || this.stopping || this.closing || this.replacing || !this.jobs.length) return;
    if (!this.device?.opened) {
      this._cancelQueued();
      return;
    }

    const job = this.jobs.shift();
    const active = {abortController: new AbortController(), done: null};
    this.active = active;
    active.done = Promise.resolve()
      .then(() => job.effect(this._effectContext(active.abortController.signal)))
      .then(value => job.resolve(value), error => {
        if (active.abortController.signal.aborted) {
          job.resolve({cancelled: true});
        } else {
          this.onStatus(`Effect failed: ${error.message}`);
          job.reject(error);
        }
      })
      .finally(() => {
        if (this.active === active) this.active = null;
        this._runNext();
      });
  }

  _cancelQueued() {
    for (const job of this.jobs.splice(0)) job.resolve({cancelled: true});
  }
  async stop() {
    if (this.stopping) return;
    this.stopping = true;
    this.replacementGeneration++;
    this.replacing = false;
    this._cancelQueued();
    const active = this.active;
    active?.abortController.abort();

    try {
      if (active?.done) await active.done;
      if (this.device?.opened) await this._writeColor([0, 0, 0]);
    } finally {
      this.stopping = false;
      this._runNext();
    }
  }




  async disconnect() {
    const device = this.device;
    if (!device) return;
    this.closing = true;

    try {
      await this.stop();
      this._stopKeepalives();
      this.device = null;
      if (this.disconnectHandler) {
        globalThis.navigator.hid.removeEventListener('disconnect', this.disconnectHandler);
        this.disconnectHandler = null;
      }
      await this.sendQueue;
      if (device.opened) await device.close();
      this.onKeepalive(false);
      this.onDisconnect();
      this.onStatus('Disconnected');
    } finally {
      this.closing = false;
      this._runNext();
    }
  }

  _effectContext(signal) {
    const fx = {
      signal,
      setColor: color => this._setColor(color, signal),
      fadeTo: (color, durationMs) => this._fadeTo(color, durationMs, signal),
      hold: (color, durationMs) => this._hold(color, durationMs, signal),
      sineWave: (color, options) => this._sineWave(color, options, signal),
      wavegen: options => this._wavegen(options, signal),
      blink: (color, options) => this._blink(color, options, signal),
      wait: durationMs => this._wait(durationMs, signal),
      repeat: async effect => {
        if (typeof effect !== 'function') throw new TypeError('A repeated effect must be a function');
        while (true) {
          this._throwIfAborted(signal);
          await effect(fx);
        }
      }
    };
    return fx;
  }

  async _setColor(color, signal) {
    await this._writeColor(this._parseColor(color), signal);
  }

  async _fadeTo(color, durationMs, signal) {
    const target = this._parseColor(color);
    const from = this.currentColor.slice();
    await this._animate(durationMs, signal, progress => {
      const eased = progress * progress * (3 - 2 * progress);
      return from.map((value, index) => value + (target[index] - value) * eased);
    });
  }

  async _hold(color, durationMs, signal) {
    await this._setColor(color, signal);
    await this._wait(durationMs, signal);
  }

  async _blink(color, options = {}, signal) {
    const times = Math.floor(this._option(options.times, 1, 1, 100000));
    const onMs = this._option(options.onMs, 250, 0, 60000);
    const offMs = this._option(options.offMs, 250, 0, 60000);
    for (let i = 0; i < times; i++) {
      await this._setColor(color, signal);
      await this._wait(onMs, signal);
      await this._setColor('#000000', signal);
      await this._wait(offMs, signal);
    }
  }

  async _sineWave(color, options = {}, signal) {
    const base = this._parseColor(color);
    const durationMs = this._option(options.durationMs, 3000, 0, 86400000);
    const fromHz = this._option(options.fromHz, 0.2, 0, 1000);
    const toHz = this._option(options.toHz, 4, 0, 1000);
    const minBrightness = this._option(options.minBrightness, 0, 0, 1);
    const maxBrightness = Math.max(minBrightness, this._option(options.maxBrightness, 1, 0, 1));
    if (!durationMs) {
      await this._writeColor(base.map(value => value * minBrightness), signal);
      return;
    }

    const durationSeconds = durationMs / 1000;
    const startedAt = performance.now();
    await this._animate(durationMs, signal, progress => {
      const elapsedSeconds = progress * durationSeconds;
      const cycles = fromHz * elapsedSeconds + (toHz - fromHz) * elapsedSeconds ** 2 / (2 * durationSeconds);
      const wave = (Math.sin(2 * Math.PI * cycles - Math.PI / 2) + 1) / 2;
      const brightness = minBrightness + (maxBrightness - minBrightness) * wave;
      return base.map(value => value * brightness);
    }, startedAt);
  }

  async _wavegen(options = {}, signal) {
    const durationMs = options.durationMs === undefined ? Infinity : this._option(options.durationMs, 0, 0, 86400000);
    const colorSpeed = this._option(options.colorCyclingSpeed, 0.003, 0, 0.1);
    const brightnessSpeed = this._option(options.brightnessCyclingSpeed, 0.001, 0, 0.08);
    const min = this._option(options.brightnessCyclingMin, 0, 0, 1);
    const max = Math.max(min, this._option(options.brightnessCyclingMax, 1, 0, 1));
    const startedAt = performance.now();
    let hue = 0;
    let brightnessPhase = 0;

    while (true) {
      this._throwIfAborted(signal);
      const brightness = this._wave(brightnessPhase);
      const range = max - min;
      const color = [
        this._wave(hue),
        this._wave(hue + 1 / 3),
        this._wave(hue + 2 / 3)
      ].map(value => min + value * brightness * range);
      await this._writeColor(color, signal);
      hue = (hue + colorSpeed) % 1;
      brightnessPhase = (brightnessPhase + brightnessSpeed) % 1;
      if (performance.now() - startedAt >= durationMs) return;
      await this._wait(FRAME_MS, signal);
    }
  }

  async _animate(durationMs, signal, colorAt, startedAt = performance.now()) {
    const duration = this._option(durationMs, 0, 0, 86400000);
    while (true) {
      this._throwIfAborted(signal);
      const progress = duration ? Math.min(1, (performance.now() - startedAt) / duration) : 1;
      await this._writeColor(colorAt(progress), signal);
      if (progress >= 1) return;
      await this._wait(FRAME_MS, signal);
    }
  }

  _wave(phase) {
    return (Math.sin(phase * 2 * Math.PI - Math.PI / 2) + 1) / 2;
  }

  _parseColor(color) {
    const match = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(color);
    if (!match) throw new TypeError('Expected a six-digit RGB hex color');
    return [1, 2, 3].map(index => parseInt(match[index], 16) / 255);
  }

  _option(value, fallback, min, max) {
    const number = Number(value === undefined ? fallback : value);
    if (!Number.isFinite(number)) throw new TypeError('Effect options must be finite numbers');
    return Math.max(min, Math.min(max, number));
  }

  async _writeColor(color, signal) {
    if (signal) this._throwIfAborted(signal);
    const device = this.device;
    if (!device?.opened) throw new Error('Flashist is not connected');
    const payload = color.map(value => Math.max(0, Math.min(255, Math.trunc(value * 255))));
    const sent = await this._sendPacket(device, RGB_COMMAND, payload);
    if (!sent) {
      if (signal) this._throwIfAborted(signal);
      throw new Error('HID device disconnected');
    }
    this.currentColor = color.slice();
  }

  _startKeepalives() {
    this._stopKeepalives();
    this.heartbeatTimer = globalThis.setInterval(() => {
      const device = this.device;
      if (!device?.opened || this.pendingHeartbeatFor === device) return;
      this.pendingHeartbeatFor = device;
      this._sendPacket(device, HEARTBEAT_COMMAND)
        .then(sent => {
          if (sent && this.device === device) this.onKeepalive(true);
        })
        .catch(() => {})
        .finally(() => {
          if (this.pendingHeartbeatFor === device) this.pendingHeartbeatFor = null;
        });
    }, 2000);
  }

  _stopKeepalives() {
    if (this.heartbeatTimer === null) return;
    globalThis.clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = null;
  }

  _sendPacket(device, command, payload = []) {
    const report = new Uint8Array(REPORT_SIZE);
    report.set([command, ...payload]);
    const pending = this.sendQueue.then(async () => {
      if (this.device !== device || !device.opened) return false;
      await device.sendReport(0, report);
      return true;
    });
    this.sendQueue = pending.catch(error => {
      if (this.device === device) this.onStatus(`WebHID write failed: ${error.message}`);
    });
    return pending;
  }

  _throwIfAborted(signal) {
    if (!signal.aborted) return;
    const error = new Error('Effect cancelled');
    error.name = 'AbortError';
    throw error;
  }

  _wait(durationMs, signal) {
    this._throwIfAborted(signal);
    const duration = this._option(durationMs, 0, 0, 86400000);
    return new Promise((resolve, reject) => {
      let timer;
      const abort = () => {
        globalThis.clearTimeout(timer);
        signal.removeEventListener('abort', abort);
        const error = new Error('Effect cancelled');
        error.name = 'AbortError';
        reject(error);
      };
      timer = globalThis.setTimeout(() => {
        signal.removeEventListener('abort', abort);
        resolve();
      }, duration);
      signal.addEventListener('abort', abort, {once: true});
    });
  }
}

